import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/canvas_pinch.dart';

/// Щипок по холсту рисовалки.
///
/// Отзыв из Play (2 августа, 1.21.1): «в комнате с рисовашками экран и
/// инструменты багаются и экран мечется туда сюда в какой то момент, мешая
/// рисовать». Ловится это здесь: пока пальцев меньше двух, холст не двигается
/// вовсе, а возвращение второго пальца перезахватывает опору, а не тянет лист
/// к новой точке.
void main() {
  group('pinchAction', () {
    test('два пальца — обычный щипок', () {
      expect(pinchAction(pointerCount: 2, paused: false), PinchAction.transform);
    });

    test('палец подняли — холст замирает', () {
      // Flutter продолжает слать события с одним пальцем, и фокус скачком
      // уезжает к нему: без паузы лист прыгал за оставшимся пальцем.
      expect(pinchAction(pointerCount: 1, paused: false), PinchAction.pause);
      expect(pinchAction(pointerCount: 0, paused: false), PinchAction.pause);
    });

    test('второй палец вернулся — сначала перезахват опоры', () {
      expect(pinchAction(pointerCount: 2, paused: true), PinchAction.rebase);
    });

    test('после паузы одним пальцем по-прежнему ничего не двигаем', () {
      expect(pinchAction(pointerCount: 1, paused: true), PinchAction.pause);
    });
  });

  group('pinchOffset', () {
    test('фокус не сдвинулся и масштаб тот же — холст стоит', () {
      final offset = pinchOffset(
        focal: const Offset(100, 200),
        baseFocal: const Offset(100, 200),
        baseOffset: const Offset(10, 20),
        baseScale: 1.0,
        nextScale: 1.0,
        baseRotation: 0,
        nextRotation: 0,
      );
      expect(offset.dx, closeTo(10, 0.001));
      expect(offset.dy, closeTo(20, 0.001));
    });

    test('фокус уехал — холст едет ровно за ним', () {
      final offset = pinchOffset(
        focal: const Offset(140, 200),
        baseFocal: const Offset(100, 200),
        baseOffset: Offset.zero,
        baseScale: 1.0,
        nextScale: 1.0,
        baseRotation: 0,
        nextRotation: 0,
      );
      expect(offset.dx, closeTo(40, 0.001));
      expect(offset.dy, closeTo(0, 0.001));
    });

    test('точка под пальцами остаётся под пальцами при увеличении', () {
      const focal = Offset(100, 100);
      final offset = pinchOffset(
        focal: focal,
        baseFocal: focal,
        baseOffset: Offset.zero,
        baseScale: 1.0,
        nextScale: 2.0,
        baseRotation: 0,
        nextRotation: 0,
      );
      // Холст под пальцем был в (100,100); после удвоения он оказался бы в
      // (200,200), поэтому смещение обязано вернуть его на место.
      expect(offset.dx, closeTo(-100, 0.001));
      expect(offset.dy, closeTo(-100, 0.001));
    });
  });
}
