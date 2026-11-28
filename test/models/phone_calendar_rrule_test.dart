import 'dart:convert';
import 'dart:io';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/date_recurrence.dart';

/// Календарь телефона получает наш повтор строкой RRULE: пакет обязан его
/// понять, иначе событие в Google Календаре молча станет одноразовым.
void main() {
  test('пакет календаря понимает каждое правило из примеров и пресетов', () {
    final cases = jsonDecode(File('test/fixtures/date_recurrence_cases.json').readAsStringSync()) as List;
    final rules = <String>{
      for (final c in cases) (c as Map)['rrule'] as String,
      for (final day in [DateTime(2026, 11, 8), DateTime(2026, 11, 26), DateTime(2026, 11, 29)])
        for (final p in repeatPresets(day)) p.rrule,
    }..remove('');
    final failed = <String>[];
    for (final r in rules) {
      try {
        if (RecurrenceRule.fromRruleString(r) == null) failed.add(r);
      } catch (e) {
        failed.add('$r — $e');
      }
    }
    expect(failed, isEmpty);
  });
}
