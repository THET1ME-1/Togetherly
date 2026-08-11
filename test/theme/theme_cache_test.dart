import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Схема и `ThemeData` собираются дорого: `ColorScheme.fromSeed` считает
/// тональные палитры в HCT, а `ThemeData` тянет за собой десяток подтем. Звали
/// их прямо из `build` — в чате восемь раз за кадр, на главной пять, — поэтому
/// цена платилась заново на каждое сообщение и каждое движение пальца.
///
/// Тесты держат ровно одно обещание: за одинаковыми входами стоит один и тот
/// же объект. Вид от этого не меняется — объекты неизменяемые.
void main() {
  test('схема по одному акценту не пересчитывается', () {
    final first = ProfileTheme.schemeOf(
      const Color(0xFFBB005B),
      Brightness.light,
    );
    final second = ProfileTheme.schemeOf(
      const Color(0xFFBB005B),
      Brightness.light,
    );

    expect(identical(first, second), isTrue);
  });

  test('яркость разводит схемы', () {
    final light = ProfileTheme.schemeOf(
      const Color(0xFF7C4DFF),
      Brightness.light,
    );
    final dark = ProfileTheme.schemeOf(
      const Color(0xFF7C4DFF),
      Brightness.dark,
    );

    expect(identical(light, dark), isFalse);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
  });

  test('тема по одной схеме собирается один раз', () {
    final scheme = ProfileTheme.schemeOf(
      const Color(0xFF00897B),
      Brightness.dark,
    );

    expect(
      identical(ProfileTheme.data(scheme), ProfileTheme.data(scheme)),
      isTrue,
    );
  });

  test('равные схемы из разных вызовов дают ту же тему', () {
    final a = ColorScheme.fromSeed(seedColor: const Color(0xFFEF6C00));
    final b = ColorScheme.fromSeed(seedColor: const Color(0xFFEF6C00));

    expect(identical(a, b), isFalse, reason: 'схемы собраны порознь');
    expect(identical(ProfileTheme.data(a), ProfileTheme.data(b)), isTrue);
  });

  test('кэш не растёт без предела', () {
    for (var i = 0; i < 200; i++) {
      final accent = Color(0xFF000000 | (i * 7919) % 0xFFFFFF);
      ProfileTheme.data(ProfileTheme.schemeOf(accent, Brightness.light));
    }

    expect(ProfileTheme.debugCachedSchemes, lessThanOrEqualTo(64));
    expect(ProfileTheme.debugCachedThemes, lessThanOrEqualTo(64));
  });
}
