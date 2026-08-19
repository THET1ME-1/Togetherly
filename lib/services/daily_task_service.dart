import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const String _prefsKey = 'daily_tasks_progress';

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
    unawaited(_loadLocal());
  }

  /// Прогресс на устройстве. Без сети запись в группу не уходит, и до этой
  /// копии галочки пропадали при первом же перезапуске: монета выдана, а
  /// задание снова выглядит несделанным.
  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsKey:$_groupId');
      if (raw == null || raw.isEmpty) return;
      final local = DailyTaskProgress.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      // Серверный прогресс главнее: у партнёра могли закрыться другие задания.
      if (_progress.doneOn(DateTime.now()).isEmpty) {
        _progress = local;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('DailyTaskService._loadLocal failed: $e');
    }
  }

  Future<void> _saveLocal() async {
    if (_groupId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_prefsKey:$_groupId', jsonEncode(_progress.toMap()));
    } catch (e) {
      debugPrint('DailyTaskService._saveLocal failed: $e');
    }
  }

  /// Подтягивает прогресс из записи группы. Отдельный поток заводить не за чем:
  /// набор меняется раз в сутки, а галочка партнёра приезжает со следующим
  /// открытием главной.
  Future<void> refresh() async {
    if (_groupId.isEmpty) return;
    try {
      final rec = await _data.loadGroupById(_groupId);
      if (rec != null) {
        applyGroupRaw(Map<String, dynamic>.from(rec.data));
        unawaited(_saveLocal());
      }
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
  ///
  /// [fromTaskId] — задание, из которого открыли форму. Оно главнее типа: к
  /// ответу на «Чем ты восхищаешься в {p}?» человек прикладывает снимок, и пин
  /// становится `photo`, а текстовое задание оставалось незакрытым.
  Future<DailyTask?> onMemoryCreated(MemoryType type,
      {String? fromTaskId}) async {
    if (_groupId.isEmpty) return null;
    final now = DateTime.now();
    final tasks = today;
    final closedId = closeByMemory(
      tasks: tasks,
      alreadyDone: _progress.doneOn(now),
      type: type,
      fromTaskId: fromTaskId,
    );
    if (closedId == null) return null;

    _progress = _progress.withDone(closedId, now);
    notifyListeners();

    unawaited(_saveLocal());
    unawaited(_data.updateGroupFields(_groupId, {
      'daily_tasks': _progress.toMap(),
    }));
    unawaited(PbCoinsService().taskReward(closedId));
    return DailyTask.byId(closedId);
  }
}
