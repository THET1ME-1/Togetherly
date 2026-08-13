import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/optimistic_count.dart';

void main() {
  final t0 = DateTime(2026, 8, 13, 12, 0, 0);

  group('OptimisticCount', () {
    test('тап показывает +1 сразу, до ответа сервера', () {
      final c = OptimisticCount(confirmed: 10).tap(t0);
      expect(c.display, 11);
    });


    // Жалоба 13 августа 2026: «Скучаю откатывается на предыдущие состояния».
    // Счётчик пары только растёт, а `confirm` слепо принимал любое число с
    // сервера. Между офлайн-кэшем, отставшим снимком realtime и повторным
    // чтением до людей доезжало старое значение — и число прыгало назад на
    // глазах.
    test('устаревший снимок не откатывает число назад', () {
      final c = OptimisticCount(confirmed: 577)
          .confirm(561, now: t0);
      expect(c.display, 577);
      expect(c.confirmed, 577);
    });

    test('после тапа устаревший снимок тоже не роняет счёт', () {
      final c = OptimisticCount(confirmed: 577)
          .tap(t0)
          .confirm(570, now: t0.add(const Duration(seconds: 1)));
      expect(c.display, 578);
    });

    test('рост сервера принимается как прежде', () {
      final c = OptimisticCount(confirmed: 577).confirm(580, now: t0);
      expect(c.display, 580);
    });

    test('смена пары обнуляет счёт явно', () {
      final c = OptimisticCount(confirmed: 577).tap(t0).reset();
      expect(c.display, 0);
      expect(c.pending, 0);
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

    // Сброс приходит не снимком, а сменой пары: обнуление снимком неотличимо
    // от пустого кэша, который отдаёт ноль раньше, чем сервер ответит.
    test('счётчик сбрасывается сменой пары, а не нулём в снимке', () {
      expect(OptimisticCount(confirmed: 10).confirm(0, now: t0).display, 10);
      expect(OptimisticCount(confirmed: 10).reset().display, 0);
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
