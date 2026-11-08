import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/canvas/canvas_free_ratio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отзыв в Google Play на 1.37: «когда на виджете рисунок, то он какой-то
/// перекошенный». У холста, созданного до листа (на 08.11.2026 таких 108
/// тысяч из 171), пропорции нет: экран рисует его во всю свободную область
/// (около 0,6 на телефоне), а виджет — в рамку 0,8, и круг становится овалом.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('у холста с листом виджет берёт лист', () {
    expect(widgetSheetRatio(sheet: 1.0, free: 0.6), 1.0);
  });

  test('у холста без листа — форма, в которой его рисует этот телефон', () {
    expect(widgetSheetRatio(sheet: null, free: 0.58), 0.58);
  });

  test('холст ещё не открывали на этом телефоне — прежние 0,8', () {
    expect(widgetSheetRatio(sheet: null, free: null), 0.8);
  });

  test('форма запоминается своя у каждой пары и холста', () async {
    await rememberFreeRatio('g1', 'main', 0.58);
    await rememberFreeRatio('g2', 'main', 0.62);

    expect(await freeRatioOf('g1', 'main'), 0.58);
    expect(await freeRatioOf('g2', 'main'), 0.62);
    expect(await freeRatioOf('g1', 'other'), isNull);
  });
}
