import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/date_recurrence.dart';

DateTime _d(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('совпадает с dateutil', () {
    // Тот же файл читает сервер (`pocketbase/hotpath/test_date_rules.py`):
    // приложение и напоминания не должны расходиться ни на день.
    final cases = jsonDecode(
            File('test/fixtures/date_recurrence_cases.json').readAsStringSync())
        as List<dynamic>;

    test('примеров не меньше сорока', () => expect(cases.length, greaterThanOrEqualTo(40)));

    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      test(c['name'], () {
        final start = _d(c['start'] as String);
        final days = occurrencesOf(
          start: start,
          rrule: c['rrule'] as String,
          exdates: {for (final e in c['exdates'] as List) e as String},
          from: _d(c['from'] as String),
          to: _d(c['to'] as String),
        );
        expect(days.map(_iso).toList(), c['dates']);
      });
    }
  });

  group('разбор и сборка правила', () {
    test('туда и обратно', () {
      final start = DateTime(2026, 11, 8);
      for (final rule in [
        'FREQ=DAILY',
        'FREQ=DAILY;INTERVAL=3',
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=WE,SU;UNTIL=20261215',
        'FREQ=WEEKLY;BYDAY=SU;COUNT=5',
        'FREQ=MONTHLY;BYMONTHDAY=8',
        'FREQ=MONTHLY;BYDAY=2SU',
        'FREQ=MONTHLY;INTERVAL=2;BYDAY=-1SU',
        'FREQ=YEARLY',
        'FREQ=YEARLY;INTERVAL=2;COUNT=3',
      ]) {
        expect(Recurrence.parse(rule, start)!.toRrule(), rule, reason: rule);
      }
    });

    test('недостающее берётся из дня начала', () {
      final start = DateTime(2026, 11, 8); // воскресенье
      expect(Recurrence.parse('FREQ=WEEKLY', start)!.toRrule(), 'FREQ=WEEKLY;BYDAY=SU');
      expect(Recurrence.parse('FREQ=MONTHLY', start)!.toRrule(), 'FREQ=MONTHLY;BYMONTHDAY=8');
      expect(Recurrence.parse('RRULE:FREQ=YEARLY', start)!.toRrule(), 'FREQ=YEARLY');
    });

    test('незнакомое и пустое — без повтора', () {
      final start = DateTime(2026, 11, 8);
      for (final rule in ['', 'мусор', 'FREQ=HOURLY', 'FREQ=YEARLY;BYMONTH=3', 'FREQ=DAILY;INTERVAL=0']) {
        expect(Recurrence.parse(rule, start), isNull, reason: rule);
      }
    });
  });

  group('пресеты как в Google Календаре', () {
    test('вс 8 ноября: второе воскресенье, не последнее', () {
      final kinds = repeatPresets(DateTime(2026, 11, 8)).map((p) => p.kind).toList();
      expect(kinds, [
        RepeatPresetKind.none,
        RepeatPresetKind.daily,
        RepeatPresetKind.weekdays,
        RepeatPresetKind.weekly,
        RepeatPresetKind.biweekly,
        RepeatPresetKind.monthlyDay,
        RepeatPresetKind.monthlyNth,
        RepeatPresetKind.yearly,
      ]);
      final nth = repeatPresets(DateTime(2026, 11, 8))
          .firstWhere((p) => p.kind == RepeatPresetKind.monthlyNth);
      expect(nth.rrule, 'FREQ=MONTHLY;BYDAY=2SU');
    });

    test('чт 26 ноября: и четвёртый, и последний четверг', () {
      final presets = repeatPresets(DateTime(2026, 11, 26));
      expect(presets.map((p) => p.rrule), containsAll(['FREQ=MONTHLY;BYDAY=4TH', 'FREQ=MONTHLY;BYDAY=-1TH']));
    });

    test('вс 29 ноября: пятого нет, последнее есть', () {
      final rules = repeatPresets(DateTime(2026, 11, 29)).map((p) => p.rrule).toList();
      expect(rules, contains('FREQ=MONTHLY;BYDAY=-1SU'));
      expect(rules.where((r) => r.contains('5SU')), isEmpty);
    });

    test('правило находит свой пресет', () {
      final start = DateTime(2026, 11, 8);
      expect(presetOf('FREQ=WEEKLY;BYDAY=SU', start), RepeatPresetKind.weekly);
      expect(presetOf('FREQ=WEEKLY', start), RepeatPresetKind.weekly);
      expect(presetOf('', start), RepeatPresetKind.none);
      expect(presetOf('FREQ=WEEKLY;BYDAY=WE,SU', start), RepeatPresetKind.custom);
    });
  });

  test('следующие повторы лениво и без конца', () {
    final next = occurrencesAfter(
      start: DateTime(2025, 11, 8),
      rrule: 'FREQ=YEARLY',
      exdates: const {},
      from: DateTime(2026, 11, 28),
    ).take(3).map(_iso).toList();
    expect(next, ['2027-11-08', '2028-11-08', '2029-11-08']);
  });
}
