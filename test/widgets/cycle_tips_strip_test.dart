import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cycle_tip.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/cycle/cycle_tips_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «В разделе „цикл“ „как себе помочь“ совет не до конца видно, обрывается»
/// (запись экрана 14.09.2026). Карточка стояла в ленте высотой 132 точки: под
/// текст совета оставалось сорок, то есть две с половиной строки, и третья
/// резалась посередине даже при обычном шрифте.
///
/// Проверка меряет каждый текст карточки: высота, которую ему дали, обязана
/// вмещать весь текст, а не его начало.
void main() {
  for (final lang in [AppLanguage.ru, AppLanguage.de]) {
    group(lang.name, () {
      // Язык ставится вне testWidgets: запись в prefs внутри поддельного
      // времени теста не завершается никогда.
      setUpAll(() async {
        SharedPreferences.setMockInitialValues({});
        await LocaleService.instance.setLanguage(lang);
      });
      for (final scale in [1.0, 1.3]) {
        testWidgets('совет виден целиком, шрифт $scale', (tester) async {
          tester.view.physicalSize = const Size(360 * 3, 800 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const Scaffold(
                  body: Padding(
                    padding: EdgeInsets.all(16),
                    child: CycleTipsStrip(
                      scheme: ColorScheme.light(),
                      accent: Color(0xFFD32F2F),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          final list = find.byType(Scrollable);
          for (final tip in CycleTip.all(LocaleService.current)) {
            for (final text in [tip.title, tip.body]) {
              await tester.scrollUntilVisible(
                find.text(text),
                120,
                scrollable: list.first,
                maxScrolls: 40,
              );
              final rp = tester.renderObject<RenderParagraph>(find.text(text));
              final full = TextPainter(
                text: rp.text,
                textDirection: TextDirection.ltr,
                textScaler: rp.textScaler,
              )..layout(maxWidth: rp.size.width);
              expect(
                rp.didExceedMaxLines,
                isFalse,
                reason: 'обрезано многоточием: $text',
              );
              expect(
                rp.size.height,
                greaterThanOrEqualTo(full.height - 0.5),
                reason: 'нижние строки срезаны: $text',
              );
            }
          }
        });
      }
    });
  }
}
