import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/memory/moment_parts.dart';

/// Детали обложки открытого воспоминания (вариант A, 07.10.2026): название,
/// факты пилюлями, оценка звёздами, связанная группа кнопок, рамка постера.
/// Всё в цветах темы и без рамок — прежние экраны красили рейтинг оранжевым
/// и обводили каждую карточку.

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Future<ColorScheme> _pump(WidgetTester tester, Widget Function(ColorScheme, Color) build,
    {Brightness b = Brightness.light, double width = 360, double scale = 1}) async {
  final theme = buildAppTheme(kPalettes[0], b);
  final cs = ProfileTheme.themeFor(theme).colorScheme;
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ProfileTheme.data(cs),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 1600), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [build(cs, theme.fillColor)],
        ),
      ),
    ),
  ));
  await tester.pump();
  return cs;
}

Widget _all(ColorScheme cs, Color fill) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MomentPosterFrame(scheme: cs, child: const ColoredBox(color: Colors.grey)),
        MomentHead(scheme: cs, title: 'Очень длинное название фильма, которое не влезает', sub: 'Interstellar'),
        MomentPills(children: [
          MomentPill(scheme: cs, fill: fill, label: 'КП 8,6', icon: Icons.star_rounded, strong: true),
          MomentPill(scheme: cs, fill: fill, label: '2014'),
          MomentPill(scheme: cs, fill: fill, label: 'научная фантастика'),
          MomentPill(scheme: cs, fill: fill, label: 'драма'),
        ]),
        MomentStars(scheme: cs, fill: fill, rating: 4, who: 'Аня'),
        MomentButtons(
          scheme: cs,
          fill: fill,
          primary: MomentAction(Icons.open_in_new_rounded, 'Открыть на Кинопоиске', () {}),
          secondary: MomentAction(Icons.map_rounded, 'Карта', () {}),
        ),
      ],
    );

void main() {
  setUpAll(() async {
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  testWidgets('нет ни одной рамки', (tester) async {
    await _pump(tester, _all);
    for (final w in tester.widgetList<Container>(find.byType(Container))) {
      final d = w.decoration;
      if (d is BoxDecoration) expect(d.border, isNull);
    }
  });

  testWidgets('рейтинг Кинопоиска — заливка темы, остальные факты — тональные', (tester) async {
    final cs = await _pump(tester, _all);
    final colors = tester
        .widgetList<Container>(find.descendant(of: find.byType(MomentPill), matching: find.byType(Container)))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .toSet();
    final fill = buildAppTheme(kPalettes[0], Brightness.light).fillColor;
    expect(colors, contains(fill));
    expect(colors, contains(cs.secondaryContainer));
    expect(colors.any((c) => c == Colors.amber || c == Colors.orange), isFalse);
  });

  testWidgets('звёзд пять, залито столько, какая оценка', (tester) async {
    await _pump(tester, _all);
    final fill = buildAppTheme(kPalettes[0], Brightness.light).fillColor;
    final stars = tester
        .widgetList<Icon>(find.descendant(
            of: find.byType(MomentStars), matching: find.byType(Icon)))
        .toList();
    expect(stars, hasLength(5));
    expect(stars.where((i) => i.color == fill), hasLength(4));
    expect(find.text('Аня'), findsOneWidget);
  });

  testWidgets('главная кнопка залита цветом темы, вторая — значок с подсказкой', (tester) async {
    await _pump(tester, _all);
    expect(find.text('Открыть на Кинопоиске'), findsOneWidget);
    expect(find.byTooltip('Карта'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    for (final w in [320.0, 360.0]) {
      testWidgets('без переполнений: ${b.name}, $w dp, шрифт 1.3', (tester) async {
        await _pump(tester, _all, b: b, width: w, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
