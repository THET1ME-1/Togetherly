import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/season_backdrop.dart';
import 'package:love_app/widgets/season/season_backdrop_layer.dart';

// Прозрачный PNG 1×1: картинке маски в тесте нужна только загрузка.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

const _backdrop = SeasonBackdrop(
  key: 'hw',
  maskUrl: 'mask',
  blurUrl: 'blur',
  handUrl: 'hand',
  until: '2099-01-01',
  cycleMs: 16000,
  inMs: 4000,
  holdMs: 5000,
  outMs: 4000,
);

Widget _host(Widget child, {bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduce),
    child: Scaffold(body: child),
  ),
);

SeasonBackdropLayer _layer({GlobalKey<SeasonBackdropLayerState>? key}) => SeasonBackdropLayer(
  key: key,
  backdrop: _backdrop,
  brightness: Brightness.light,
  accent: const Color(0xFFFE7E8B),
  imageFor: (_) => MemoryImage(_png),
);

double _alphaOf(WidgetTester t, String key) => t.widget<Image>(find.byKey(ValueKey(key))).color!.a;

void main() {
  testWidgets('фон не ловит касаний', (t) async {
    await t.pumpWidget(_host(_layer()));
    expect(find.descendant(of: find.byType(SeasonBackdropLayer), matching: find.byType(IgnorePointer)), findsWidgets);
  });

  testWidgets('в начале петли призрак размыт, на середине — чёткий и плотный', (t) async {
    await t.pumpWidget(_host(_layer()));
    await t.pump(const Duration(milliseconds: 1000));
    final blurEarly = _alphaOf(t, 'backdrop-blur'), sharpEarly = _alphaOf(t, 'backdrop-sharp');
    expect(blurEarly, greaterThan(sharpEarly));
    await t.pump(const Duration(milliseconds: 5000));
    expect(_alphaOf(t, 'backdrop-sharp'), closeTo(_backdrop.opacity(Brightness.light), 0.01));
    expect(_alphaOf(t, 'backdrop-blur'), closeTo(0, 0.01));
    await t.pump(const Duration(milliseconds: 8500));
    expect(find.byKey(const ValueKey('backdrop-sharp')), findsNothing, reason: 'в паузе петли рисовать нечего');
  });

  testWidgets('при «уменьшить движение» призрак стоит неподвижно', (t) async {
    await t.pumpWidget(_host(_layer(), reduce: true));
    final a = _alphaOf(t, 'backdrop-sharp');
    await t.pump(const Duration(milliseconds: 9000));
    expect(_alphaOf(t, 'backdrop-sharp'), a);
    expect(a, greaterThan(0));
  });

  testWidgets('призрак по «Скучаю»: сам не появляется, приходит на нажатие и уходит', (t) async {
    final key = GlobalKey<SeasonBackdropLayerState>();
    await t.pumpWidget(_host(SeasonBackdropLayer(
      key: key,
      backdrop: const SeasonBackdrop(
        key: 'hw',
        maskUrl: 'mask',
        blurUrl: 'blur',
        until: '2099-01-01',
        trigger: 'miss',
        inMs: 1600,
        holdMs: 3500,
        outMs: 2600,
      ),
      brightness: Brightness.light,
      accent: const Color(0xFFFE7E8B),
      imageFor: (_) => MemoryImage(_png),
    )));
    await t.pump(const Duration(seconds: 20));
    expect(find.byKey(const ValueKey('backdrop-sharp')), findsNothing, reason: 'без нажатия призрака нет');

    key.currentState!.summon();
    await t.pump(); // первый кадр тикера
    await t.pump(const Duration(milliseconds: 3000));
    expect(_alphaOf(t, 'backdrop-sharp'), greaterThan(0.7));

    // Второе нажатие, пока стоит, продлевает его, а не начинает заново из пустоты.
    key.currentState!.summon();
    await t.pump(const Duration(milliseconds: 3000));
    expect(_alphaOf(t, 'backdrop-sharp'), greaterThan(0.7));

    await t.pump(const Duration(seconds: 8));
    expect(find.byKey(const ValueKey('backdrop-sharp')), findsNothing);
  });

  testWidgets('ладонь прижимается в точке касания и уходит', (t) async {
    final key = GlobalKey<SeasonBackdropLayerState>();
    await t.pumpWidget(_host(_layer(key: key)));
    key.currentState!.press(const Offset(200, 300));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('backdrop-hand')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 4000));
    expect(find.byKey(const ValueKey('backdrop-hand')), findsNothing);
  });

  testWidgets('ладонь только от нажатия в пустое место: кнопка и прокрутка работают как раньше', (t) async {
    final button = GlobalKey();
    final empty = <Offset>[];
    var pressed = 0;
    await t.pumpWidget(_host(BackdropTapCatcher(
      onEmptyTap: empty.add,
      child: ListView(
        children: [
          const SizedBox(height: 200),
          Center(child: FilledButton(key: button, onPressed: () => pressed++, child: const Text('Кнопка'))),
          const SizedBox(height: 1200),
        ],
      ),
    )));
    await t.tap(find.byKey(button));
    expect(pressed, 1);
    expect(empty, isEmpty, reason: 'нажатие кнопки не уходит в фон');

    await t.tapAt(const Offset(195, 100));
    expect(empty, hasLength(1));

    await t.drag(find.byType(ListView), const Offset(0, -120));
    await t.pumpAndSettle();
    expect(empty, hasLength(1), reason: 'прокрутка не считается нажатием');
    expect(t.getTopLeft(find.byKey(button)).dy, lessThan(200), reason: 'и сама прокрутка работает');
  });
}
