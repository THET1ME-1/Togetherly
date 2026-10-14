// Лист «Наклейки»: ряд наборов как в выборе настроения и сетка картинок.
// Касание по картинке отдаёт наклейку, а набор запоминается на следующий раз.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/memory/sticker_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picked {
  StickerChoice? choice;
  bool done = false;
}

Future<_Picked> _open(
  WidgetTester tester, {
  Brightness b = Brightness.light,
  double width = 360,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final theme = buildAppTheme(kPalettes[21], b);
  final cs = ProfileTheme.schemeFor(theme);
  final picked = _Picked();
  await tester.pumpWidget(ThemeScope(
    theme: theme,
    child: MaterialApp(
      theme: ProfileTheme.data(cs),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () async {
                    picked.choice = await showStickerPicker(ctx);
                    picked.done = true;
                  },
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'app_language': 'ru'}));

  testWidgets('наборы рядом, касание по картинке отдаёт наклейку',
      (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    final picked = await _open(tester);
    expect(find.text('Наклейки'), findsOneWidget);
    expect(find.byKey(const Key('sticker-pack-classic')), findsOneWidget);
    // Ряд наборов прокручивается вбок: «Зайка» может стоять за краем.
    final bunny = find.byKey(const Key('sticker-pack-bunny'), skipOffstage: false);
    expect(bunny, findsOneWidget);
    await tester.ensureVisible(bunny);
    await tester.pumpAndSettle();

    await tester.tap(bunny);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sticker-bunny-love')));
    await tester.pumpAndSettle();

    expect(picked.done, isTrue);
    expect(picked.choice?.image, 'assets/images/mood_packs/bunny/love.webp');
    expect(picked.choice?.pack, 'bunny');
    expect(picked.choice?.mood, 'love');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kStickerLastPackKey), 'bunny');
  });

  testWidgets('прошлый набор открывается сам', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'app_language': 'ru', kStickerLastPackKey: 'pink'});
    await _open(tester);
    expect(find.byKey(const Key('sticker-pack-pink')), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('sticker-pink-')),
        findsWidgets);
  });

  for (final b in Brightness.values) {
    for (final lang in [AppLanguage.ru, AppLanguage.de]) {
      testWidgets('320 точек, шрифт 1.3, ${lang.name}, ${b.name}',
          (tester) async {
        await LocaleService.instance.setLanguage(lang);
        addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));
        await _open(tester, b: b, width: 320, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
