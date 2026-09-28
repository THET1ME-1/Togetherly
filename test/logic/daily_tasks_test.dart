import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/memory.dart';

/// Задания дня: каталог из двухсот штук лежал с июля без механики. Здесь
/// проверяется выбор набора и его закрытие — то, чего не хватало.
void main() {
  final day = DateTime.utc(2026, 10, 2);

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
          day: DateTime.utc(2026, 10, 2, 7), pairId: 'g1');
      final evening = dailyTasksFor(
          day: DateTime.utc(2026, 10, 2, 23), pairId: 'g1');
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
          date: '2026-10-01', done: const {'photo_now'});
      expect(old.doneOn(day), isEmpty);
    });

    test('сегодняшний прогресс читается', () {
      final p = DailyTaskProgress(date: '2026-10-02', done: const {'photo_now'});
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
      final p = DailyTaskProgress(date: '2026-10-02', done: const {'a', 'b'});
      final back = DailyTaskProgress.fromMap(p.toMap());
      expect(back.date, '2026-10-02');
      expect(back.done, {'a', 'b'});
    });
  });

  group('пин из задания', () {
    // Живой разбор пары tepngitgvren2b9 (19.08.2026): человек открыл задание
    // «Чем ты восхищаешься в {p}?», написал текст И приложил фото. Тип пина
    // стал photo, фото-задания в наборе не было — не закрылось ничего, и
    // текстовое осталось с пустой галочкой. Жалоба звучала как «текстовые
    // задания не отмечаются».
    test('закрывает своё задание, даже если тип пина другой', () {
      final tasks = dailyTasksFor(day: day, pairId: 'g1');
      final target = tasks.firstWhere((t) => t.type == MemoryType.text,
          orElse: () => tasks.first);
      final other = MemoryType.values
          .firstWhere((t) => tasks.every((task) => task.type != t));
      final closed = closeByMemory(
        tasks: tasks,
        alreadyDone: const {},
        type: other,
        fromTaskId: target.id,
      );
      expect(closed, target.id);
    });

    test('уже закрытое задание уступает совпадению по типу', () {
      final tasks = dailyTasksFor(day: day, pairId: 'g1');
      final target = tasks.first;
      final another = tasks.last;
      final closed = closeByMemory(
        tasks: tasks,
        alreadyDone: {target.id},
        type: another.type,
        fromTaskId: target.id,
      );
      expect(closed, another.id);
    });

    test('чужой id задания не мешает старому правилу', () {
      final tasks = dailyTasksFor(day: day, pairId: 'g1');
      final target = tasks.first;
      final closed = closeByMemory(
        tasks: tasks,
        alreadyDone: const {},
        type: target.type,
        fromTaskId: 'task_from_yesterday',
      );
      expect(closed, target.id);
    });
  });

  group('каталог', () {
    test('заданий не меньше четырёхсот, id и тексты не повторяются', () {
      final all = DailyTask.all;
      expect(all.length, greaterThanOrEqualTo(400));
      expect(all.map((t) => t.id).toSet().length, all.length);
      expect(all.map((t) => t._ruForTest).toSet().length, all.length);
    });

    test('у каждого типа пина есть задания, включая своё видео', () {
      final types = DailyTask.all.map((t) => t.type).toSet();
      expect(types, containsAll(MemoryType.values));
    });
  });

  group('порядок по дням', () {
    final start = DateTime.utc(2026, 9, 28);
    DailyTaskDay dayAt(int i, [String pair = 'g1']) => dailyTaskDayFor(
        day: start.add(Duration(days: i)), pairId: pair);

    test('пока не пройден каталог, задание не повторяется', () {
      // Три основных плюс бонус в день: 400 заданий хватает на сто дней.
      final seen = <String>{};
      final days = DailyTask.all.length ~/ 4 - 5;
      for (var i = 0; i < days; i++) {
        final d = dayAt(i);
        for (final t in [...d.main, if (d.bonus != null) d.bonus!]) {
          expect(seen.add(t.id), isTrue, reason: 'повтор ${t.id} в день $i');
        }
      }
    });

    test('типы основных разные каждый день, бонус есть всегда', () {
      for (var i = 0; i < 400; i++) {
        final d = dayAt(i, 'g7');
        expect(d.main.length, 3);
        expect(d.main.map((t) => t.type).toSet().length, 3, reason: 'день $i');
        expect(d.bonus, isNotNull, reason: 'день $i');
        expect(d.main.map((t) => t.id), isNot(contains(d.bonus!.id)));
      }
    });

    test('два дня подряд без общих заданий', () {
      for (var i = 0; i < 300; i++) {
        final a = dayAt(i, 'g3').main.map((t) => t.id).toSet();
        final b = dayAt(i + 1, 'g3').main.map((t) => t.id).toSet();
        expect(a.intersection(b), isEmpty, reason: 'дни $i и ${i + 1}');
      }
    });

    test('бонус закрывается пином своего типа, когда передан в список', () {
      final d = dayAt(0);
      final closed = closeByMemory(
        tasks: [...d.main, d.bonus!],
        alreadyDone: d.main.map((t) => t.id).toSet(),
        type: d.bonus!.type,
      );
      expect(closed, d.bonus!.id);
    });
  });
}

extension on DailyTask {
  String get _ruForTest => title('П');
}
