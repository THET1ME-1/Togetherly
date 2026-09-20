// Виджет «Где мы» рисуется картинкой под пропорции ячейки, а лончер показывает
// её с centerCrop. Ячейку лончер сообщает двумя парами чисел: MIN_WIDTH ×
// MAX_HEIGHT — это портрет, MAX_WIDTH × MIN_HEIGHT — альбом. Пока провайдер
// брал MIN_WIDTH × MIN_HEIGHT, на эмуляторе (Pixel Launcher, 19.09.2026)
// картинку рисовали под 360×135 при настоящих 360×224, и лончер срезал верх и
// низ: пилюлю, шарик и подпись о партнёре.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final provider = File(
    'android/app/src/main/kotlin/com/togetherly/love/PairMapWidgetProvider.kt',
  ).readAsStringSync();
  final sizing = File(
    'android/app/src/main/kotlin/com/togetherly/love/WidgetSizing.kt',
  ).readAsStringSync();

  test('размер ячейки берётся по ориентации экрана', () {
    expect(sizing, contains('OPTION_APPWIDGET_MAX_HEIGHT'));
    expect(sizing, contains('OPTION_APPWIDGET_MAX_WIDTH'));
    expect(sizing, contains('ORIENTATION_LANDSCAPE'));
  });

  test('провайдер «Где мы» записывает ячейку по ориентации, а не минимумы', () {
    expect(provider, contains('WidgetSizing.cellDp('));
    expect(provider, isNot(contains('WidgetSizing.heightDp(')));
    expect(provider, isNot(contains('WidgetSizing.widthDp(')));
  });

  // «144p» на телефоне 19.09.2026: картинка шла впритык к бюджету 950 КБ,
  // провайдер читал её в RGB_565 и при малейшем превышении — вдвое меньше.
  test('провайдер сообщает плотность экрана для рисовки в фоне', () {
    expect(provider, contains('mapw_density'));
    expect(provider, contains('displayMetrics.density'));
  });

  test('картинка читается целиком, в ARGB, а отказ лончера — повтор вдвое меньше', () {
    expect(provider, isNot(contains('RGB_565')));
    expect(provider, isNot(contains('950_000')));
    expect(provider, contains('ARGB_8888'));
    expect(RegExp(r'try \{[^}]*updateAppWidget', dotAll: true).hasMatch(provider), isTrue,
        reason: 'updateAppWidget с картинкой должен быть в try');
    expect(provider, contains('sample = 2'));
  });
}
