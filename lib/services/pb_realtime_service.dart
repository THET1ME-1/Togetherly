import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_service.dart';

/// Realtime-слой PocketBase (миграция Firebase→PB, Этап 6).
///
/// Заменяет Firestore-листенеры и RTDB живыми SSE-подписками. ВАЖНО (директива
/// пользователя): на self-hosted PB чтения БЕСПЛАТНЫ → списки грузятся БЕЗ
/// лимитов/пагинации, всё в реальном времени, ручные кнопки «обновить» не нужны.
/// См. memory togetherly_pb_realtime_no_limits.
///
/// Дженерики:
///  • [watchList]   — начальная полная загрузка (`getFullList`) + SSE-дельты
///    (create/update/delete мёржатся в локальный список → `Stream<List>`).
///  • [watchRecord] — один документ по id (напр. группа) → `Stream<RecordModel?>`.
class PbRealtimeService {
  PbRealtimeService._();
  static final PbRealtimeService instance = PbRealtimeService._();
  factory PbRealtimeService() => instance;

  PocketBase get _pb => PocketBaseService().pb;

  // ── сравнители для сортировки ───────────────────────────────────────────
  /// ISO-строки сравниваются лексикографически = хронологически.
  static int _strAsc(dynamic a, dynamic b) =>
      (a ?? '').toString().compareTo((b ?? '').toString());
  static int _strDesc(dynamic a, dynamic b) => _strAsc(b, a);
  static int _numAsc(dynamic a, dynamic b) =>
      ((a as num?) ?? 0).compareTo((b as num?) ?? 0);

  /// Живой список записей коллекции по [filter]: полная загрузка + SSE-дельты.
  /// [compare] — сортировка снапшота (по умолчанию без сортировки).
  Stream<List<RecordModel>> watchList(
    String collection, {
    String? filter,
    int Function(RecordModel, RecordModel)? compare,
  }) {
    final byId = <String, RecordModel>{};
    UnsubscribeFunc? unsub;
    // Гонка: слушатель может отписаться (onCancel), пока ещё идёт начальная
    // загрузка/подписка в start(). Тогда unsub ещё null → onCancel ничего не
    // отменяет, а subscribe() резолвится позже и оставляет живую SSE-подписку
    // навсегда (утечка). Флаг закрывает гонку: если отменили во время старта,
    // только что созданную подписку рвём и не сохраняем.
    var cancelled = false;
    late StreamController<List<RecordModel>> ctrl;

    List<RecordModel> snapshot() {
      final list = byId.values.toList();
      if (compare != null) list.sort(compare);
      return list;
    }

    Future<void> start() async {
      try {
        final initial =
            await _pb.collection(collection).getFullList(filter: filter);
        if (cancelled) return;
        byId
          ..clear()
          ..addEntries(initial.map((r) => MapEntry(r.id, r)));
        if (!ctrl.isClosed) ctrl.add(snapshot());
        final u = await _pb.collection(collection).subscribe(
          '*',
          (e) {
            final rec = e.record;
            if (rec == null) return;
            if (e.action == 'delete') {
              byId.remove(rec.id);
            } else {
              byId[rec.id] = rec;
            }
            if (!ctrl.isClosed) ctrl.add(snapshot());
          },
          filter: filter,
        );
        if (cancelled) {
          await u(); // отменили, пока подписывались — рвём и не сохраняем
          return;
        }
        unsub = u;
      } catch (err) {
        debugPrint('PbRealtime.watchList($collection) failed: $err');
        if (!ctrl.isClosed) ctrl.addError(err);
      }
    }

    ctrl = StreamController<List<RecordModel>>.broadcast(
      onListen: start,
      onCancel: () async {
        cancelled = true;
        await unsub?.call();
        unsub = null;
      },
    );
    return ctrl.stream;
  }

  /// Живой одиночный документ по id (напр. group-doc). delete → null.
  Stream<RecordModel?> watchRecord(String collection, String id) {
    UnsubscribeFunc? unsub;
    var cancelled = false; // та же гонка отписки-во-время-старта, что в watchList
    late StreamController<RecordModel?> ctrl;

    Future<void> start() async {
      try {
        try {
          final rec = await _pb.collection(collection).getOne(id);
          if (cancelled) return;
          if (!ctrl.isClosed) ctrl.add(rec);
        } on ClientException catch (e) {
          if (e.statusCode == 404) {
            if (!ctrl.isClosed) ctrl.add(null);
          } else {
            rethrow;
          }
        }
        if (cancelled) return;
        final u = await _pb.collection(collection).subscribe(id, (e) {
          if (e.action == 'delete') {
            if (!ctrl.isClosed) ctrl.add(null);
          } else if (!ctrl.isClosed) {
            ctrl.add(e.record);
          }
        });
        if (cancelled) {
          await u();
          return;
        }
        unsub = u;
      } catch (err) {
        debugPrint('PbRealtime.watchRecord($collection/$id) failed: $err');
        if (!ctrl.isClosed) ctrl.addError(err);
      }
    }

    ctrl = StreamController<RecordModel?>.broadcast(
      onListen: start,
      onCancel: () async {
        cancelled = true;
        await unsub?.call();
        unsub = null;
      },
    );
    return ctrl.stream;
  }

