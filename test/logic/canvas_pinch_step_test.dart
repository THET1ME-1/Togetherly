import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/canvas_pinch.dart';

/// Щипок двумя пальцами. Жалоба со скринкастом (21.08.2026): «если двигать
/// холст двумя пальцами, он дёргается и улетает куда попало; ладошкой всё
/// супер».
///
/// Причина в том, что Flutter при КАЖДОМ изменении состава пальцев берёт новую
/// точку отсчёта: `_reconfigure` заново назначает span, линию и фокус, поэтому
/// `scale` возвращается к единице, `rotation` к нулю, а средний фокус скачком
/// уезжает. Обработчик, который считал от собственной базы и абсолютного
/// фокуса, в этот момент рвал холст. Здесь проверяется счёт ОТНОСИТЕЛЬНО
/// прошлого кадра — он с такой перестройкой согласован.
const _view = CanvasView(scale: 1, rotation: 0, offset: Offset.zero);

void main() {
  group('шаг щипка', () {
    test('фокус уехал вправо — холст уехал ровно за ним', () {
      final next = applyPinch(
        _view,
        const PinchStep(
          focal: Offset(140, 200),
          focalDelta: Offset(40, 0),
          scaleStep: 1,
          rotationStep: 0,
        ),
      );
      expect(next.offset.dx, closeTo(40, 0.001));
      expect(next.offset.dy, closeTo(0, 0.001));
      expect(next.scale, 1);
    });

    test('пальцы развелись — точка под ними осталась под ними', () {
      const focal = Offset(100, 100);
      final next = applyPinch(
        _view,
        const PinchStep(
          focal: focal,
          focalDelta: Offset.zero,
          scaleStep: 2,
          rotationStep: 0,
        ),
      );
      // Точка холста под фокусом: до шага (100,100), после — там же.
      final under = (focal - next.offset) / next.scale;
      expect(under.dx, closeTo(100, 0.001));
      expect(under.dy, closeTo(100, 0.001));
      expect(next.scale, closeTo(2, 0.001));
    });

    test('поворот идёт вокруг пальцев, а не вокруг угла листа', () {
      const focal = Offset(100, 100);
      final next = applyPinch(
        _view,
        PinchStep(
          focal: focal,
          focalDelta: Offset.zero,
          scaleStep: 1,
          rotationStep: math.pi / 2,
        ),
      );
      expect(next.rotation, closeTo(math.pi / 2, 0.001));
      // Точка холста под фокусом не должна уехать: считаем обратным ходом.
      final v = focal - next.offset;
      final c = Offset(
        v.dx * math.cos(-next.rotation) - v.dy * math.sin(-next.rotation),
        v.dx * math.sin(-next.rotation) + v.dy * math.cos(-next.rotation),
      );
      expect(c.dx, closeTo(100, 0.001));
      expect(c.dy, closeTo(100, 0.001));
    });

    test('масштаб зажат пределами', () {
      final huge = applyPinch(
        _view,
        const PinchStep(
          focal: Offset.zero,
          focalDelta: Offset.zero,
          scaleStep: 1000,
          rotationStep: 0,
        ),
        maxScale: 6,
      );
      expect(huge.scale, 6);
    });
  });

  group('перестройка жеста', () {
    test('число пальцев изменилось — кадр пропускаем целиком', () {
      final t = PinchTracker()..begin();
      // Первый кадр двумя пальцами задаёт опору.
      expect(
        t.step(pointerCount: 2, scale: 1, rotation: 0,
            focal: const Offset(100, 100), focalDelta: Offset.zero),
        isNull,
      );
      // Тянем: масштаб пошёл вверх.
      final grow = t.step(pointerCount: 2, scale: 1.5, rotation: 0,
          focal: const Offset(100, 100), focalDelta: Offset.zero);
      expect(grow!.scaleStep, closeTo(1.5, 0.001));

      // Лёг третий палец: Flutter обнулил span и увёл средний фокус.
      // Этот кадр не должен двигать холст ВООБЩЕ — ни масштабом, ни сдвигом.
      final rebuild = t.step(pointerCount: 3, scale: 1, rotation: 0,
          focal: const Offset(180, 60), focalDelta: const Offset(80, -40));
      expect(rebuild, isNull);

      // Следующий кадр считается от новой опоры, а не от старой.
      final after = t.step(pointerCount: 3, scale: 1.1, rotation: 0,
          focal: const Offset(182, 60), focalDelta: const Offset(2, 0));
      expect(after!.scaleStep, closeTo(1.1, 0.001));
      expect(after.focalDelta.dx, closeTo(2, 0.001));
    });

    test('палец подняли — холст замирает, пока их меньше двух', () {
      final t = PinchTracker()..begin();
      t.step(pointerCount: 2, scale: 1, rotation: 0,
          focal: const Offset(100, 100), focalDelta: Offset.zero);
      final one = t.step(pointerCount: 1, scale: 1, rotation: 0,
          focal: const Offset(40, 100), focalDelta: const Offset(-60, 0));
      expect(one, isNull);
    });

    test('поворот включается только после заметного разворота', () {
      final t = PinchTracker()..begin();
      t.step(pointerCount: 2, scale: 1, rotation: 0,
          focal: Offset.zero, focalDelta: Offset.zero);
      final small = t.step(pointerCount: 2, scale: 1, rotation: 0.05,
          focal: Offset.zero, focalDelta: Offset.zero);
      expect(small!.rotationStep, 0, reason: 'дрожь руки листа не кренит');

      final big = t.step(pointerCount: 2, scale: 1, rotation: 0.5,
          focal: Offset.zero, focalDelta: Offset.zero);
      expect(big!.rotationStep, greaterThan(0));
      // Порог вычитается один раз, а не прибавляется рывком.
      expect(big.rotationStep, closeTo(0.5 - kPinchRotationSlop, 0.001));

      final more = t.step(pointerCount: 2, scale: 1, rotation: 0.6,
          focal: Offset.zero, focalDelta: Offset.zero);
      expect(more!.rotationStep, closeTo(0.1, 0.001));
    });
  });
}
