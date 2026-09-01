// Кнопки листа «Редактировать таймер» при крупном системном шрифте.
//
// Жалоба со скриншота: «Отмена» ломалась на три строки — «От/мен/а». Кнопке
// доставалась четверть ширины листа, а внутри стандартный отступ кнопки
// съедал по 24 dp с каждой стороны, и на само слово оставалось около 30 dp.
//
// Считать символы тут бесполезно, нужен рендер настоящими шрифтами: тест
// открывает лист на узком экране при масштабе текста 1.3 и 1.5 и требует,
// чтобы обе надписи легли в одну строку.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/screens/expandable_timer_card.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/timer_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Число строк, на которое реально разложился текст виджета.
int _linesOf(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(text).first,
  );
  return paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      )
      .map((b) => b.top.round())
      .toSet()
      .length;
}

void main() {
  final theme = buildAppTheme(kPalettes[0], Brightness.dark);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  for (final scale in [1.0, 1.3, 1.5]) {
    testWidgets('«Отмена» и «Сохранить» держат одну строку при шрифте $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: ExpandableTimerCard(
                theme: theme,
                timerService: TimerService(),
                myAvatarUrl: '',
                partnerAvatarUrl: '',
                isPaired: true,
              ),
            ),
          ),
        ),
      );

      // Пустой список показывает кнопку «плюс» — она открывает тот же лист,
      // что и правка существующего таймера.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      final s = LocaleService.current;
      expect(find.text(s.cancel), findsOneWidget);
      expect(_linesOf(tester, s.cancel), 1,
          reason: '«${s.cancel}» снова переносится внутри кнопки');
      expect(_linesOf(tester, s.saveSettings), 1,
          reason: '«${s.saveSettings}» снова переносится внутри кнопки');
    });
  }
}
