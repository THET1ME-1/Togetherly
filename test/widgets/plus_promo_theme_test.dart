import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/plus/plus_promo_sheet.dart';

/// Плашка Togetherly+ обязана рисоваться темой пары.
///
/// Нижний лист живёт в дереве навигатора, ВЫШЕ экрана, поэтому цвета ему
/// достаются от `MaterialApp`, а не от того, кто его открыл. Пока схема там
/// собиралась заново (`ColorScheme.fromSeed` от `AppTheme.primary`), лист
/// выходил цветом чужой темы: серый заголовок, кнопка не в тон, текст едва
/// читался на фоне. Жалоба 15 августа 2026 — «попап фиговый, тему не берёт».
///
/// Расхождение было у ВСЕХ 25 палитр в обеих яркостях: у закатной
/// `primaryContainer` #FFEBE2 против #FFDAD2, у монохрома схема уезжала из
/// серого в бирюзу.
void main() {
  testWidgets('лист берёт схему темы пары, а не глобальную', (tester) async {
    // В MaterialApp намеренно стоит ЧУЖАЯ тема: так выглядит любой лист,
    // открытый поверх экрана с собственной темой.
    final mine = buildAppTheme(kPalettes[9], Brightness.dark); // Закатная
    final alien = ProfileTheme.themeFor(
        buildAppTheme(kPalettes[11], Brightness.light)); // Лесная
    final cs = ProfileTheme.schemeFor(mine);

    await tester.pumpWidget(
      MaterialApp(
        theme: alien,
        home: ThemeScope(
          theme: mine,
          child: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showPlusPromoSheet(ctx),
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    final inSheet = tester.element(find.byType(FilledButton));
    expect(Theme.of(inSheet).colorScheme, cs,
        reason: 'содержимое листа рисуется схемой темы пары');

    final sheetMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          )
          .last,
    );
    expect(sheetMaterial.color, cs.surfaceContainerHigh,
        reason: 'фон листа — поверхность той же схемы');
  });

  test('глобальная тема не собирает схему заново', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source.contains('ColorScheme.fromSeed'), isFalse,
        reason: 'схему меню берём у самой темы (ProfileTheme.schemeFor), '
            'иначе листы и диалоги уходят цветом от экранов');
  });
}
