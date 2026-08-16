// Подпись «сколько уже вместе» приходит в виджет из приложения.
//
// Жалоба со снимком экрана 15.08.2026: у пары 348 дней, а виджет пишет «0 лет
// уже ❤️». Года считались делением `дни / 365` прямо в нативе — там же, где
// нет ни локализации, ни календарных границ. Теперь строку собирает Dart
// (`togetherAlreadyCaption`), а Kotlin со Swift только рисуют.
//
// Тест читает исходники: подключить сюда виджет-расширение нельзя, а проверить,
// что связка не разъехалась, нужно.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dart = File('lib/services/home_widget_service.dart').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/togetherly/love/DaysCounterWidgetProvider.kt',
  ).readAsStringSync();
  final swift =
      File('ios/TogetherlyWidget/DaysStreakStatsWidgets.swift').readAsStringSync();

  test('приложение отдаёт готовую подпись', () {
    expect(dart, contains("days_\${g}_caption"));
    expect(
      dart,
      contains('togetherAlreadyCaption'),
      reason: 'подпись обязана считаться общим правилом, а не на месте',
    );
  });

  test('Android читает подпись и не считает года сам', () {
    expect(kotlin, contains('days_\${g}_caption'));
    final ownMath = RegExp(r'val years = totalDays / 365');
    // Расчёт остался ровно один — в запасной ветке для старых виджетов.
    expect(
      ownMath.allMatches(kotlin).length,
      1,
      reason: 'года считает приложение; в нативе — только фолбэк',
    );
    expect(
      kotlin,
      contains('legacyYearsText'),
      reason: 'виджет со старой сборки обязан продолжать работать',
    );
  });

  test('iOS читает подпись и не считает года сам', () {
    expect(swift, contains('days_\\(g)_caption'));
    expect(
      RegExp(r'let years = totalDays / 365').allMatches(swift).length,
      1,
      reason: 'года считает приложение; в расширении — только фолбэк',
    );
    expect(swift, contains('legacyYearsText'));
  });

  test('запасная ветка молчит вместо «0 лет уже»', () {
    // Ровно то, на что жаловался человек: ноль лет вслух не произносится
    // даже у виджета, который ещё не получил строку от приложения.
    expect(kotlin, contains('if (years < 1) return ""'));
    expect(swift, contains('if years < 1 { return "" }'));
  });
}
