// Прогноз партнёрши. Раньше вся арифметика цикла считалась по своим отметкам:
// в сетке партнёра рисовались только проставленные вручную дни, без ожидаемых
// месячных, овуляции и задержки. Две девушки в паре из-за этого видели друг у
// друга голый календарь.
//
// Расчёт от источника не зависит — он принимает набор отметок и не спрашивает,
// чей он.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cycle_entry.dart';
import 'package:love_app/services/cycle_service.dart';
import 'package:love_app/utils/cycle_math.dart';

DateTime d(int year, int month, int day) => DateTime(year, month, day);

CycleEntry period(DateTime day, {String uid = 'partner'}) => CycleEntry(
      id: 'p-${day.month}-${day.day}',
      day: day,
      kind: CycleKind.period,
      shared: true,
      userUid: uid,
    );

/// Два цикла по 28 дней: 5 января и 2 февраля, по три дня каждый.
List<CycleEntry> get partnerMarks => [
      period(d(2026, 1, 5)),
      period(d(2026, 1, 6)),
      period(d(2026, 1, 7)),
      period(d(2026, 2, 2)),
      period(d(2026, 2, 3)),
      period(d(2026, 2, 4)),
    ];

void main() {
  group('CycleService.forecastOf — прогноз по чужим отметкам', () {
    test('следующие месячные считаются от последнего начала', () {
      final forecast =
          CycleService.forecastOf(partnerMarks, today: d(2026, 2, 20));

      expect(forecast, isNotNull);
      expect(forecast!.cycleLength, 28);
      expect(forecast.nextPeriod, d(2026, 3, 2));
    });

    test('овуляция отсчитывается от следующих месячных', () {
      final forecast =
          CycleService.forecastOf(partnerMarks, today: d(2026, 2, 20));

      expect(forecast!.ovulation, d(2026, 2, 16));
    });

    test('задержка видна и у партнёрши', () {
      // 2 марта прошло, новых отметок нет — пятый день задержки.
      final forecast =
          CycleService.forecastOf(partnerMarks, today: d(2026, 3, 7));

      expect(forecast!.overdueDays, 5);
    });

    test('близость в расчёт цикла не идёт', () {
      final withIntimacy = [
        ...partnerMarks,
        CycleEntry(
          id: 'i-1',
          day: d(2026, 2, 14),
          kind: CycleKind.intimacy,
          shared: true,
          userUid: 'partner',
        ),
      ];

      expect(
        CycleService.forecastOf(withIntimacy, today: d(2026, 2, 20))!.nextPeriod,
        d(2026, 3, 2),
      );
    });

    test('одного цикла для прогноза мало', () {
      final single = [period(d(2026, 1, 5)), period(d(2026, 1, 6))];

      expect(CycleService.forecastOf(single, today: d(2026, 1, 20)), isNull);
    });
  });

  group('CycleService.phaseOf — раскраска чужой сетки', () {
    test('день овуляции помечен', () {
      expect(
        CycleService.phaseOf(partnerMarks, d(2026, 2, 16), today: d(2026, 2, 20)),
        CyclePhase.ovulation,
      );
    });

    test('ожидаемые месячные помечены', () {
      expect(
        CycleService.phaseOf(partnerMarks, d(2026, 3, 2), today: d(2026, 2, 20)),
        CyclePhase.predictedPeriod,
      );
    });

    test('отмеченный вручную день остаётся месячными', () {
      expect(
        CycleService.phaseOf(partnerMarks, d(2026, 2, 3), today: d(2026, 2, 20)),
        CyclePhase.period,
      );
    });
  });
}
