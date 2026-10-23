import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/miss_you_event.dart';
import 'package:love_app/screens/mini_mood_calendar.dart';
import 'package:love_app/utils/calendar_day.dart';

/// Шаг по дням календаря через перевод часов (обращение 433, 22.10.2026).
///
/// 25.10.2026 в Украине, Молдове, Европе и Израиле сутки длятся 25 часов, и
/// 24-часовой шаг от полуночи 22-го на четвёртой клетке попадал в 23:00 25-го:
/// полоса дней на главной показала воскресенье дважды. Проверки по датам
/// краснеют только в поясе с переводом часов, поэтому прогонять так:
///
///     TZ=Europe/Kyiv flutter test test/utils/calendar_day_test.dart
///
/// В поясе без перевода (CI в UTC) ловят сторожа по исходникам ниже.
void main() {
  group('calendarDay', () {
    test('через конец летнего времени — каждый день по разу и в полночь', () {
      final start = DateTime(2026, 10, 22);
      final days = [for (var i = 0; i < 7; i++) calendarDay(start, i)];
      expect(days.map((d) => d.day), [22, 23, 24, 25, 26, 27, 28]);
      expect(days.every((d) => d.hour == 0 && d.minute == 0), isTrue);
    });

    test('через начало летнего времени и назад — ни один день не пропадает', () {
      final start = DateTime(2026, 3, 31);
      final days = [for (var i = 0; i < 5; i++) calendarDay(start, -i)];
      expect(days.map((d) => d.day), [31, 30, 29, 28, 27]);
      expect(days.every((d) => d.hour == 0), isTrue);
    });

    test('через границу месяца и года', () {
      expect(calendarDay(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(calendarDay(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });
  });

  test('полоса дней на главной не повторяет воскресенье перевода часов', () {
    final today = DateTime(2026, 10, 22);
    expect(miniCalendarDate(today, 3), DateTime(2026, 10, 25));
    expect(miniCalendarDate(today, 4), DateTime(2026, 10, 26));
    expect(miniCalendarDate(DateTime(2026, 3, 31), -2), DateTime(2026, 3, 29));
  });

  test('«вчера» у импульсов «Скучаю» — с полуночи вчерашнего дня', () {
    // Утро после перевода часов: вчерашние сутки длились 25 часов.
    final since = missYouHistorySince(DateTime(2026, 10, 26, 9));
    expect(DateTime.fromMillisecondsSinceEpoch(since), DateTime(2026, 10, 25));
  });

  test('сторож: дни в этих местах не двигают 24-часовым шагом', () {
    // В поясе без перевода часов проверки выше проходят и со старым кодом,
    // поэтому старый приём ловится прямо в исходниках.
    final step = RegExp(r'(add|subtract)\((const )?Duration\(days');
    for (final path in [
      'lib/screens/mini_mood_calendar.dart',
      'lib/models/miss_you_event.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(step.hasMatch(source), isFalse, reason: path);
    }
  });
}
