import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree.dart';
import 'package:love_app/models/xmas_tree_geometry.dart';
import 'package:love_app/widgets/xmas/tree_draw.dart';
import 'package:love_app/widgets/xmas/tree_stage.dart';
import 'package:love_app/widgets/xmas/tree_sway.dart';

/// Ёлка покачивается, как в макете (26.11.2026, владелец: «А почему ёлка не
/// анимирована?»): поворот ±0,07 рад за 7 с, игрушки едут вместе с ветками,
/// касание по качающейся ёлке попадает туда же, куда при обычном повороте.
void main() {
  group('поворот', () {
    test('качание идёт вокруг обычного поворота на 0,07 рад', () {
      expect(xtSwayYaw(0, 1), closeTo(kXtYaw, 1e-9));
      expect(xtSwayYaw(0.25, 1), closeTo(kXtYaw + 0.07, kXtYawStep));
      expect(xtSwayYaw(0.75, 1), closeTo(kXtYaw - 0.07, kXtYawStep));
      expect(xtSwayYaw(0.25, 0), closeTo(kXtYaw, 1e-9), reason: 'размах 0 — ёлка стоит');
    });

    test('поворот берётся шагами: каждый шаг рисуется один раз', () {
      final a = xtTreePictures('fir', kXtYaw + 0.0004, garland: true);
      final b = xtTreePictures('fir', kXtYaw + 0.0006, garland: true);
      expect(identical(a, xtTreePictures('fir', kXtYaw + 0.0004, garland: true)), isTrue);
      expect(a.layers.keys, containsAll(['base', 't3', 't2', 't1', 't0', 'star']));
      expect(xtQuantizeYaw(kXtYaw + 0.0004), isNot(xtQuantizeYaw(kXtYaw + 0.0016)));
      expect(b.layers, hasLength(6));
    });
  });

  group('касание качающейся ёлки', () {
    test('точка на хвое при повороте переводится в ту же точку при обычном', () {
      // игрушка, повешенная в (50, 60) при обычном повороте
      final a = xtAnchor('fir', 50, 60)!;
      for (final yaw in [kXtYaw - 0.07, kXtYaw + 0.05]) {
        final moved = xtHangPoint('fir', a, yaw: yaw).screen;
        final back = xtUnsway('fir', moved.dx, moved.dy, yaw);
        final home = xtHangPoint('fir', a).screen;
        expect((back - home).distance, lessThan(1.6), reason: 'поворот $yaw');
        expect((moved - home).distance, greaterThan(0.3), reason: 'игрушка правда уехала с веткой');
      }
    });

    test('игрушку под пальцем ищут на повёрнутой ёлке', () {
      const toy = TreeToy(id: 't', toy: 'red', x: 30, y: 64, author: 'me');
      final a = xtAnchor('fir', toy.x, toy.y)!;
      const yaw = kXtYaw + 0.07;
      final h = xtHangPoint('fir', a, yaw: yaw);
      final body = h.screen + Offset(0, 7 * h.scale / 0.15);
      expect(xtToyAt('fir', const [toy], body, yaw: yaw)?.id, 't');
    });

    test('мимо хвои точка не двигается', () {
      expect(xtUnsway('fir', 2, 2, kXtYaw + 0.07), const Offset(2, 2));
    });
  });

  testWidgets('ёлка качается, игрушки едут вместе с ней', (tester) async {
    const toys = [TreeToy(id: 't', toy: 'red', x: 30, y: 64, author: 'me')];
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: XtSway(builder: (context, yaw) => TreeStage(side: 300, tree: const PairTree(), toys: toys, yaw: yaw, still: true)),
      ),
    ));
    // ключ игрушки стоит на её Positioned
    double toyLeft() => tester.widget<Positioned>(find.byKey(const ValueKey('t'))).left!;
    final at0 = toyLeft();
    await tester.pump(const Duration(milliseconds: 1750));
    final atQuarter = toyLeft();
    expect((atQuarter - at0).abs(), greaterThan(1), reason: 'через четверть круга игрушка сдвинулась');
  });

  testWidgets('игрушка в руке — ёлка встаёт в обычный поворот', (tester) async {
    final seen = <double>[];
    Widget app(bool calm) => MaterialApp(home: XtSway(calm: calm, builder: (context, yaw) {
          seen.add(yaw);
          return const SizedBox();
        }));
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 1750));
    expect((seen.last - kXtYaw).abs(), greaterThan(0.05));
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 100));
    expect(seen.last, closeTo(kXtYaw, kXtYawStep));
  });

  testWidgets('без анимаций в системе ёлка стоит', (tester) async {
    final seen = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: XtSway(builder: (context, yaw) {
          seen.add(yaw);
          return const SizedBox();
        }),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(seen.every((y) => y == kXtYaw), isTrue);
  });
}
