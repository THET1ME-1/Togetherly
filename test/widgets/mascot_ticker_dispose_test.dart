import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/widgets/mascot/pixel_mascot_view.dart';

/// Кадры маскота гонит `Ticker`, и жизнь у него длиннее одного кадра: он
/// переживает уход с экрана, если забыть его убрать. `SingleTickerProviderState`
/// ловит забытый тикер ассертом только в отладке, поэтому тест проверяет оба
/// конца — что виджет уходит с экрана без единой ошибки и что живой тикер
/// крутит кадры, не роняя экран по дороге.
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

  testWidgets('уход с экрана гасит тикер, а не роняет его', (tester) async {
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