  // ── типизированные обёртки (фильтр+сортировка под каждую сущность) ───────
  /// Группа (метаданные пары) — live. Замена listenToPair.
  Stream<RecordModel?> watchGroup(String groupId) =>
      watchRecord('groups', groupId);

  /// Лента воспоминаний — БЕЗ лимита, новые сверху, soft-deleted скрыты.
  Stream<List<RecordModel>> watchMemories(String groupId) => watchList(
        'memories',
        filter:
            _pb.filter('group_id = {:g} && deleted = false', {'g': groupId}),
        compare: (a, b) =>
            _strDesc(a.data['created_at'], b.data['created_at']),
      );

  /// Комментарии воспоминания — старые сверху.
  Stream<List<RecordModel>> watchComments(String memoryId) => watchList(
        'memory_comments',
        filter: _pb.filter('memory_id = {:m} && deleted = false', {'m': memoryId}),
        compare: (a, b) => _strAsc(a.data['created_at'], b.data['created_at']),
      );

  /// Настроения пользователя в группе.
  Stream<List<RecordModel>> watchMoods(String groupId, String uid) => watchList(
        'mood_entries',
        filter: _pb.filter(
            'group_id = {:g} && user_uid = {:u}', {'g': groupId, 'u': uid}),
        compare: (a, b) => _strDesc(a.data['timestamp'], b.data['timestamp']),
      );

  /// Чат группы — старые сверху (по ts).
  Stream<List<RecordModel>> watchMessages(String groupId) => watchList(
        'chat_messages',
        filter: _pb.filter('group_id = {:g}', {'g': groupId}),
        compare: (a, b) => _numAsc(a.data['ts'], b.data['ts']),
      );

  /// Маскоты группы — дефолтные первыми, затем по дате.
  Stream<List<RecordModel>> watchMascots(String groupId) => watchList(
        'mascots',
        filter: _pb.filter('group_id = {:g}', {'g': groupId}),
        compare: (a, b) {
          final ad = a.data['is_default'] == true;
          final bd = b.data['is_default'] == true;
          if (ad != bd) return ad ? -1 : 1;
          return _strAsc(a.data['created_at'], b.data['created_at']);
        },
      );

  /// Штрихи холста — по order_index.
  Stream<List<RecordModel>> watchCanvasStrokes(String groupId, String canvasId) =>
      watchList(
        'canvas_strokes',
        filter: _pb.filter('group_id = {:g} && canvas_id = {:c}',
            {'g': groupId, 'c': canvasId}),
        compare: (a, b) => _numAsc(a.data['order_index'], b.data['order_index']),
      );

  /// Виджет-данные группы (оба слота: свой + партнёрский).
  Stream<List<RecordModel>> watchWidgetData(String groupId) => watchList(
        'widget_data',
        filter: _pb.filter('group_id = {:g}', {'g': groupId}),
      );

  /// Каталог холстов группы.
  Stream<List<RecordModel>> watchCanvasCatalogue(String groupId) => watchList(
        'canvas_catalogue',
        filter: _pb.filter('group_id = {:g}', {'g': groupId}),
      );

  /// Статусы прочтения чата {uid: lastReadTs} — live.
  Stream<Map<String, int>> watchChatReads(String groupId) => watchList(
        'chat_reads',
        filter: _pb.filter('group_id = {:g}', {'g': groupId}),
      ).map((rows) => {
            for (final r in rows)
              (r.data['user_uid'] ?? '').toString():
                  (r.data['last_read_ts'] as num?)?.toInt() ?? 0,
          });

  /// Счётчики «Я скучаю» {uid: count} — live.
  Stream<Map<String, int>> watchMissYou(String groupId) => watchList(
        'miss_you',
        filter: _pb.filter('group_id = {:g}', {'g': groupId}),
      ).map((rows) => {
            for (final r in rows)
              (r.data['user_uid'] ?? '').toString():
                  (r.data['count'] as num?)?.toInt() ?? 0,
          });
}
