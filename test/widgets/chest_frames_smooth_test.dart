import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

/// TOG-70 (канал, 27.10.2026): «анимация открывания сундука кажется зависает».
///
/// Две вещи в проигрывателе. Следующий кадр распаковывается заранее, пока
/// стоит текущий: раньше распаковка начиналась в момент, когда кадр уже пора
/// показать, и на слабом телефоне каждый кадр опаздывал на её время. И после
/// открытия сундук не застывает последним кадром, а уходит в петлю
/// [ChestFrames.afterUrl], где живёт обводка.
void main() {
  const open = 'test://smooth_open.webp';
  const hold = 'test://smooth_hold.webp';

  setUpAll(() {
    final bytes = File('test/fixtures/chest_frames_3.webp').readAsBytesSync();
    ChestFrames.debugPut(open, bytes);
    ChestFrames.debugPut(hold, bytes);
  });

  Future<void> settle(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 70));
    }
  }

  testWidgets('следующий кадр готов к сроку и показывается в тот же тик', (tester) async {
    final frames = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: ChestFrames(url: open, still: null, side: 100, loop: false, onFrame: frames.add),
    ));
    // Дождаться первого кадра.
    for (var i = 0; i < 20 && frames.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(frames, [0]);
    // Пока кадр стоит, следующий распаковывается.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    // Срок пришёл: один тик, без ожидания распаковки.
    await tester.pump(const Duration(milliseconds: 200));
    expect(frames, [0, 1], reason: 'кадр 1 обязан быть распакован заранее');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('после открытия сундук уходит в петлю, а не застывает', (tester) async {
    final frames = <int>[], done = <int>[], after = <Duration>[];
    await tester.pumpWidget(MaterialApp(
      home: ChestFrames(
        url: open,
        afterUrl: hold,
        still: null,
        side: 100,
        loop: false,
        onFrame: frames.add,
        onDone: () => done.add(1),
        onAfter: after.add,
      ),
    ));
    await settle(tester, 12);
    expect(frames, [0, 1, 2], reason: 'кадры петли не выдаются за кадры открытия');
    expect(done, [1], reason: 'конец открытия приходит ровно один раз');
    await settle(tester, 12);
    expect(after.length, greaterThan(3), reason: 'петля играет: $after');
    expect(after.first, Duration.zero);
    expect(after.last, greaterThan(after.first));
    expect(frames, [0, 1, 2]);
    expect(done, [1]);
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
