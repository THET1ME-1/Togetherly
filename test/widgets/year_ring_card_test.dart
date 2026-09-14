import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/year_ring_spec.dart';
import 'package:love_app/widgets/year_ring_card.dart';

/// «Кольцо года» не имеет права выпускать текст за свои границы.
///
/// Снимки 14.09.2026: на iPhone «1288» вылезало за кольцо, на Android
/// «ВОСПОМИНАН» резалось, в превью каталога плитки выходили за низ карточки.
/// Проверка рисует карточку настоящим шрифтом Onest (тестовый шрифт шире
/// вдвое и соврал бы) на худших числах и длинных немецких словах.
void main() {
  setUpAll(() async {
    final loader = FontLoader('Onest')
      ..addFont(File('assets/fonts/Onest.ttf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await loader.load();
  });

  const colors = YearRingColors(
    primary: Color(0xFFFF7E8B),
    onPrimary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFDDB4),
  );

  const ru = YearRingTexts(
    daysCaption: 'Дней вместе',
    untilAnniversary: 'До годовщины',
    daysLeftUnit: 'дней',
    anniversaryLine: 'Годовщина 29 сентября',
    monthsShort: 'мес.',
    memoriesUnit: 'воспоминаний',
    smallLine: 'Ещё 364 дня',
  );
  const de = YearRingTexts(
    daysCaption: 'Tage zusammen',
    untilAnniversary: 'Bis zum Jahrestag',
    daysLeftUnit: 'Tage',
    anniversaryLine: 'Jahrestag am 29. September',
    monthsShort: 'Mon.',
    memoriesUnit: 'Erinnerungen',
    smallLine: '364 Tage übrig',
  );

  final cases = [
    (ru, 125, 240, 4, 10),
    (ru, 1288, 173, 42, 10),
    (ru, 12345, 364, 405, 12345),
    (de, 12345, 364, 405, 12345),
  ];

  for (final small in [false, true]) {
    for (final (texts, days, left, months, memories) in cases) {
      testWidgets(
          '${small ? '2×2' : '4×2'}: $days дней, $memories воспоминаний, '
          '«${texts.untilAnniversary}»', (tester) async {
        tester.view.physicalSize = const Size(400 * 3, 300 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: small ? 158 : 338,
                child: YearRingCard(
                  small: small,
                  colors: colors,
                  texts: texts,
                  daysTotal: days,
                  daysLeft: left,
                  months: months,
                  memories: memories,
                  progress: 0.53,
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);

        final card = tester.getRect(find.byType(YearRingCard));
        final paragraphs = tester
            .renderObjectList<RenderParagraph>(find.descendant(
              of: find.byType(YearRingCard),
              matching: find.byType(RichText),
            ))
            .toList();
        expect(paragraphs, isNotEmpty);

        for (final rp in paragraphs) {
          final text = rp.text.toPlainText();
          final left = rp.localToGlobal(Offset.zero).dx;
          final width = rp.getMaxIntrinsicWidth(double.infinity);
          expect(left + width, lessThanOrEqualTo(card.right - 8 + 0.5),
              reason: '«$text» вылезает за правый край карточки');
          expect(left, greaterThanOrEqualTo(card.left + 8),
              reason: '«$text» вылезает за левый край');
        }

        // Число дней в кольце: целиком во внутреннем диаметре.
        final ringSide = small ? YearRingSpec.smallRing : YearRingSpec.ring;
        final stroke = small ? YearRingSpec.smallStroke : YearRingSpec.stroke;
        final number = tester.renderObject<RenderParagraph>(find.text('$days'));
        expect(number.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(ringSide - 2 * stroke - 8),
            reason: 'число $days шире кольца');
      });
    }
  }
}
