import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/miss_you/vibe_chip.dart';

/// TOG-40, обращение 377: плитки «Что ещё передать» уходили молча. Сердечки
/// взлетали у большой кнопки наверху экрана, а у пальца не было ничего, и
/// число стояло до выхода с экрана. Плитка отвечает на нажатие сама.
void main() {
  final cs = ProfileTheme.schemeFor(AppThemes.byIndex(7));

  Widget host(Widget chip, {double width = 360, double scale = 1, bool reduce = false}) => MediaQuery(
    data: MediaQueryData(size: Size(width, 780), textScaler: TextScaler.linear(scale), disableAnimations: reduce),
    child: MaterialApp(
      theme: ProfileTheme.data(cs),
      home: Scaffold(
        body: Center(child: SizedBox(width: width - 28, child: chip)),
      ),
    ),
  );

  testWidgets('нажатие отвечает у самой плитки: всплеск значков', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(VibeChip(
      scheme: cs,
      icon: Icons.cloud_rounded,
      label: 'Думаю о тебе',
      mine: 3,
      partner: 5,
      onTap: () => taps++,
    )));

    await tester.tap(find.text('Думаю о тебе'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(taps, 1);
    expect(find.byKey(const ValueKey('vibe-burst')), findsOneWidget, reason: 'нажатие ничем не отмечено');

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byKey(const ValueKey('vibe-burst')), findsNothing, reason: 'всплеск не уходит');
  });

  testWidgets('новое число на плитке сменяет прежнее', (tester) async {
    Widget chip(int mine) => VibeChip(
      scheme: cs,
      icon: Icons.volunteer_activism_rounded,
      label: 'Хочу обнять',
      mine: mine,
      partner: 7,
      onTap: () {},
    );
    await tester.pumpWidget(host(chip(3)));
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(host(chip(4)));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('«уменьшить движение» — без всплеска, но нажатие доходит', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(
      VibeChip(scheme: cs, icon: Icons.cloud_rounded, label: 'Думаю о тебе', onTap: () => taps++),
      reduce: true,
    ));
    await tester.tap(find.text('Думаю о тебе'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(taps, 1);
    expect(find.byKey(const ValueKey('vibe-burst')), findsNothing);
  });

  testWidgets('320 точек при шрифте 1,3: длинное пожелание со счётом и крестиком влезает', (tester) async {
    await tester.pumpWidget(host(
      VibeChip(
        scheme: cs,
        icon: Icons.edit_rounded,
        label: 'Люблю тебя очень сильно и скучаю каждый день',
        mine: 1045,
        partner: 1957,
        onTap: () {},
        onRemove: () {},
      ),
      width: 320,
      scale: 1.3,
    ));
    await tester.tap(find.byType(VibeChip));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });
}
