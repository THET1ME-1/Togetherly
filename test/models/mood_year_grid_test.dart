import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_year_grid.dart';

/// Год настроений клетками: колонка — неделя, клетка — день, тон — оценка.
///
/// Прежний режим «год» показывал двенадцать плиток с числом отметок за месяц:
/// по нему видно, много ли отмечались, и совсем не видно, какими были дни.
/// Сетка отвечает на второй вопрос — и на неё же ложится виджет 4×2, где
/// вместо года месяц.
///
/// Дни подряд с одинаковой оценкой рисуются одним скруглённым пятном: хорошая
/// неделя тогда читается сплошной полосой, а провал — прорехой в столбце.
void main() {
  DateTime d(int m, int day) => DateTime(2026, m, day);

  group('moodYearCells', () {
    test('год раскладывается по неделям, понедельник сверху', () {
      final cells = moodYearCells(year: 2026, scores: {d(1, 1): 4});
      // 1 января 2026 — четверг, то есть четвёртая строка первой колонки.
      final jan1 = cells.firstWhere((c) => c.date == d(1, 1));
      expect(jan1.weekday, 4);
      expect(jan1.column, 0);
      expect(jan1.score, 4);
    });

    test('в году 365 клеток, и все дни на месте', () {
      final cells = moodYearCells(year: 2026, scores: const {});
      expect(cells.length, 365);
      expect(cells.first.date, DateTime(2026, 1, 1));
      expect(cells.last.date, DateTime(2026, 12, 31));
    });

    test('високосный год длиннее на день', () {
      expect(moodYearCells(year: 2028, scores: const {}).length, 366);
    });

    test('день без отметки остаётся пустым, а не нулём', () {
      final cells = moodYearCells(year: 2026, scores: {d(3, 5): 2});
      expect(cells.firstWhere((c) => c.date == d(3, 5)).score, 2);
      expect(cells.firstWhere((c) => c.date == d(3, 6)).score, isNull);
    });
  });

  group('серии', () {
    test('соседние дни с одной оценкой сливаются в пятно', () {
      final cells = moodYearCells(year: 2026, scores: {
        d(1, 5): 5, // понедельник
        d(1, 6): 5,
        d(1, 7): 5,
      });
      final run = cells.firstWhere((c) => c.date == d(1, 5));
      expect(run.startsRun, isTrue, reason: 'первый день серии скруглён сверху');
      expect(run.endsRun, isFalse);

      final tail = cells.firstWhere((c) => c.date == d(1, 7));
      expect(tail.startsRun, isFalse);
      expect(tail.endsRun, isTrue, reason: 'последний скруглён снизу');
    });

    test('разные оценки подряд серией не считаются', () {
      final cells = moodYearCells(year: 2026, scores: {
        d(1, 5): 5,
        d(1, 6): 3,
      });
      for (final day in [d(1, 5), d(1, 6)]) {
        final c = cells.firstWhere((x) => x.date == day);
        expect(c.startsRun, isTrue);
        expect(c.endsRun, isTrue, reason: 'одиночная клетка скруглена со всех сторон');
      }
    });

    test('серия не переходит из колонки в колонку', () {
      // Воскресенье и следующий понедельник стоят в разных столбцах, и
      // склеивать их нельзя: пятно уехало бы поперёк сетки.
      final cells = moodYearCells(year: 2026, scores: {
        d(1, 11): 4, // воскресенье
        d(1, 12): 4, // понедельник следующей недели
      });
      expect(cells.firstWhere((c) => c.date == d(1, 11)).endsRun, isTrue);
      expect(cells.firstWhere((c) => c.date == d(1, 12)).startsRun, isTrue);
    });

    test('пропуск разрывает серию', () {
      final cells = moodYearCells(year: 2026, scores: {
        d(1, 5): 5,
        // 6 января без отметки
        d(1, 7): 5,
      });
      expect(cells.firstWhere((c) => c.date == d(1, 5)).endsRun, isTrue);
      expect(cells.firstWhere((c) => c.date == d(1, 7)).startsRun, isTrue);
    });
  });

  group('итог года', () {
    test('среднее считается по отмеченным дням, а не по всем', () {
      final s = moodYearSummary(
        year: 2026,
        scores: {d(2, 1): 5, d(2, 2): 3},
        today: DateTime(2026, 12, 31),
      );
      expect(s.marked, 2);
      expect(s.average, closeTo(4.0, 0.001));
      expect(s.missing, 363);
    });

    test('пустой год не делит на ноль', () {
      final s = moodYearSummary(
        year: 2026,
        scores: const {},
        today: DateTime(2026, 12, 31),
      );
      expect(s.marked, 0);
      expect(s.average, isNull);
      expect(s.missing, 365);
    });

    test('будущие дни года в пропуски не идут', () {
      // Год ещё не кончился: считать декабрь «днём без отметки» нечестно.
      final s = moodYearSummary(
        year: 2026,
        scores: {d(1, 1): 4},
        today: DateTime(2026, 1, 10),
      );
      expect(s.missing, 9);
    });
  });
}
