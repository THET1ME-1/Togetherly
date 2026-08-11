import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/widgets/mascot/pixel_mascot_view.dart';

/// Кадры маскота гонит таймер, и он переживает уход с экрана, если забыть его
/// отменить: дальше идут `setState` у мёртвого состояния. Тест держит оба
/// конца — виджет уходит с экрана без единой ошибки и полторы секунды крутит
/// кадры, не роняя экран по дороге.
void main() {
  const anim = MascotAnim(
    id: 'test',
    nameRu: 'Проверка',
    nameEn: 'Test',
    sheetUrl: 'https://example.invalid/atlas.webp',
    frame: 32,
    cols: 6,
    fps: 10,
    rows: ['live'],
  );

  testWidgets('уход с экрана гасит кадры, а не роняет экран', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PixelMascotView(anim: anim, state: MascotAnimState.live),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('живой маскот не держит экран в перестроениях', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PixelMascotView(anim: anim, state: MascotAnimState.live),
      ),
    );

    // Полторы секунды кадров: без атласа рисовать нечего, но тикер идёт и
    // двигает кадр — важно, что это не роняет виджет и не сыплет ошибками.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
  });
}
