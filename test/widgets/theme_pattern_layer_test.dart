import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/seed_swatch.dart';
import 'package:love_app/widgets/theme/theme_pattern_layer.dart';

/// Узор темы лежит на фоне главной под всеми вкладками, как обои в чате:
/// плитка повторяется, контуры красятся одним цветом из темы.
void main() {
  final hw = kPalettes.firstWhere((p) => p.name == 'Хэллоуин');

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, height: 780, child: child)),
      );

  testWidgets('у «Хэллоуина» фон в узоре: плитка повторяется одним цветом',
      (tester) async {
    final t = buildAppTheme(hw, Brightness.dark);
    await tester.pumpWidget(host(ThemePatternLayer(theme: t)));

    final img = tester.widget<Image>(find.byType(Image));
    expect(img.repeat, ImageRepeat.repeat);
    expect(img.color, t.bgPattern!.tint);
    expect(img.colorBlendMode, BlendMode.srcIn);
    final provider = img.image as ExactAssetImage;
    expect(provider.assetName, t.bgPattern!.asset);
    // Плитка нарисована втрое крупнее точки экрана — так контуры не мылятся
    // на плотных экранах.
    expect(provider.scale, 3.0);
    // Узор — фон: касания идут сквозь него, а читалка экрана его не видит.
    expect(
      find.ancestor(of: find.byType(Image), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    expect(
      find.ancestor(
          of: find.byType(Image), matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
  });

  testWidgets('у обычной темы слой пустой', (tester) async {
    final t = buildAppTheme(kPalettes.first, Brightness.light);
    await tester.pumpWidget(host(ThemePatternLayer(theme: t)));
    expect(find.byType(Image), findsNothing);
  });

  test('главная кладёт узор между фоном и содержимым всех вкладок', () {
    final src = File('lib/screens/home_screen.dart').readAsStringSync();
    final background = src.indexOf('// -- Background --');
    final pattern = src.indexOf('ThemePatternLayer(');
    final content = src.indexOf('// -- Main content --');
    expect(background, greaterThan(0));
    expect(pattern, greaterThan(background));
    expect(pattern, lessThan(content));
  });

  testWidgets('в кружке ленты у «Хэллоуина» тыква на ночи, а не квадранты',
      (tester) async {
    await tester.pumpWidget(host(Center(child: SeedSwatch(palette: hw))));
    final img = tester.widget<Image>(find.byType(Image));
    expect((img.image as AssetImage).assetName, hw.badge!.asset);
    final circle = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle && d.color != null);
    expect(circle.map((d) => d.color), contains(hw.badge!.background));
  });

  testWidgets('у обычной палитры в кружке квадранты схемы', (tester) async {
    await tester
        .pumpWidget(host(Center(child: SeedSwatch(palette: kPalettes[3]))));
    expect(find.byType(Image), findsNothing);
  });
}
