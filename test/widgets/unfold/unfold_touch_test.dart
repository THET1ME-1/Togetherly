import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/unfold_touch.dart';

const _button = ValueKey<String>('button');

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// Список с одной кнопкой: вокруг неё прокрутка со своим слушателем касаний.
Widget _listWithButton({VoidCallback? onTap}) => ListView(
      children: [
        const SizedBox(height: 120),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 40),
            child: GestureDetector(
              onTap: onTap ?? () {},
              child: Container(
                key: _button,
                width: 140,
                height: 48,
                color: Colors.teal,
              ),
            ),
          ),
        ),
        const SizedBox(height: 1200),
      ],
    );

void main() {
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 11, 12);
    UnfoldTouch.install();
    UnfoldTouch.forget();
    UnfoldTouch.clock = () => now;
  });

  tearDown(() => UnfoldTouch.clock = DateTime.now);

  testWidgets('кнопка в списке даёт место кнопки, а не списка', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tap(find.byKey(_button));

    final spot = UnfoldTouch.take();
    expect(spot, isNotNull);
    expect(spot!.rect(null), tester.getRect(find.byKey(_button)));
  });

  testWidgets('место отдаётся один раз', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tap(find.byKey(_button));

    expect(UnfoldTouch.take(), isNotNull);
    expect(UnfoldTouch.take(), isNull);
  });

  testWidgets('палец уехал — это прокрутка, расти не из чего', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.drag(find.byKey(_button), const Offset(0, -60));

    expect(UnfoldTouch.take(), isNull);
  });

  testWidgets('нажатие по пустому месту списка места не даёт', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tapAt(const Offset(300, 400));

    expect(UnfoldTouch.take(), isNull);
  });

  testWidgets('старое нажатие не годится', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tap(find.byKey(_button));
    now = now.add(const Duration(milliseconds: 1600));

    expect(UnfoldTouch.take(), isNull);
  });

  testWidgets('палец ещё лежит (долгое нажатие) — место годится',
      (tester) async {
    await _pump(tester, _listWithButton());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_button)));
    now = now.add(const Duration(seconds: 2));

    expect(UnfoldTouch.take(), isNotNull);
    await gesture.up();
  });

  testWidgets('кнопки уже нет на экране — места нет', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tap(find.byKey(_button));
    await _pump(tester, const SizedBox());

    expect(UnfoldTouch.take(), isNull);
  });

  testWidgets('скругление берётся у формы кнопки', (tester) async {
    await _pump(
      tester,
      Center(
        child: SizedBox(
          width: 200,
          height: 56,
          child: FilledButton(
            key: _button,
            onPressed: () {},
            child: const Text('Дальше'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_button));

    final spot = UnfoldTouch.take()!;
    expect(spot.radius, 28);
    expect(spot.rect(null), tester.getRect(find.byKey(_button)));
  });

  testWidgets('круг внутри зоны нажатия: местом становится сам круг',
      (tester) async {
    const circle = ValueKey<String>('circle');
    await _pump(
      tester,
      Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                key: circle,
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: Colors.indigo, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(circle));

    final spot = UnfoldTouch.take()!;
    expect(spot.rect(null), tester.getRect(find.byKey(circle)));
    expect(spot.radius, 20);
  });

  testWidgets('без формы скругление — половина короткой стороны, не больше 24',
      (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tap(find.byKey(_button));

    // Кнопка 140×48 залита `ColoredBox`: формы у него не спросить.
    expect(UnfoldTouch.take()!.radius, 24);
  });

  testWidgets('экран целиком местом не считается', (tester) async {
    await _pump(
      tester,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: const SizedBox.expand(),
      ),
    );
    await tester.tapAt(const Offset(180, 380));

    expect(UnfoldTouch.take(), isNull);
  });

  testWidgets('снимок места совпадает с ним размером', (tester) async {
    await _pump(tester, _listWithButton());
    await tester.tap(find.byKey(_button));
    await tester.pump();

    final image = UnfoldTouch.take()!.snapshot(2);
    expect(image, isNotNull);
    expect(image!.width, 280);
    expect(image.height, 96);
    image.dispose();
  });

  group('картинка нажатой миниатюры', () {
    late ui.Image photo;

    Future<void> pumpThumb(WidgetTester tester, {bool veiled = false}) async {
      photo = (await tester.runAsync(
          () => createTestImage(width: 40, height: 30)))!;
      addTearDown(photo.dispose);
      Widget thumb = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          key: _button,
          width: 120,
          height: 60,
          child: RawImage(image: photo, fit: BoxFit.cover),
        ),
      );
      if (veiled) thumb = UnfoldVeiled(child: thumb);
      await _pump(
        tester,
        Center(child: GestureDetector(onTap: () {}, child: thumb)),
      );
    }

    testWidgets('отдаётся вместе с местом и скруглением', (tester) async {
      await pumpThumb(tester);
      await tester.tap(find.byKey(_button));

      final shot = UnfoldTouch.takeImage();
      expect(shot, isNotNull);
      expect(shot!.image.width, 40);
      expect(shot.image.height, 30);
      expect(shot.radius, 12);
      expect(shot.rect(null), tester.getRect(find.byKey(_button)));
      shot.dispose();
    });

    testWidgets('под завесой 18+ в полёт не идёт', (tester) async {
      await pumpThumb(tester, veiled: true);
      await tester.tap(find.byKey(_button));

      expect(UnfoldTouch.takeImage(), isNull);
    });

    testWidgets('нажали не на картинку — картинки нет', (tester) async {
      await _pump(tester, _listWithButton());
      await tester.tap(find.byKey(_button));

      expect(UnfoldTouch.takeImage(), isNull);
    });
  });
}
