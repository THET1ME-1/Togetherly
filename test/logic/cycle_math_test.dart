// Арифметика цикла. Считается по собственным данным пользователя: средние
// 28 дней — плохой прогноз, если у человека цикл 33.
//
// Овуляция отсчитывается от КОНЦА цикла, а не от начала: лютеиновая фаза
// стабильнее фолликулярной (10–16 дней, обычно 14), поэтому «следующие
// месячные минус 14» точнее, чем «начало плюс половина цикла».

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/cycle_math.dart';

DateTime d(int year, int month, int day) => DateTime(year, month, day);

void main() {
  group('CycleMath.starts — первые дни циклов', () {
    test('подряд идущие дни считаются одним циклом', () {
      final marks = [
        d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 7),
        d(2026, 2, 2), d(2026, 2, 3),
      ];
      expect(CycleMath.starts(marks), [d(2026, 1, 5), d(2026, 2, 2)]);
    });

    test('разрыв в один день разрывает цикл', () {
      final marks = [d(2026, 1, 5), d(2026, 1, 7)];
      expect(CycleMath.starts(marks), [d(2026, 1, 5), d(2026, 1, 7)]);
    });

    test('порядок отметок не важен', () {
      final marks = [d(2026, 2, 3), d(2026, 1, 5), d(2026, 2, 2), d(2026, 1, 6)];
      expect(CycleMath.starts(marks), [d(2026, 1, 5), d(2026, 2, 2)]);
    });

    test('пустой список даёт пустой результат', () {
      expect(CycleMath.starts(const []), isEmpty);
    });
  });

  group('CycleMath.averageCycleLength', () {
    test('среднее по промежуткам между началами', () {
      // 5 янв → 2 фев = 28 дней, 2 фев → 4 мар = 30 дней. Среднее 29.
      final marks = [d(2026, 1, 5), d(2026, 2, 2), d(2026, 3, 4)];
      expect(CycleMath.averageCycleLength(marks), 29);
    });

    test('одного цикла мало — длины нет', () {
      expect(CycleMath.averageCycleLength([d(2026, 1, 5)]), isNull);
    });

    test('считает только по последним шести циклам', () {
      // Восемь начал: первые давние и длинные, последние короткие. Старые
      // в среднее попадать не должны — цикл меняется со временем.
      final marks = <DateTime>[];
      var day = d(2025, 1, 1);
      for (var i = 0; i < 3; i++) {
        marks.add(day);
        day = day.add(const Duration(days: 40));
      }
      // Семь начал подряд дают шесть промежутков по 28 — ровно окно усреднения,
      // старые сорокадневные в него уже не попадают.
      for (var i = 0; i < 7; i++) {
        marks.add(day);
        day = day.add(const Duration(days: 28));
      }
      expect(CycleMath.averageCycleLength(marks), 28);
    });

    test('неправдоподобные промежутки отбрасываются', () {
      // Пропущенный цикл даёт 56 дней — это не длина цикла, а дыра в данных.
      final marks = [d(2026, 1, 1), d(2026, 1, 29), d(2026, 3, 25)];
      expect(CycleMath.averageCycleLength(marks), 28);
    });
  });

  group('CycleMath.averagePeriodLength', () {
    test('среднее число подряд отмеченных дней', () {
      final marks = [
        d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 7), d(2026, 1, 8),
        d(2026, 2, 2), d(2026, 2, 3), d(2026, 2, 4), d(2026, 2, 5),
        d(2026, 2, 6), d(2026, 2, 7),
      ];
      expect(CycleMath.averagePeriodLength(marks), 5); // (4 + 6) / 2
    });

    test('без отметок длительности нет', () {
      expect(CycleMath.averagePeriodLength(const []), isNull);
    });
  });

  group('CycleMath.predict — прогноз', () {
    test('следующие месячные = последнее начало плюс средняя длина', () {
      final marks = [d(2026, 1, 5), d(2026, 2, 2)]; // 28 дней
      final p = CycleMath.predict(marks, today: d(2026, 2, 10));
      expect(p!.nextPeriod, d(2026, 3, 2));
    });

    test('овуляция за 14 дней до следующих месячных', () {
      final marks = [d(2026, 1, 5), d(2026, 2, 2)];
      final p = CycleMath.predict(marks, today: d(2026, 2, 10));
      expect(p!.ovulation, d(2026, 2, 16));
    });

    test('фертильное окно — пять дней до овуляции и день после', () {
      final marks = [d(2026, 1, 5), d(2026, 2, 2)];
      final p = CycleMath.predict(marks, today: d(2026, 2, 10));
      expect(p!.fertileFrom, d(2026, 2, 11));
      expect(p.fertileTo, d(2026, 2, 17));
    });

    test('без второго цикла прогноза нет', () {
      expect(CycleMath.predict([d(2026, 1, 5)], today: d(2026, 1, 20)), isNull);
    });

    test('просроченный прогноз сдвигается вперёд, а не остаётся в прошлом', () {
      // Месячные ждали 2 марта, сегодня 20 марта, новых отметок нет.
      final marks = [d(2026, 1, 5), d(2026, 2, 2)];
      final p = CycleMath.predict(marks, today: d(2026, 3, 20));
      expect(p!.nextPeriod.isAfter(d(2026, 3, 20)), isTrue);
      expect(p.overdueDays, 18);
    });

    test('нерегулярный цикл помечается как ненадёжный', () {
      // Разброс 24…35 дней — среднему верить нельзя.
      final marks = [
        d(2026, 1, 1), d(2026, 1, 25), d(2026, 3, 1), d(2026, 3, 25),
      ];
      final p = CycleMath.predict(marks, today: d(2026, 3, 26));
      expect(p!.irregular, isTrue);
    });

    test('ровный цикл ненадёжным не считается', () {
      final marks = [
        d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 26),
      ];
      final p = CycleMath.predict(marks, today: d(2026, 3, 27));
      expect(p!.irregular, isFalse);
    });
  });

  group('сверка с общепринятым расчётом', () {
    // Эталон из калькуляторов овуляции и рекомендаций ACOG:
    // последние месячные 1 января, цикл 28 дней →
    // овуляция = 1 янв + (28 − 14) = 15 января,
    // фертильное окно = овуляция − 5 … + 1 = 10…16 января.
    //
    // У нас овуляция считается от конца цикла (следующие месячные − 14), что
    // при цикле 28 даёт ту же дату, но не разъезжается на длинных циклах.
    // Последние месячные — 1 января; предыдущие 4 декабря дают длину 28.
    final marks = [d(2025, 12, 4), d(2026, 1, 1)];

    test('овуляция 15 января', () {
      final p = CycleMath.predict(marks, today: d(2026, 1, 5));
      expect(p!.ovulation, d(2026, 1, 15));
    });

    test('фертильное окно 10–16 января', () {
      final p = CycleMath.predict(marks, today: d(2026, 1, 5));
      expect(p!.fertileFrom, d(2026, 1, 10));
      expect(p.fertileTo, d(2026, 1, 16));
    });

    test('цикл считается от первого дня до первого дня следующих', () {
      // 1 янв → 29 янв это 28 дней, а не 27 и не 29.
      expect(CycleMath.averageCycleLength(marks), 28);
    });

    test('на длинном цикле овуляция сдвигается к его концу', () {
      // Цикл 35 дней: овуляция должна быть на 21-й день, а не на 14-й, —
      // именно из-за этого считаем от конца, а не от начала.
      final long = [d(2026, 1, 1), d(2026, 2, 5)];
      final p = CycleMath.predict(long, today: d(2026, 2, 6));
      expect(p!.cycleLength, 35);
      expect(p.ovulation, d(2026, 2, 26)); // 5 фев + 35 = 12 мар, минус 14
    });
  });

  group('CycleMath.dayOfCycle', () {
    test('первый день месячных — день 1', () {
      final marks = [d(2026, 1, 5), d(2026, 2, 2)];
      expect(CycleMath.dayOfCycle(marks, today: d(2026, 2, 2)), 1);
    });

    test('десятый день цикла', () {
      final marks = [d(2026, 1, 5), d(2026, 2, 2)];
      expect(CycleMath.dayOfCycle(marks, today: d(2026, 2, 11)), 10);
    });

    test('без отметок дня цикла нет', () {
      expect(CycleMath.dayOfCycle(const [], today: d(2026, 2, 11)), isNull);
    });
  });

  group('CycleMath.phaseOn — фаза дня', () {
    final marks = [d(2026, 1, 5), d(2026, 2, 2)];

    test('отмеченный день — месячные', () {
      expect(CycleMath.phaseOn(marks, d(2026, 2, 2), today: d(2026, 2, 10)),
          CyclePhase.period);
    });

    test('день овуляции', () {
      expect(CycleMath.phaseOn(marks, d(2026, 2, 16), today: d(2026, 2, 10)),
          CyclePhase.ovulation);
    });

    test('день фертильного окна', () {
      expect(CycleMath.phaseOn(marks, d(2026, 2, 13), today: d(2026, 2, 10)),
          CyclePhase.fertile);
    });

    test('ожидаемые месячные', () {
      expect(CycleMath.phaseOn(marks, d(2026, 3, 2), today: d(2026, 2, 10)),
          CyclePhase.predictedPeriod);
    });

    test('обычный день ничем не помечен', () {
      expect(CycleMath.phaseOn(marks, d(2026, 2, 22), today: d(2026, 2, 10)),
          CyclePhase.none);
    });
  });
}
