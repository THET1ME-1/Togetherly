import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/widgets/chest/chest_prize_image.dart';

// Жалоба 28.09.2026: приз, вылетающий из сундука, мигает «есть — нет».
// Размер картинки менялся каждый кадр подъёма, и вместе с ним размер
// декодирования: картинка перезагружалась на каждом кадре. Сторож: сторона,
// с которой рисуется картинка, одна на все кадры, а на экране приз растёт.
void main() {
  testWidgets('картинка приза одного размера во всех кадрах подъёма', (t) async {
    final prize = fallbackChestOdds(withPlus: false).firstWhere((p) => p.kind == ChestPrizeKind.coins);
    final sides = <double>{};
    final shown = <double>[];
    for (final spot in kChestPrizeTrack.whereType<List<double>>().take(14)) {
      await t.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 300,
            child: Stack(children: [ChestPrizeFlight(prize: prize, spot: spot, stage: 300)]),
          ),
        ),
      ));
      sides.add(t.widget<ChestPrizeImage>(find.byType(ChestPrizeImage)).side);
      shown.add(t.getSize(find.byType(FittedBox)).width);
    }
    expect(sides.length, 1, reason: 'сторона картинки меняется — картинка перезагружается и мигает');
    expect(shown.first, lessThan(shown.last), reason: 'приз на экране по-прежнему растёт');
  });

  test('экран сундука рисует приз через ChestPrizeFlight', () {
    final src = File('lib/screens/chest_screen.dart').readAsStringSync();
    expect(src.contains('ChestPrizeFlight('), isTrue);
    expect(src.contains('ChestPrizeImage(opening, side: spot'), isFalse);
  });
}
