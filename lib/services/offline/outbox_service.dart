import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sembast/sembast_io.dart';

import '../pb_data_service.dart';
import '../pb_media_service.dart';
import 'backoff.dart';
import 'connectivity_service.dart';
import 'local_store.dart';

/// Очередь офлайн-записи (outbox).
///
/// Мутации сначала оптимистично попадают в локальный кэш (UI обновляется сразу),
/// затем кладутся СЮДА; при наличии сети очередь сливается на сервер по FIFO.
/// Хранится в том же sembast-файле, что и кэш (стор `outbox`, авто-инкрементный
/// ключ = порядок отправки), поэтому переживает перезапуск и чистится вместе с
/// кэшем при выходе/смене пользователя.
///
/// Идемпотентность: операции построены так, чтобы повтор после «ложного провала»
/// (ответ потерян, но сервер применил) не ломал данные — upsert по id, delete с
/// 404-как-успех, set-saved по желаемому состоянию. Исключение — counterInc
/// (инкремент счётчика-подсказки): возможен косметический дрейф, как и в текущем
/// онлайн-коде.
class OutboxService {
  OutboxService._();
  static final OutboxService instance = OutboxService._();
  factory OutboxService() => instance;

  final StoreRef<int, Map<String, Object?>> _store =
      intMapStoreFactory.store('outbox');
  final StoreRef<int, Map<String, Object?>> _poison =
      intMapStoreFactory.store('outbox_poison');
  static const int _maxAttempts = 8;

  bool _flushing = false;
  int _retryAttempt = 0;
  Timer? _retryTimer;
  StreamSubscription<bool>? _connSub;

  /// Число операций в очереди (для индикатора «ожидает синхронизации»).
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Число «ядовитых» операций (сервер упорно отвергает) — для UI повтора.
  final ValueNotifier<int> poisonCount = ValueNotifier<int>(0);

  /// Ключ операции, которую прямо сейчас обрабатывает flush — коалесинг в неё НЕ
  /// мёржит (иначе гонка: применилось бы старое, а новое потерялось при delete).
  int? _inflightKey;

  Future<void> init() async {
    _connSub ??= ConnectivityService.instance.onOnlineChanged.listen((online) {
      if (online) unawaited(flush());
    });
    await _updatePending();
    unawaited(flush()); // дослать то, что осталось с прошлой офлайн-сессии
  }

