import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cycle_entry.dart';
import 'offline/local_store.dart';
import 'offline/outbox_service.dart';
import 'offline/pb_id.dart';
import 'pb_data_service.dart';
import 'pocketbase_service.dart';

/// Отметки календаря цикла.
///
/// Пишет как остальные разделы: сначала в местное хранилище, потом заданием в
/// очередь отправки. Отметка появляется в календаре мгновенно и не теряется без
/// сети.
///
/// Видимость партнёру — поле каждой записи, а не флажок в профиле: правило
/// чтения коллекции смотрит именно на него, поэтому выключенный доступ
/// закрывает данные на сервере, а не только в интерфейсе. Из-за этого
/// переключение тумблера — операция над всеми записями сразу.
class CycleRepository {
  CycleRepository._();
  static final CycleRepository instance = CycleRepository._();
  factory CycleRepository() => instance;

  static const String _collection = 'cycle_entries';

  final PbDataService _data = PbDataService();

  String? get _uid => PocketBaseService().userId;

  /// Отметки [uid] в группе. Свои — все; партнёрские сервер отдаст только те,
  /// что разрешено показывать.
  Future<List<CycleEntry>> load(String groupId, String uid) async {
    if (groupId.isEmpty || uid.isEmpty) return const [];
    try {
      final cached = await LocalStore.instance.allRecords(_collection);
      final local = cached
          .map(CycleEntry.fromPb)
          .where((e) => e.userUid == uid)
          .toList();

      final recs = await _data.loadCycle(groupId, uid);
      if (recs.isEmpty) return local;

      final fresh = recs.map(CycleEntry.fromPb).toList();
      for (final e in fresh) {
        await LocalStore.instance
            .upsertRaw(_collection, e.id, e.toMap(groupId: groupId));
      }
      return fresh;
    } catch (e) {
      debugPrint('CycleRepository.load failed: $e');
      return const [];
    }
  }

  /// Ставит отметку на день. Возвращает созданную запись или null.
  Future<CycleEntry?> mark({
    required String groupId,
    required DateTime day,
    required CycleKind kind,
    CycleFlow? flow,
    required bool shared,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty || groupId.isEmpty) return null;

    final normalized = DateTime(day.year, day.month, day.day);
    final entry = CycleEntry(
      id: newPbId(),
      day: normalized,
      kind: kind,
      flow: flow,
      shared: shared,
      userUid: uid,
    );
    final map = entry.toMap(groupId: groupId);

    await LocalStore.instance.upsertRaw(_collection, entry.id, map);
    await OutboxService.instance.enqueue('cycleUpsert', {
      'groupId': groupId,
      'uid': uid,
      'entry': {
        'id': entry.id,
        'day': normalized.toIso8601String(),
        'kind': CycleEntry.kindToStorage(kind),
        'flow': CycleEntry.flowToStorage(flow),
        'shared': shared,
      },
    });
    return entry;
  }

  /// Снимает отметку.
  Future<void> unmark(String entryId) async {
    if (entryId.isEmpty) return;
    await LocalStore.instance.deleteRecord(_collection, entryId);
    await OutboxService.instance.enqueue('cycleDelete', {'id': entryId});
  }

  /// Переключает видимость всех своих отметок.
  Future<void> setShared({
    required String groupId,
    required bool shared,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty || groupId.isEmpty) return;

    // Местная копия обновляется сразу, чтобы интерфейс не ждал сервер.
    final cached = await LocalStore.instance.allRecords(_collection);
    for (final rec in cached) {
      final entry = CycleEntry.fromPb(rec);
      if (entry.userUid != uid || entry.shared == shared) continue;
      await LocalStore.instance.upsertRaw(
        _collection,
        entry.id,
        entry.copyWith(shared: shared).toMap(groupId: groupId),
      );
    }

    await OutboxService.instance.enqueue('cycleShareAll', {
      'groupId': groupId,
      'uid': uid,
      'shared': shared,
    });
  }

  /// Стирает все свои отметки — по кнопке «удалить данные цикла».
  Future<void> wipe(String groupId) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty || groupId.isEmpty) return;

    final cached = await LocalStore.instance.allRecords(_collection);
    for (final rec in cached) {
      final entry = CycleEntry.fromPb(rec);
      if (entry.userUid != uid) continue;
      await LocalStore.instance.deleteRecord(_collection, entry.id);
    }

    await OutboxService.instance.enqueue('cycleWipe', {
      'groupId': groupId,
      'uid': uid,
    });
  }
}
