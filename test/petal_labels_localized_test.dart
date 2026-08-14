// Подписи лепесткового таймера приходят из приложения, а не зашиты в натив.
//
// Жалоба 14.08.2026: «некоторые слова + "ч", "мин" на виджете с лепестком
// таймером на русском, когда само приложение на англ». Расширения виджетов
// живут без Flutter и до `locale_service` не дотягиваются, поэтому единицы
// времени были прописаны прямо в Kotlin и Swift. Теперь приложение отдаёт их
// строкой `timer_<группа>_petal_labels`, а натив только рисует.
//
// Тест читает исходники: подключить сюда сам виджет нельзя, а проверить, что
// связка не разъехалась, нужно.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dart = File('lib/services/home_widget_service.dart').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/togetherly/love/PetalTimerWidgetProvider.kt',
  ).readAsStringSync();
  final swiftGraphics =
      File('ios/TogetherlyWidget/WidgetGraphics.swift').readAsStringSync();
  final swiftTimer =
      File('ios/TogetherlyWidget/TimerWidgets.swift').readAsStringSync();

  test('приложение отдаёт подписи лепестков', () {
    expect(dart, contains("timer_\${g}_petal_labels"));
    for (final label in [
      'yearsLabel',
      'monthsShortLabel',
      'daysShortLabel',
      'hoursLabel',
      'minLabel',
      'secLabel',
    ]) {
      expect(
        dart,
        contains('LocaleService.current.$label'),
        reason: 'подпись $label должна уезжать в виджет из локализации',
      );
    }
  });

  test('Android читает подписи и не рисует своими', () {
    expect(kotlin, contains('timer_\${g}_petal_labels'));
    final hardcoded = RegExp(r'Petal\("(лет|мес|дн|ч|мин|сек)"');
    expect(
      hardcoded.hasMatch(kotlin),
      isFalse,
      reason: 'подписи лепестков не должны быть зашиты в провайдере',
    );
  });

  test('iOS читает подписи и не рисует своими', () {
    expect(swiftTimer, contains('timer_\\(g)_petal_labels'));
    final hardcoded = RegExp(r'label: "(лет|мес|дн|ч|мин|сек)"');
    expect(
      hardcoded.hasMatch(swiftGraphics),
      isFalse,
      reason: 'подписи лепестков не должны быть зашиты в отрисовке',
    );
  });

  test('запасные подписи остаются для старых данных', () {
    // Виджет, добавленный до обновления, ещё не получил строку с подписями —
    // он обязан рисовать прежние слова, а не пустоту.
    expect(kotlin, contains('RU_LABELS'));
    expect(swiftGraphics, contains('petalFallbackLabels'));
  });
}