  /// Поставить операцию в очередь. Онлайн → сразу пробуем слить.
  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    final db = await LocalStore.instance.database();
    if (db == null) return;
    // Коалесинг: склеиваем/заменяем совместимые операции, чтобы не копить дубли
    // (повторные инкременты, многократные правки одного поля и т.п.).
    final merged = await _coalesce(db, type, payload);
    if (!merged) {
      await _store.add(db, {'type': type, 'payload': payload, 'attempts': 0});
    }
    await _updatePending();
    if (ConnectivityService.instance.isOnline) unawaited(flush());
  }

  /// Слить очередь (строгий FIFO). Защищён от параллельного запуска.
  Future<void> flush() async {
    if (_flushing || !ConnectivityService.instance.isOnline) return;
    final db = await LocalStore.instance.database();
    if (db == null) return;
    _flushing = true;
    try {
      while (true) {
        final snaps = await _store.find(
          db,
          finder: Finder(sortOrders: [SortOrder(Field.key)], limit: 1),
        );
        if (snaps.isEmpty) {
          _retryAttempt = 0;
          break;
        }
        final snap = snaps.first;
        _inflightKey = snap.key; // коалесинг не должен мёржить в обрабатываемую
        final type = snap.value['type'] as String? ?? '';
        final payload =
            Map<String, dynamic>.from((snap.value['payload'] as Map?) ?? const {});
        final attempts = (snap.value['attempts'] as num?)?.toInt() ?? 0;

        final ok = await _apply(type, payload);
        if (ok) {
          await _store.record(snap.key).delete(db);
          _inflightKey = null;
          continue;
        }
        // Провал: считаем попытки. Сервис-методы PB глотают ошибку и возвращают
        // false (не отличить транзиент от перманента) → отправляем в «отравленные»
        // по лимиту попыток, чтобы одна битая операция не блокировала очередь.
        final next = attempts + 1;
        if (next >= _maxAttempts) {
          await _poison.add(db, {
            ...snap.value,
            'attempts': next,
            'failedAt': DateTime.now().toIso8601String(),
          });
          await _store.record(snap.key).delete(db);
          _inflightKey = null;
          debugPrint('Outbox: операция «$type» отравлена после $next попыток');
          continue;
        }
        await _store.record(snap.key).update(db, {'attempts': next});
        _inflightKey = null;
        _scheduleRetry();
        break; // не долбим дальше — ждём ретрая/сети
      }
    } catch (e) {
      debugPrint('Outbox.flush error: $e');
      _scheduleRetry();
    } finally {
      _inflightKey = null;
      _flushing = false;
      await _updatePending();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final ms = backoffMs(_retryAttempt);
    _retryAttempt++;
    _retryTimer = Timer(Duration(milliseconds: ms), () {
      if (ConnectivityService.instance.isOnline) unawaited(flush());
    });
  }

  Future<void> _updatePending() async {
    final db = await LocalStore.instance.database();
    pendingCount.value = db == null ? 0 : await _store.count(db);
    poisonCount.value = db == null ? 0 : await _poison.count(db);
  }

  /// Полная очистка очереди (logout/смена пользователя).
  Future<void> clear() async {
    final db = await LocalStore.instance.database();
    if (db != null) {
      await _store.delete(db);
      await _poison.delete(db);
    }
    pendingCount.value = 0;
    poisonCount.value = 0;
  }

  /// Повторить «ядовитые» операции (тап в индикаторе): вернуть в очередь со
  /// сбросом попыток и слить.
  Future<void> retryPoison() async {
    final db = await LocalStore.instance.database();
    if (db == null) return;
    final items = await _poison.find(db);
    for (final s in items) {
      await _store.add(db, {
        'type': s.value['type'],
        'payload': s.value['payload'],
        'attempts': 0,
      });
      await _poison.record(s.key).delete(db);
    }
    await _updatePending();
    unawaited(flush());
  }

  // ── коалесинг очереди ───────────────────────────────────────────────────────
  /// Склеить новую операцию с уже стоящей (если совместимы). true — смержили в
  /// существующую (новую добавлять не нужно). Операцию, обрабатываемую flush
  /// (`_inflightKey`), не трогаем.
  Future<bool> _coalesce(
      Database db, String type, Map<String, dynamic> p) async {
    switch (type) {
      case 'counterInc':
        return _replaceOrMerge(
          db,
          type,
          p,
          (a, b) => a['groupId'] == b['groupId'] && a['field'] == b['field'],
          merge: (o, n) => {
            ...o,
            'by': ((o['by'] as num?)?.toInt() ?? 0) +
                ((n['by'] as num?)?.toInt() ?? 0),
          },
        );
      case 'groupUpdateFields':
        return _replaceOrMerge(
          db,
          type,
          p,
          (a, b) => a['groupId'] == b['groupId'],
          merge: (o, n) => {
            ...o,
            'cols': {
              ...?(o['cols'] as Map?)?.cast<String, dynamic>(),
              ...?(n['cols'] as Map?)?.cast<String, dynamic>(),
            },
          },
        );
      case 'chatUpdate':
        return _replaceOrMerge(
          db,
          type,
          p,
          (a, b) => a['id'] == b['id'],
          merge: (o, n) => {
            ...o,
            'fields': {
              ...?(o['fields'] as Map?)?.cast<String, dynamic>(),
              ...?(n['fields'] as Map?)?.cast<String, dynamic>(),
            },
          },
        );
      case 'groupSetMemberMood':
      case 'groupSetMemberAilment':
        return _replaceOrMerge(db, type, p,
            (a, b) => a['groupId'] == b['groupId'] && a['uid'] == b['uid']);
      case 'groupSetStatus':
        return _replaceOrMerge(
            db, type, p, (a, b) => a['groupId'] == b['groupId']);
      case 'chatSetReaction':
        return _replaceOrMerge(db, type, p,
            (a, b) => a['id'] == b['id'] && a['uid'] == b['uid']);
      case 'memorySetSaved':
        return _replaceOrMerge(db, type, p,
            (a, b) => a['memoryId'] == b['memoryId'] && a['uid'] == b['uid']);
      case 'memoryUpsert':
        return _replaceOrMerge(db, type, p, (a, b) => a['id'] == b['id']);
      case 'memoryDelete':
        // create+delete аннигиляция: убрать ещё не отправленный memoryUpsert того
        // же id (создавать-затем-удалять на сервере не нужно). Сам delete ставим
        // (404 = успех, если записи на сервере уже/ещё нет).
        final pend = await _store.find(db);
        for (final s in pend) {
          if (s.key == _inflightKey) continue;
          if (s.value['type'] == 'memoryUpsert') {
            final pp = Map<String, dynamic>.from(
                (s.value['payload'] as Map?) ?? const {});
            if (pp['id'] == p['id']) await _store.record(s.key).delete(db);
          }
        }
        return false;
      default:
        return false;
    }
  }

  Future<bool> _replaceOrMerge(
    Database db,
    String type,
    Map<String, dynamic> payload,
    bool Function(Map<String, dynamic> existing, Map<String, dynamic> incoming)
        sameKey, {
    Map<String, dynamic> Function(
            Map<String, dynamic> old, Map<String, dynamic> incoming)?
        merge,
  }) async {
    final pend = await _store.find(db,
        finder: Finder(sortOrders: [SortOrder(Field.key)]));
    for (final s in pend) {
      if (s.key == _inflightKey || s.value['type'] != type) continue;
      final existing =
          Map<String, dynamic>.from((s.value['payload'] as Map?) ?? const {});
      if (sameKey(existing, payload)) {
        final next = merge != null ? merge(existing, payload) : payload;
        await _store.record(s.key).update(db, {'payload': next});
        return true;
      }
    }
    return false;
  }

  // ── исполнение операций ────────────────────────────────────────────────────
  Future<bool> _apply(String type, Map<String, dynamic> p) async {
    final data = PbDataService();
    switch (type) {
      case 'memoryUpsert':
        return data.upsertMemory(
          p['groupId'] as String? ?? '',
          p['id'] as String? ?? '',
          Map<String, dynamic>.from(p['data'] as Map? ?? const {}),
        );
      case 'memoryDelete':
        final media = PbMediaService();
        for (final ref in (p['mediaRefs'] as List? ?? const [])) {
          if (ref is String && media.isPbRef(ref)) {
            try {
              await media.delete(ref);
            } catch (_) {}
          }
        }
        return data.deleteMemory(p['id'] as String? ?? '', hard: true);
      case 'memorySetSaved':
        return _applySetSaved(
          p['memoryId'] as String? ?? '',
          p['uid'] as String? ?? '',
          p['saved'] == true,
        );
      case 'counterInc':
        return data.incrementGroupCounter(
          p['groupId'] as String? ?? '',
          p['field'] as String? ?? '',
          (p['by'] as num?)?.toInt() ?? 0,
        );
      // ── настроения ──
      case 'moodUpsert':
        return data.upsertMood(
          p['groupId'] as String? ?? '',
          p['uid'] as String? ?? '',
          Map<String, dynamic>.from(p['entry'] as Map? ?? const {}),
        );
      case 'moodDelete':
        return data.deleteMood(p['id'] as String? ?? '');
      // ── комментарии ──
      case 'commentUpsert':
        return data.upsertComment(
          p['groupId'] as String? ?? '',
          p['memoryId'] as String? ?? '',
          p['id'] as String? ?? '',
          Map<String, dynamic>.from(p['data'] as Map? ?? const {}),
        );
      case 'commentDelete':
        return data.deleteComment(p['id'] as String? ?? '');
      case 'memoryBumpComments':
        return _applyBumpComments(
          p['groupId'] as String? ?? '',
          p['memoryId'] as String? ?? '',
          (p['by'] as num?)?.toInt() ?? 0,
        );
      // ── чат ──
      case 'chatUpsert':
        return data.chatSend(
          p['groupId'] as String? ?? '',
          p['id'] as String? ?? '',
          Map<String, dynamic>.from(p['msg'] as Map? ?? const {}),
        );
      case 'chatUpdate':
        return data.chatUpdate(
          p['id'] as String? ?? '',
          Map<String, dynamic>.from(p['fields'] as Map? ?? const {}),
        );
      case 'chatSetReaction':
        return data.setChatReaction(
          p['id'] as String? ?? '',
          p['uid'] as String? ?? '',
          p['emoji'] as String?, // null/'' → снять (setChatReaction идемпотентен)
        );
      // ── маскоты ──
      case 'mascotUpsert':
        return data.upsertMascot(p['groupId'] as String? ?? '',
            Map<String, dynamic>.from(p['mascot'] as Map? ?? const {}));
      case 'mascotDelete':
        return data.deleteMascot(
            p['groupId'] as String? ?? '', p['mascotId'] as String? ?? '');
      case 'mascotUpdateFields':
        return data.updateMascotFields(
            p['groupId'] as String? ?? '',
            p['mascotId'] as String? ?? '',
            Map<String, dynamic>.from(p['cols'] as Map? ?? const {}));
      // ── поля группы (настроение/самочувствие/статус/маскот) ──
      case 'groupSetMemberMood':
        final gid = p['groupId'] as String? ?? '';
        final uid = p['uid'] as String? ?? '';
        final mood = p['mood'];
        return mood == null
            ? data.clearMemberMood(gid, uid)
            : data.setMemberMood(gid, uid, mood);
      case 'groupSetMemberAilment':
        final gid = p['groupId'] as String? ?? '';
        final uid = p['uid'] as String? ?? '';
        final ail = p['ailment'];
        return ail == null
            ? data.clearMemberAilment(gid, uid)
            : data.setMemberAilment(
                gid, uid, Map<String, dynamic>.from(ail as Map));
      case 'groupSetStatus':
        final gid = p['groupId'] as String? ?? '';
        final st = p['status'];
        return st == null
            ? data.clearGroupStatus(gid)
            : data.setGroupStatus(gid, Map<String, dynamic>.from(st as Map));
      case 'groupUpdateFields':
        return data.updateGroupFields(p['groupId'] as String? ?? '',
            Map<String, dynamic>.from(p['cols'] as Map? ?? const {}));
      default:
        debugPrint('Outbox: неизвестный тип «$type» — пропускаю');
        return true; // не зацикливаем неизвестное
    }
  }

  /// RMW счётчика комментариев в json `data` воспоминания (бейдж в ленте).
  /// Не идемпотентен (как и counterInc) — возможен косметический дрейф бейджа.
  Future<bool> _applyBumpComments(
      String groupId, String memoryId, int by) async {
    if (memoryId.isEmpty || by == 0) return true;
    final data = PbDataService();
    final rec = await data.loadMemoryById(memoryId);
    if (rec == null) return true;
    final raw = rec.data['data'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    map['commentsCount'] = ((map['commentsCount'] as num?)?.toInt() ?? 0) + by;
    return data.upsertMemory(
        rec.data['group_id'] as String? ?? groupId, memoryId, map);
  }

  /// Идемпотентный RMW «избранное»: читаем АКТУАЛЬНОЕ серверное состояние и
  /// приводим присутствие своего uid к желаемому [saved] (а не пишем стейл-список
  /// из кэша) — не затираем правку партнёра, и повтор операции безопасен.
  Future<bool> _applySetSaved(String memoryId, String uid, bool saved) async {
    if (memoryId.isEmpty || uid.isEmpty) return true;
    final data = PbDataService();
    final rec = await data.loadMemoryById(memoryId);
    if (rec == null) return true; // удалено на сервере — считаем выполненным
    final raw = rec.data['data'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final list = (map['savedBy'] is List)
        ? List<String>.from((map['savedBy'] as List).map((e) => e.toString()))
        : <String>[];
    final has = list.contains(uid);
    if (saved && !has) {
      list.add(uid);
    } else if (!saved && has) {
      list.remove(uid);
    } else {
      return true; // уже в нужном состоянии — идемпотентно
    }
    map['savedBy'] = list;
    return data.upsertMemory(
        rec.data['group_id'] as String? ?? '', memoryId, map);
  }
}
