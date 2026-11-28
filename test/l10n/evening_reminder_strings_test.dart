import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dict/evening_reminder.dart';
import 'package:love_app/l10n/uk/evening_reminder.dart';
import 'package:love_app/l10n/zh/evening_reminder.dart';

/// Вечернее напоминание (TOG-113) говорит на всех девяти языках.
void main() {
  const langs = ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de'];

  test('каждая строка есть на семи языках словаря', () {
    final gaps = [
      for (final e in eveningReminderStrings.entries)
        for (final l in langs)
          if ((e.value[l] ?? '').trim().isEmpty) '${e.key}:$l',
    ];
    expect(gaps, isEmpty);
  });

  test('украинский и китайский покрывают все ключи и ничего лишнего', () {
    expect(eveningReminderUk.keys.toSet(), eveningReminderStrings.keys.toSet());
    expect(eveningReminderZh.keys.toSet(), eveningReminderStrings.keys.toSet());
  });

  test('подсказка — одно предложение', () {
    for (final l in langs) {
      final text = eveningReminderStrings['er.hint']![l]!;
      expect(RegExp(r'[.!?](\s|$)').allMatches(text).length, 1, reason: l);
    }
  });
}
