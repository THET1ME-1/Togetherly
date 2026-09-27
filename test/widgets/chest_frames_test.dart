import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

/// Открытие сундука шагает только вместе с отрисовкой экрана.
///
/// Жалоба 27.09.2026: «анимация открытия идёт во время рекламы, после неё
/// сундук уже закрыт». Кадры двигал таймер, и открытие проходило, пока экран
/// был закрыт рекламой. Теперь кадры двигает тикер: нет отрисовки — нет шагов.
void main() {
  const url = 'test://chest_frames_3.webp';

  setUpAll(() {
    ChestFrames.debugPut(url, File('test/fixtures/chest_frames_3.webp').readAsBytesSync());
  });

  Future<void> settle(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 70));
    }
  }

  Widget player({required bool ticking, required List<int> frames, required List<int> done}) => MaterialApp(
    home: TickerMode(
      enabled: ticking,
      child: ChestFrames(
        key: const ValueKey('open'),
        url: url,
        still: 'assets/images/gifts/chest.webp',
        side: 100,
        loop: false,
        onFrame: frames.add,
        onDone: () => done.add(1),
      ),
    ),
  );

  testWidgets('пока экран не рисуется, открытие стоит, потом проходит целиком и замирает на последнем кадре', (
    tester,
  ) async {
    final frames = <int>[], done = <int>[];

    await tester.pumpWidget(player(ticking: false, frames: frames, done: done));
    await settle(tester, 10);
    expect(frames, isEmpty, reason: 'без отрисовки кадры не должны идти');
    expect(done, isEmpty);

    await tester.pumpWidget(player(ticking: true, frames: frames, done: done));
    await settle(tester, 12);
    expect(frames, [0, 1, 2]);
    expect(done, [1], reason: 'конец приходит ровно один раз');
    expect(find.byType(RawImage), findsOneWidget, reason: 'после конца стоит последний кадр, а не заглушка');

    await settle(tester, 5);
    expect(frames, [0, 1, 2], reason: 'проигранное открытие не начинается заново');
  });
}
