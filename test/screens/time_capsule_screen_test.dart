// Экран «Капсула времени», вариант А «Письмо на листе» из макета
// https://claude.ai/artifact/P1TYH5PFd6RLu7R3UJi3yz (14.10.2026).
//
// Прежний экран: градиентный круг с конвертом, эмодзи в подсказке, рамки у
// кнопки фото и у карточки даты, чипы срока в две строки и «Запечатать»,
// которая на пустой капсуле отвечала всплывающей ошибкой.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/time_capsule_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// 14 октября 2026, полдень: «через полгода» — 14 апреля 2027, 182 дня.
DateTime _now() => DateTime(2026, 10, 14, 12);

Future<AppTheme> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double width = 360,
  double scale = 1.0,
  AppLanguage language = AppLanguage.ru,
}) async {
  LocaleService.instance.setLanguage(language);
  final theme = buildAppTheme(kPalettes[21], brightness); // «Кофе», как на снимках
  tester.view.physicalSize = Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 780), textScaler: TextScaler.linear(scale)),
      child: TimeCapsuleScreen(
        theme: theme,
        pairId: 'g',
        authorName: 'Аня',
        authorAvatar: '',
        now: _now,
      ),
    ),
  ));
  await tester.pump();
  return theme;
}

FilledButton _seal(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('capsule-seal')));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  testWidgets('«Запечатать» молчит, пока нет ни письма, ни фото', (tester) async {
    await _pump(tester);
    expect(_seal(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('capsule-letter')), 'Привет из октября');
    await tester.pump();
    expect(_seal(tester).onPressed, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('capsule-letter')), '   ');
    await tester.pump();
    expect(_seal(tester).onPressed, isNull, reason: 'одни пробелы — не письмо');
  });

  testWidgets('срок: полгода по умолчанию, кнопки меняют число дней', (tester) async {
    await _pump(tester);
    expect(find.text('182'), findsOneWidget);
    expect(find.textContaining('14 апреля 2027'), findsOneWidget);
    await tester.tap(find.text('Месяц'));
    await tester.pump();
    expect(find.text('31'), findsOneWidget);
    expect(find.textContaining('14 ноября 2026'), findsOneWidget);
    await tester.tap(find.text('Год'));
    await tester.pump();
    expect(find.text('365'), findsOneWidget);
  });

  testWidgets('письмо на листе заметки: лист secondaryContainer, кавычка цвета темы, без рамок и теней',
      (tester) async {
    final theme = await _pump(tester);
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    final screen = find.byType(TimeCapsuleScreen);
    final fills = <Color>[];
    for (final w in tester.widgetList<Container>(find.descendant(of: screen, matching: find.byType(Container)))) {
      final d = w.decoration;
      if (d is BoxDecoration) {
        expect(d.border, isNull, reason: 'рамок на экране нет');
        expect(d.boxShadow, isNull, reason: 'теней на экране нет');
        expect(d.gradient, isNull, reason: 'градиентов на экране нет');
        if (d.color != null) fills.add(d.color!);
      }
    }
    expect(fills, contains(cs.secondaryContainer), reason: 'письмо пишется на листе пина-заметки');
    expect(tester.widget<Text>(find.text('“')).style?.color, theme.fillColor);
    expect(find.textContaining('💌'), findsNothing, reason: 'эмодзи в подсказке больше нет');
  });

  testWidgets('немецкий на 320 dp при шрифте 1.3: подпись под числом, подписи сроков одного размера',
      (tester) async {
    await _pump(tester, width: 320, scale: 1.3, language: AppLanguage.de);
    final number = tester.getRect(find.text('182'));
    final until = tester.getRect(find.text('bis zur Öffnung'));
    expect(until.top, greaterThanOrEqualTo(number.bottom - 1),
        reason: 'не влезла рядом — уходит под число, а не рвётся посреди слова');
    // Высота на экране, с учётом сжатия: размер шрифта в стиле у всех один,
    // а мелкой подпись делало сжатие под ширину кнопки.
    final heights = [
      for (final l in ['Monat', '6 Monate', 'Jahr'])
        tester.getRect(find.text(l)).height,
    ];
    for (final h in heights) {
      expect(h, closeTo(heights.first, 0.5), reason: 'подписи сроков уменьшаются вместе');
    }
  });

  for (final language in [AppLanguage.ru, AppLanguage.de]) {
    for (final b in Brightness.values) {
      for (final w in [320.0, 360.0]) {
        testWidgets('без переполнений: ${language.code}, ${b.name}, $w dp, шрифт 1.3', (tester) async {
          await _pump(tester, brightness: b, width: w, scale: 1.3, language: language);
          expect(tester.takeException(), isNull);
          await tester.enterText(
            find.byKey(const ValueKey('capsule-title')),
            'Очень длинный заголовок капсулы, который в строку не помещается',
          );
          await tester.enterText(
            find.byKey(const ValueKey('capsule-letter')),
            List.filled(30, 'строка письма в будущее').join('\n'),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
