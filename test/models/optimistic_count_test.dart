import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/optimistic_count.dart';

void main() {
  final t0 = DateTime(2026, 8, 13, 12, 0, 0);

  group('OptimisticCount', () {
    test('тап показывает +1 сразу, до ответа сервера', () {
      final c = OptimisticCount(confirmed: 10).tap(t0);
      expect(c.display, 11);
    });

    test('подтверждение сервера снимает ожидание, число не прыгает', () {
      final c = OptimisticCount(confirmed: 10)
          .tap(t0)
          .confirm(11, now: t0.add(const Duration(seconds: 1)));
      expect(c.display, 11);
      expect(c.pending, 0);
    });

    test('отказ отправки снимает надбавку сразу', () {
      final c = OptimisticCount(confirmed: 10).tap(t0).failed();
      expect(c.display, 10);
      expect(c.pending, 0);
    });

    test('три тапа подряд подтверждаются одним снимком', () {
      var c = OptimisticCount(confirmed: 5);
      for (var i = 0; i < 3; i++) {
        c = c.tap(t0);
      }
      expect(c.display, 8);
      c = c.confirm(8, now: t0.add(const Duration(seconds: 2)));
      expect(c.display, 8);
      expect(c.pending, 0);
    });

    test('молчание сокета не оставляет надбавку навсегда', () {
      // Сервер записал импульс, но событие не доехало: подписка переподнялась
      // и прислала тот же счётчик. Ожидание протухает и число садится на
      // серверное, а не живёт своей жизнью.
      final c = OptimisticCount(confirmed: 10)
          .tap(t0)
          .confirm(10, now: t0.add(OptimisticCount.ttl))
          .confirm(10, now: t0.add(OptimisticCount.ttl * 2));
      expect(c.display, 10);
      expect(c.pending, 0);
    });

    test('свежее ожидание переподписка не сбрасывает', () {
      final c = OptimisticCount(confirmed: 10)
          .tap(t0)
          .confirm(10, now: t0.add(const Duration(seconds: 1)));
      expect(c.display, 11);
      expect(c.pending, 1);
    });

    test('число никогда не уходит вниз от подтверждённого', () {
      final c = OptimisticCount(confirmed: 10)
          .tap(t0)
          .confirm(12, now: t0.add(const Duration(seconds: 1)));
      // Партнёрское устройство добавило свои импульсы: сервер обогнал нас на
      // два, ожидание снято целиком, отрицательных остатков нет.
      expect(c.display, 12);
      expect(c.pending, 0);
    });

    test('счётчик сбросили на сервере — показываем его правду', () {
      final c = OptimisticCount(confirmed: 10).confirm(0, now: t0);
      expect(c.display, 0);
    });

    test('отказ без ожидания ничего не портит', () {
      final c = OptimisticCount(confirmed: 3).failed();
      expect(c.display, 3);
      expect(c.pending, 0);
    });

    test('смена пары обнуляет ожидания', () {
      final c = OptimisticCount(confirmed: 10).tap(t0).reset();
      expect(c.display, 0);
      expect(c.pending, 0);
    });
  });
}
