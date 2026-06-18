import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_msg.dart';
import '../config/migration_config.dart';
import 'firebase_service.dart';
import 'supabase_service.dart';

/// URL базы Realtime Database (регион europe-west1 — не дефолтный).
const String _kChatRtdbUrl =
    'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app';

/// Сервис постоянного текстового чата пары.
///
/// История сообщений хранится ТОЛЬКО в Realtime Database — это даёт ноль
/// Firestore-чтений независимо от числа сообщений и открытий чата. Firestore
/// используется лишь как разовый триггер push-уведомления (документ-событие,
/// который Cloud Function удаляет сразу после отправки FCM).
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final FirebaseService _fb = FirebaseService();
  final SupabaseService _sb = SupabaseService();

  /// Фаза 1: зеркалим чат в Supabase и читаем оттуда.
  bool get _mig =>
      MigrationConfig.isConfigured &&
      MigrationConfig.isPhase1User(_fb.currentUser?.email);

  /// Stage 2 (постепенный переезд): пишем в оба склада (RTDB — источник, его
  /// читают обе версии + зеркало в Supabase), читаем из RTDB пока вся группа не
  /// на новой сборке.
  bool get _dualWrite => _mig;

  /// Можно ли ЧИТАТЬ чат этой группы из Supabase. Stage 3: true только когда
  /// группа помечена в прошлой сессии (оба партнёра на новой сборке + бэкфилл
  /// завершён, см. FirebaseService.readFromSupabase); иначе читаем из RTDB
  /// (общий источник, его пишут обе версии) — безопасный дефолт.
  bool _readSb(String groupId) => _fb.readFromSupabase(groupId);

  /// Stage 4: писать ли чат в RTDB (Firebase). Для полностью мигрированной группы
  /// — нет: чат живёт только в Supabase. См. FirebaseService.writeToFirebase.
  bool _writeFb(String groupId) => _fb.writeToFirebase(groupId);

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _kChatRtdbUrl,
      );

  DatabaseReference _messagesRef(String groupId) =>
      _db.ref('chats/$groupId/messages');

  /// Узел статусов прочтения {uid: lastReadTs} — для галочек «прочитано».
  DatabaseReference _readsRef(String groupId) =>
      _db.ref('chats/$groupId/reads');

  String get _uid => _fb.uid ?? '';

  /// Регистрирует пользователя в members чата (нужно для security-rules:
  /// читать/писать может только участник). Вызывается при открытии чата и
  /// перед первой отправкой. Идемпотентно.
  Future<void> ensureMember(String groupId) async {
    if (groupId.isEmpty || _uid.isEmpty) return;
    if (!_writeFb(groupId)) return; // Stage 4: мигрированная группа не пишет RTDB
    // Stage 2: пишем в RTDB (источник) → членство в RTDB снова нужно для правил.
    try {
      await _db.ref('chats/$groupId/members/$_uid').set(true);
    } catch (e) {
      debugPrint('ChatService.ensureMember failed: $e');
    }
  }

  /// Бэкфилл ВСЕЙ истории чата группы RTDB → Supabase (для миграции Фазы 1).
  ///
  /// Идемпотентен (upsert по id сообщения), поэтому безопасно повторять. Каждое
  /// сообщение зеркалится через mirrorChatSend (повтор+бэкофф внутри), а правки/
  /// удаления/реакции — через mirrorChatUpdate. Возвращает число НЕперенесённых
  /// сообщений — оркестратор не ставит флаг «готово», пока оно > 0, и повторяет.
  Future<int> backfillToSupabase(String groupId) async {
    if (!_mig || groupId.isEmpty) return 0;
    var failures = 0;
    try {
      final snap = await _messagesRef(groupId).get();
      for (final child in snap.children) {
        final msg = ChatMsg.fromSnapshot(child);
        if (msg.id.isEmpty) continue;
        final ok = await _sb.mirrorChatSend(
          groupId: groupId,
          id: msg.id,
          uid: msg.uid,
          name: msg.name,
          text: msg.text,
          ts: msg.ts,
          pinId: msg.pinId,
          pinTitle: msg.pinTitle,
          pinThumb: msg.pinThumb,
        );
        if (!ok) {
          failures++;
          continue;
        }
        // Правки/удаления/реакции не покрываются базовым upsert'ом отправки.
        final extra = <String, dynamic>{};
        if (msg.deleted) extra['deleted'] = true;
        if (msg.editedTs != null) extra['edited_ts'] = msg.editedTs;
        if (msg.reactions.isNotEmpty) extra['reactions'] = msg.reactions;
        if (extra.isNotEmpty) {
          final ok2 = await _sb.mirrorChatUpdate(msg.id, extra);
          if (!ok2) failures++;
        }
      }
      // ── Статусы прочтения (галочки) RTDB reads/{uid} → chat_reads ──
      final reads = await _readsRef(groupId).get();
      final rv = reads.value;
      if (rv is Map) {
        for (final entry in rv.entries) {
          final ruid = entry.key.toString();
          final rts = (entry.value as num?)?.toInt() ?? 0;
          if (ruid.isEmpty || rts <= 0) continue;
          if (!await _sb.mirrorChatRead(groupId, ruid, rts)) failures++;
        }
      }
    } catch (e) {
      debugPrint('ChatService.backfillToSupabase($groupId) failed: $e');
      failures++; // не вышло прочитать RTDB — повторим позже
    }
    return failures;
  }

  /// Поток последних [limit] сообщений, отсортированных по времени.
  Stream<List<ChatMsg>> watchMessages(String groupId, {int limit = 100}) {
    if (groupId.isEmpty) return const Stream.empty();
    // Читаем сообщения из RTDB (общий источник); Stage 3 — из Supabase.
    if (_readSb(groupId)) return _sb.watchMessages(groupId, limit: limit);
    return _messagesRef(groupId)
        .orderByChild('ts')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final children = event.snapshot.children
          .map(ChatMsg.fromSnapshot)
          .toList()
        ..sort((a, b) => a.ts.compareTo(b.ts));
      return children;
    });
  }

  /// Отправить сообщение. [pinId]/[pinTitle] — опционально прикреплённый пин.
  Future<void> send({
    required String groupId,
    required String senderName,
    required String text,
    String? pinId,
    String? pinTitle,
    String? pinThumb,
    String? replyToId,
    String? replyToName,
    String? replyToText,
    String? face,
    int? color,
    double? faceX,
    double? faceY,
  }) async {
    final trimmed = text.trim();
    if (groupId.isEmpty || _uid.isEmpty || trimmed.isEmpty) return;
    try {
      // Двойная запись: RTDB (источник, читают обе версии) + зеркало в Supabase
      // под ОДНИМ id (RTDB push-key — клиентский, доступен без записи), чтобы
      // Stage 3 не задвоил. Stage 4: для мигрированной группы RTDB пропускаем.
      final ref = _messagesRef(groupId).push();
      final id = ref.key ?? DateTime.now().microsecondsSinceEpoch.toString();
      if (_writeFb(groupId)) {
        await ensureMember(groupId);
        await ref.set({
          'uid': _uid,
          'name': senderName,
          'text': trimmed,
          'ts': ServerValue.timestamp,
          if (pinId != null) 'pinId': pinId,
          if (pinTitle != null) 'pinTitle': pinTitle,
          if (pinThumb != null) 'pinThumb': pinThumb,
          if (replyToId != null) 'replyToId': replyToId,
          if (replyToName != null) 'replyToName': replyToName,
          if (replyToText != null) 'replyToText': replyToText,
          if (face != null) 'face': face,
          if (color != null) 'color': color,
          if (faceX != null) 'faceX': faceX,
          if (faceY != null) 'faceY': faceY,
        });
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorChatSend(
          groupId: groupId,
          id: id,
          uid: _uid,
          name: senderName,
          text: trimmed,
          ts: DateTime.now().millisecondsSinceEpoch,
          pinId: pinId,
          pinTitle: pinTitle,
          pinThumb: pinThumb,
          replyToId: replyToId,
          replyToName: replyToName,
          replyToText: replyToText,
          face: face,
          color: color,
          faceX: faceX,
          faceY: faceY,
        ));
      }
      // Триггер push-уведомления через Firestore-событие (его удаляет CF).
      unawaited(_fb.sendChatPush(
        groupId: groupId,
        senderName: senderName,
        text: trimmed,
      ));
    } catch (e) {
      debugPrint('ChatService.send failed: $e');
    }
  }

  /// Редактировать своё сообщение. Помимо текста переписываем оформление
  /// (мордочка/цвет/позиция) — null-значения СТИРАЮТ поле (update в RTDB и
  /// колонку в Supabase), чтобы можно было снять лицо/вернуть цвет темы.
  Future<void> edit({
    required String groupId,
    required String messageId,
    required String newText,
    String? face,
    int? color,
    double? faceX,
    double? faceY,
  }) async {
    final trimmed = newText.trim();
    if (groupId.isEmpty || messageId.isEmpty || trimmed.isEmpty) return;
    try {
      if (_writeFb(groupId)) {
        await _messagesRef(groupId).child(messageId).update({
          'text': trimmed,
          'editedTs': ServerValue.timestamp,
          'face': face,
          'color': color,
          'faceX': faceX,
          'faceY': faceY,
        });
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorChatUpdate(messageId, {
          'text': trimmed,
          'edited_ts': DateTime.now().millisecondsSinceEpoch,
          'face': face,
          'color': color,
          'face_x': faceX,
          'face_y': faceY,
        }));
      }
    } catch (e) {
      debugPrint('ChatService.edit failed: $e');
    }
  }

  /// Мягко удалить сообщение (томбстоун — партнёр видит «сообщение удалено»).
  Future<void> delete({
    required String groupId,
    required String messageId,
  }) async {
    if (groupId.isEmpty || messageId.isEmpty) return;
    try {
      if (_writeFb(groupId)) {
        await _messagesRef(groupId).child(messageId).update({
          'deleted': true,
          'text': '',
          'pinId': null,
          'pinTitle': null,
          'editedTs': ServerValue.timestamp,
        });
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorChatUpdate(messageId, {
          'deleted': true,
          'text': '',
          'pin_id': null,
          'pin_title': null,
          'edited_ts': DateTime.now().millisecondsSinceEpoch,
        }));
      }
    } catch (e) {
      debugPrint('ChatService.delete failed: $e');
    }
  }

  /// Поставить/снять свою реакцию на сообщение. [emoji] == null убирает её.
  /// Один эмодзи на пользователя: новый перезаписывает прежний.
  /// Пишется в messages/{id}/reactions/{uid} — каскадно покрыто write-правилом
  /// чата (писать может только участник группы).
  Future<void> setReaction({
    required String groupId,
    required String messageId,
    required String? emoji,
  }) async {
    if (groupId.isEmpty || messageId.isEmpty || _uid.isEmpty) return;
    try {
      if (_writeFb(groupId)) {
        final reactionsRef =
            _messagesRef(groupId).child(messageId).child('reactions');
        final ref = reactionsRef.child(_uid);
        if (emoji == null || emoji.isEmpty) {
          await ref.remove();
        } else {
          await ref.set(emoji);
        }
      }
      // Зеркало в Supabase: атомарный RPC (jsonb_set/minus), один эмодзи на uid.
      if (_dualWrite) unawaited(_sb.setChatReaction(messageId, _uid, emoji));
    } catch (e) {
      debugPrint('ChatService.setReaction failed: $e');
    }
  }

  // ── «Печатает…» (эфемерный презенс) ─────────────────────────────────────────
  // Живёт в RTDB chats/{groupId}/typing/{uid}=ts (как presence/missYou) для ВСЕХ
  // групп независимо от стадии миграции — это не данные, а живой статус. Ноль
  // Firestore/Supabase. onDisconnect снимает маркер при обрыве связи.

  DatabaseReference _typingRef(String groupId) =>
      _db.ref('chats/$groupId/typing');

  /// Пометить «я печатаю» / снять. Маркер обновляется клиентом раз в ~3с пока
  /// идёт ввод и снимается при отправке/очистке/уходе с экрана.
  Future<void> setTyping(String groupId, bool typing) async {
    if (groupId.isEmpty || _uid.isEmpty) return;
    try {
      final ref = _typingRef(groupId).child(_uid);
      if (typing) {
        unawaited(ref.onDisconnect().remove());
        await ref.set(ServerValue.timestamp);
      } else {
        await ref.remove();
      }
    } catch (e) {
      debugPrint('ChatService.setTyping failed: $e');
    }
  }

  /// true — партнёр сейчас печатает (его маркер свежий, < 8с).
  Stream<bool> watchTyping(String groupId) {
    if (groupId.isEmpty) return Stream.value(false);
    return _typingRef(groupId).onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in v.entries) {
        if (entry.key.toString() == _uid) continue; // свой маркер не считаем
        final ts = (entry.value as num?)?.toInt() ?? 0;
        if (now - ts < 8000) return true;
      }
      return false;
    });
  }

  // ── Непрочитанные ──────────────────────────────────────────────────────────

  String _lastReadKey(String groupId) => 'chat_last_read_$groupId';

  // Кэш последнего опубликованного в RTDB ts прочтения по группам — markRead
  // зовётся на каждый кадр, поэтому пишем в сеть только при росте значения.
  final Map<String, int> _syncedReadTs = {};

  /// Отметить чат прочитанным: локально (ts последнего открытия) + публикуем
  /// в RTDB `chats/{groupId}/reads/{uid}`, чтобы партнёр увидел галочку.
  Future<void> markRead(String groupId, int lastMessageTs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastReadKey(groupId), lastMessageTs);

    if (groupId.isEmpty || _uid.isEmpty || lastMessageTs <= 0) return;
    if ((_syncedReadTs[groupId] ?? 0) >= lastMessageTs) return;
    _syncedReadTs[groupId] = lastMessageTs;
    try {
      if (_writeFb(groupId)) {
        await _readsRef(groupId).child(_uid).set(lastMessageTs);
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorChatRead(groupId, _uid, lastMessageTs));
      }
    } catch (e) {
      _syncedReadTs.remove(groupId); // не вышло — позволим повторить позже
      debugPrint('ChatService.markRead publish failed: $e');
    }
  }

  /// Поток статусов прочтения {uid: lastReadTs}. Для галочек «прочитано»:
  /// своё сообщение прочитано, если его ts ≤ минимального ts среди остальных.
  Stream<Map<String, int>> watchReads(String groupId) {
    if (groupId.isEmpty) return const Stream.empty();
    if (_readSb(groupId)) return _sb.watchChatReads(groupId);
    return _readsRef(groupId).onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <String, int>{};
      final out = <String, int>{};
      v.forEach((k, val) => out[k.toString()] = (val as num?)?.toInt() ?? 0);
      return out;
    });
  }

  Future<int> _lastRead(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastReadKey(groupId)) ?? 0;
  }

  /// ts последнего прочтения — публично, для разделителя «новые сообщения».
  Future<int> lastReadTs(String groupId) => _lastRead(groupId);

  // ── Фон чата (локальный, у каждого свой) ────────────────────────────────────

  String _bgKey(String groupId) => 'chat_bg_$groupId';

  /// Путь к локальному файлу фона чата (null — фон не задан).
  Future<String?> backgroundPath(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_bgKey(groupId));
  }

  Future<void> setBackgroundPath(String groupId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bgKey(groupId), path);
  }

  Future<void> clearBackground(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bgKey(groupId));
  }

  // ── Позиция прокрутки (локально, чтобы вернуться ровно туда же) ──────────────

  String _scrollKey(String groupId) => 'chat_scroll_$groupId';

  /// Сохранить позицию прокрутки чата (px от верха) — при перезаходе вернём
  /// человека ровно туда, где он остановился.
  Future<void> saveScrollOffset(String groupId, double px) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scrollKey(groupId), px);
    } catch (_) {}
  }

  /// Сохранённая позиция прокрутки (null — не сохранена).
  Future<double?> loadScrollOffset(String groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_scrollKey(groupId));
    } catch (_) {
      return null;
    }
  }

  // ── Недавние цвета сообщений (до 5, глобально) ──────────────────────────────

  static const String _kRecentColors = 'chat_recent_colors';

  Future<List<int>> loadRecentColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_kRecentColors) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRecentColors(List<int> colors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _kRecentColors, colors.map((c) => '$c').toList());
    } catch (_) {}
  }

  /// Поток: есть ли непрочитанные сообщения от партнёра (для красной точки).
  /// Слушает только последнее сообщение — минимальный трафик RTDB.
  Stream<bool> watchHasUnread(String groupId) {
    if (groupId.isEmpty) return Stream.value(false);
    if (_readSb(groupId)) {
      // Последнее сообщение из Supabase (chat_messages, ts DESC limit 1).
      return _sb.watchLastMessage(groupId).asyncMap((last) async {
        if (last == null) return false;
        if (last.uid == _uid) return false; // своё сообщение
        if (last.deleted) return false;
        final lastRead = await _lastRead(groupId);
        return last.ts > lastRead;
      });
    }
    return _messagesRef(groupId).orderByChild('ts').limitToLast(1).onValue.asyncMap(
      (event) async {
        if (event.snapshot.children.isEmpty) return false;
        final last = ChatMsg.fromSnapshot(event.snapshot.children.first);
        if (last.uid == _uid) return false; // своё сообщение
        if (last.deleted) return false;
        final lastRead = await _lastRead(groupId);
        return last.ts > lastRead;
      },
    );
  }
}
