import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/daily_task.dart';
import '../models/memory.dart';
import 'pb_coins_service.dart';
import 'pb_data_service.dart';

/// Задания дня для пары.
///
/// Каталог из двухсот заданий лежал с июля без механики — здесь она. Набор на
/// день считается из даты и id пары ([dailyTasksFor]), поэтому у обоих
/// партнёров он совпадает без единого запроса к серверу и меняется сам в
/// полночь.
///
/// Прогресс общий: закрыл задание один — засчитано обоим, потому что пин
/// появляется в общей ленте. Хранится в `groups.daily_tasks`, монету за
/// закрытие выдаёт сервер (`/api/coins/task-reward`, не больше трёх в сутки):
/// клиент своим начислением распоряжаться не должен.
class DailyTaskService extends ChangeNotifier {
  DailyTaskService._();
  static final DailyTaskService instance = DailyTaskService._();
  factory DailyTaskService() => instance;

  final PbDataService _data = PbDataService();

  String _groupId = '';
  DailyTaskProgress _progress = const DailyTaskProgress.empty();

  /// Задания на сегодня. Пустой список — пары ещё нет.
  List<DailyTask> get today => _groupId.isEmpty
      ? const []
      : dailyTasksFor(day: DateTime.now(), pairId: _groupId);

  Set<String> get doneToday => _progress.doneOn(DateTime.now());

  bool isDone(DailyTask task) => doneToday.contains(task.id);

  /// Сколько закрыто из набора — для подписи на карточке.
  int get doneCount => today.where(isDone).length;

  bool get allDone => today.isNotEmpty && doneCount == today.length;

  /// Привязка к паре: зовётся там же, где остальные сервисы получают группу.
  void bind({required String groupId}) {
    if (_groupId == groupId) return;
    _groupId = groupId;
    _progress = const DailyTaskProgress.empty();
    notifyListeners();
  }

  /// Подтягивает прогресс из записи группы. Отдельный поток заводить не за чем:
  /// набор меняется раз в сутки, а галочка партнёра приезжает со следующим
  /// открытием главной.
  Future<void> refresh() async {
    if (_groupId.isEmpty) return;
    try {
      final rec = await _data.loadGroupById(_groupId);
      if (rec != null) applyGroupRaw(Map<String, dynamic>.from(rec.data));
    } catch (e) {
      debugPrint('DailyTaskService.refresh failed: $e');
    }
  }

  /// Прогресс приезжает вместе с записью группы — отдельного запроса не нужно.
  void applyGroupRaw(Map<String, dynamic> raw) {
    final value = raw['daily_tasks'];
    if (value is Map) {
      _progress = DailyTaskProgress.fromMap(Map<String, dynamic>.from(value));
      notifyListeners();
    }
  }

  /// Пин создан: закрываем подходящее задание и просим монету.
  ///
  /// Пин чужого типа и повторный пин уже закрытого задания не делают ничего —
  /// решает это [closeByMemory], а сервер сторожит суточный предел.
  Future<DailyTask?> onMemoryCreated(MemoryType type) async {
    if (_groupId.isEmpty) return null;
    final now = DateTime.now();
    final tasks = today;
    final closedId = closeByMemory(
      tasks: tasks,
      alreadyDone: _progress.doneOn(now),
      type: type,
    );
    if (closedId == null) return null;

    _progress = _progress.withDone(closedId, now);
    notifyListeners();

    unawaited(_data.updateGroupFields(_groupId, {
      'daily_tasks': _progress.toMap(),
    }));
    unawaited(PbCoinsService().taskReward(closedId));
    return DailyTask.byId(closedId);
  }
}
