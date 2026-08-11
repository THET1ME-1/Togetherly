import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/screens/home/home_action_buttons.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Кнопка фото делает две разные вещи: тап снимает кадр, удержание пишет
/// ролик. Жесты легко разъезжаются при правках анимации нажатия, поэтому
/// проверяются оба.
void main() {
  Widget host({
    required VoidCallback onPost,
    VoidCallback? onPostHold,
    bool paired = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: HomeActionButtons(
          theme: buildAppTheme(kPalettes[0], Brightness.light),
          isPaired: paired,
          myMoodImagePath: '',
          onDraw: () {},
          onMood: () {},
          onCalendar: () {},
          onPost: onPost,
          onPostHold: onPostHold,
        ),
      ),
    );
  }

  testWidgets('тап зовёт снимок, удержание — ролик', (tester) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(host(
      onPost: () => taps++,
      onPostHold: () => holds++,
    ));

    // Кнопка фото — четвёртая в ряду.
    final photo = find.byType(GestureDetector).last;

    await tester.tap(photo);
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 1);
    expect(holds, 0);

    await tester.longPress(photo);
    await tester.pump(const Duration(milliseconds: 300));
    expect(holds, 1);
    expect(taps, 1, reason: 'удержание не должно считаться тапом');
  });

  testWidgets('без пары кнопки молчат', (tester) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(host(
      onPost: () => taps++,
      onPostHold: () => holds++,
      paired: false,
    ));

    // Ряд без пары рисуется приглушённым, но не отвечает: все четыре кнопки
    // пишут в коллекции с `group_id`, и без партнёра любое нажатие потерялось
    // бы молча. Приглашение вместо ряда ставит уже главный экран.
    final photo = find.byType(GestureDetector).last;
    await tester.tap(photo);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(photo);
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 0);
    expect(holds, 0);
  });
}
