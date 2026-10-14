// Пин запечатанной капсулы, вариант 2 «Лист с печатью» из макета
// https://claude.ai/artifact/P1TYH5PFd6RLu7R3UJi3yz (14.10.2026).
//
// Прежний пин: прыгающий подарок в градиентном круге, рамка, эмодзи песочных
// часов и строка «от Ани» под карточкой. Теперь — общая шапка пина, лист
// заметки с печатью-«печеньем» над краем, отсчёт дней, полоса срока и
// пилюля с датой открытия.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/sealed_capsule_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Future<AppTheme> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double width = 360,
  double scale = 1.0,
  AppLanguage language = AppLanguage.ru,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) async {
  LocaleService.instance.setLanguage(language);
  final theme = buildAppTheme(kPalettes[21], brightness);
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SealedCapsuleCard(
              theme: theme,
              header: const Text('Аня · 12 июля', key: ValueKey('pin-header')),
              sealedAt: DateTime(2026, 7, 12, 20),
              openAt: DateTime(2027, 2, 14, 9),
              onTapTooEarly: onTap ?? () {},
              onLongPress: onLongPress,
              now: () => DateTime(2026, 10, 14, 12),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
  return theme;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  testWidgets('шапка пина, отсчёт по календарю и дата открытия словами', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('pin-header')), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('дня до открытия'), findsOneWidget);
    expect(find.text('Откроется 14 февраля 2027'), findsOneWidget);
    expect(find.textContaining('от '), findsNothing, reason: 'автора называет шапка');
  });

  testWidgets('полоса срока: прошло 43% от запечатывания до открытия', (tester) async {
    await _pump(tester);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.43, 0.01));
  });

  testWidgets('лист заметки с печатью: secondaryContainer, без рамок, теней, градиентов и эмодзи',
      (tester) async {
    final theme = await _pump(tester);
    final cs = ProfileTheme.schemeFor(theme);
    final card = find.byType(SealedCapsuleCard);
    final fills = <Color>[];
    for (final w in tester.widgetList<Container>(find.descendant(of: card, matching: find.byType(Container)))) {
      final d = w.decoration;
      if (d is BoxDecoration) {
        expect(d.border, isNull, reason: 'рамок нет');
        expect(d.boxShadow, isNull, reason: 'теней нет');
        expect(d.gradient, isNull, reason: 'градиентов нет');
        if (d.color != null) fills.add(d.color!);
      }
    }
    expect(fills, contains(cs.secondaryContainer));
    expect(fills, contains(theme.cardSurface), reason: 'карточка как у всех пинов');
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget, reason: 'печать с замком');
    expect(find.textContaining('⏳'), findsNothing);
  });

  testWidgets('касание — «ещё рано», удержание — у того, кому его дали', (tester) async {
    var taps = 0, holds = 0;
    await _pump(tester, onTap: () => taps++, onLongPress: () => holds++);
    await tester.tap(find.byType(SealedCapsuleCard));
    await tester.pump(const Duration(milliseconds: 600));
    expect(taps, 1);
    await tester.longPress(find.byType(SealedCapsuleCard));
    await tester.pump(const Duration(milliseconds: 600));
    expect(holds, 1);
  });

  for (final language in [AppLanguage.ru, AppLanguage.de]) {
    for (final b in Brightness.values) {
      for (final w in [320.0, 360.0]) {
        testWidgets('без переполнений: ${language.code}, ${b.name}, $w dp, шрифт 1.3', (tester) async {
          await _pump(tester, brightness: b, width: w, scale: 1.3, language: language);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
