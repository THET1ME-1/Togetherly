// Лист «Кто на рисунке» (26.11.2026): девушка или парень на каждой половине
// раскраски. Владелец: «кастомизацию, кого выбирать для рисунка, парня или
// девушку, с каждой стороны по отдельности».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_figures.dart';
import 'package:love_app/models/coloring_picture.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/coloring/coloring_figures_sheet.dart';

void main() {
  late ColoringFigures? result;

  Future<void> open(
    WidgetTester tester, {
    double width = 320,
    double scale = 1.3,
    bool rightLocked = false,
    ColoringSide? mySide = ColoringSide.left,
  }) async {
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    tester.view.physicalSize = Size(width * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    result = null;
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(cs),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showColoringFiguresSheet(
                  context,
                  theme: theme,
                  picture: ColoringPicture.byId('snowman')!,
                  initial: ColoringFigures.drawn,
                  mySide: mySide,
                  rightLocked: rightLocked,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  testWidgets('каждая половина выбирается отдельно и уходит наружу по «Готово»', (tester) async {
    await open(tester);
    expect(find.text('Кто на рисунке'), findsOneWidget);
    expect(find.textContaining('Твоя половинка'), findsOneWidget);
    expect(find.textContaining('Половинка партнёра'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coloring-figure-right-girl')));
    await tester.pumpAndSettle();
    final preview = tester.widget<Image>(find.byKey(const ValueKey('coloring-figures-preview-right')));
    expect((preview.image as AssetImage).assetName, 'assets/coloring/snowman_right_girl.png');

    await tester.tap(find.byKey(const ValueKey('coloring-figures-done')));
    await tester.pumpAndSettle();
    expect(result, const ColoringFigures(left: ColoringFigure.girl, right: ColoringFigure.girl));
  });

  testWidgets('раскрашенную половину не поменять', (tester) async {
    await open(tester, rightLocked: true);
    expect(find.textContaining('Уже раскрашено'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coloring-figure-right-girl')), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coloring-figures-done')));
    await tester.pumpAndSettle();
    expect(result!.right, ColoringFigure.boy);
  });

  testWidgets('без партнёра половины без подписей «твоя / партнёра»', (tester) async {
    await open(tester, mySide: null);
    expect(find.textContaining('Половинка партнёра'), findsNothing);
    expect(find.text('Слева'), findsOneWidget);
  });

  for (final lang in [AppLanguage.ru, AppLanguage.de, AppLanguage.pt]) {
    testWidgets('320 точек, шрифт 1,3 — ничего не переполняется (${lang.code})', (tester) async {
      // Смена языка пишет настройки по-настоящему: ждём её вне поддельного
      // времени теста, иначе она не кончится никогда.
      await tester.runAsync(() => LocaleService.instance.setLanguage(lang));
      await open(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
