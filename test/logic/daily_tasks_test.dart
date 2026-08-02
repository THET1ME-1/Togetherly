import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/memory.dart';

/// Задания дня: каталог из двухсот штук лежал с июля без механики. Здесь
/// проверяется выбор набора и его закрытие — то, чего не хватало.
void main() {
  final day = DateTime.utc(2026, 8, 2);

  group('dailyTasksFor', () {
    test('выдаёт ровно три задания', () {
      expect(dailyTasksFor(day: day, pairId: 'g1').length, 3);
    });

    test('у обоих партнёров набор одинаковый', () {
      // Сервер в выборе не участвует: набор считается из даты и пары, поэтому
      // на двух телефонах он обязан совпасть без обмена сообщениями.
      final a = dailyTasksFor(day: day, pairId: 'g1').map((t) => t.id).toList();
      final b = dailyTasksFor(day: day, pairId: 'g1').map((t) => t.id).toList();
      expect(a, b);
    });

    test('у разных пар наборы разные', () {
      final a = dailyTasksFor(day: day, pairId: 'g1').map((t) => t.id).toSet();
      final b = dailyTasksFor(day: day, pairId: 'g2').map((t) => t.id).toSet();
      expect(a, isNot(b));
    });

    test('назавтра набор меняется', () {
      final today = dailyTasksFor(day: day, pairId: 'g1').map((t) => t.id).toSet();
      final tomorrow = dailyTasksFor(
              day: day.add(const Duration(days: 1)), pairId: 'g1')
          .map((t) => t.id)
          .toSet();
      expect(today, isNot(tomorrow));
    });

    test('время суток на набор не влияет', () {
      final morning = dailyTasksFor(
          day: DateTime.utc(2026, 8, 2, 7), pairId: 'g1');
      final evening = dailyTasksFor(
          day: DateTime.utc(2026, 8, 2, 23), pairId: 'g1');
      expect(morning.map((t) => t.id), evening.map((t) => t.id));
    });

    test('в наборе нет повторов', () {
      final ids = dailyTasksFor(day: day, pairId: 'g1').map((t) => t.id);
      expect(ids.toSet().length, 3);
    });

    test('типы пинов в наборе не совпадают', () {
      // Три задания на фото подряд — это одно и то же задание трижды.
      final types = dailyTasksFor(day: day, pairId: 'g7').map((t) => t.type);
      expect(types.toSet().length, 3);
    });
  });

  group('DailyTaskProgress', () {
    test('вчерашний прогресс на сегодня не переносится', () {
      final old = DailyTaskProgress(
          date: '2026-08-01', done: const {'photo_now'});
      expect(old.doneOn(day), isEmpty);
    });

    test('сегодняшний прогресс читается', () {
      final p = DailyTaskProgress(date: '2026-08-02', done: const {'photo_now'});
      expect(p.doneOn(day), {'photo_now'});
    });

    test('закрытие пина закрывает задание своего типа', () {
      final tasks = dailyTasksFor(day: day, pairId: 'g1');
      final target = tasks.first;
      final closed = closeByMemory(
        tasks: tasks,
        alreadyDone: const {},
        type: target.type,
      );
      expect(closed, target.id);
    });

    test('пин чужого типа ничего не закрывает', () {
      final tasks = dailyTasksFor(day: day, pairId: 'g1');
      final missing = MemoryType.values
          .firstWhere((t) => tasks.every((task) => task.type != t));
      expect(
        closeByMemory(tasks: tasks, alreadyDone: const {}, type: missing),
        isNull,
      );
    });

    test('второй пин того же типа второй монеты не даёт', () {
      final tasks = dailyTasksFor(day: day, pairId: 'g1');
      final target = tasks.first;
      final closed = closeByMemory(
        tasks: tasks,
        alreadyDone: {target.id},
        type: target.type,
      );
      expect(closed, isNull);
    });

    test('прогресс переживает круг через хранилище', () {
      final p = DailyTaskProgress(date: '2026-08-02', done: const {'a', 'b'});
      final back = DailyTaskProgress.fromMap(p.toMap());
      expect(back.date, '2026-08-02');
      expect(back.done, {'a', 'b'});
    });
  });
}
