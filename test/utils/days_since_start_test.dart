import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/couple_days.dart';

/// Обращение 418, 22.10.2026: «Сегодня день годовщины, попыталась сделать
/// открытку, но на ней ещё не засчитывает 365 день, показывает 364». Открытка и
/// виджет «Статистика отношений» считали полные сутки от часа начала, а главный
/// экран с праздничной плашкой считает клетки календаря. Отсчёт с вечера давал в
/// день годовщины до этого часа на день меньше.
void main() {
  test('в день годовщины 365, а не 364', () {
    final start = DateTime(2025, 10, 22, 18, 30);
    expect(daysSinceStart(start, DateTime(2026, 10, 22, 5, 6)), 365);
  });

  test('в день начала 0, назавтра с утра 1', () {
    final start = DateTime(2026, 10, 20, 23, 50);
    expect(daysSinceStart(start, DateTime(2026, 10, 20, 23, 59)), 0);
    expect(daysSinceStart(start, DateTime(2026, 10, 21, 0, 5)), 1);
  });

  test('перевод часов не съедает день', () {
    // Ночь на 29.03.2026 в Европе короче на час
    final start = DateTime(2026, 3, 28, 23, 0);
    expect(daysSinceStart(start, DateTime(2026, 3, 30, 1, 0)), 2);
  });

  test('дата в будущем и пустая дата дают 0', () {
    final now = DateTime(2026, 10, 22, 5, 6);
    expect(daysSinceStart(DateTime(2026, 11, 1), now), 0);
    expect(daysSinceStart(null, now), 0);
  });

  // Сторож: счётчики, на которых нашлась ошибка, считают общим правилом.
  test('открытка и виджет статистики считают через daysSinceStart', () {
    final postcard =
        File('lib/screens/postcard/postcard_editor_screen.dart').readAsStringSync();
    expect(postcard, contains('daysSinceStart('));
    expect(postcard, isNot(contains('.inDays')));

    final widgets = File('lib/services/home_widget_service.dart').readAsStringSync();
    expect(widgets, contains('final days = daysSinceStart(startDate'));
  });
}
