import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Сторож заголовков секций.
///
/// До 11 августа 2026 их было шесть штук на приложение: Unbounded 16 в профиле,
/// Unbounded 18 в настройках, капс Onest 12 в достижениях, Onest 13 в заданиях
/// уровня и в ленте воспоминаний, Unbounded 14 на экране «Скучаю». Соседние
/// экраны выглядели собранными из разных приложений — с этого и начали жалобу.
///
/// Проверяем не картинку, а источник: любой файл, где заводится заголовок
/// секции, обязан брать стиль из `ProfileTheme.sectionLabel`. Свой `fontSize`
/// рядом с таким билдером — это как раз начало нового разнобоя.
void main() {
  test('заголовки секций берут общий стиль', () {
    final offenders = <String>[];
    final builder = RegExp(
      // Тип возврата бывает разный: `Widget`, `SliverToBoxAdapter`, `Padding`.
      r'[\w<>?]+\s+_section(Title|Header|Label)\w*\([\s\S]{0,900}?\n  \}',
      multiLine: true,
    );

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in builder.allMatches(source)) {
        final body = match.group(0)!;
        if (body.contains('ProfileTheme.sectionLabel')) continue;
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'свой стиль заголовка секции вместо общего: '
            '${offenders.toSet().join(', ')}');
  });

  test('стиль читается на всех палитрах', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final palette in kPalettes) {
        final scheme = buildAppTheme(palette, brightness).scheme!;
        final style = ProfileTheme.sectionLabel(scheme);
        expect(style.fontSize, 12);
        expect(style.letterSpacing, greaterThan(0.5),
            reason: 'капсу нужна разрядка, иначе буквы слипаются');
        expect(style.color, scheme.primary);
      }
    }
  });
}
