import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/stroke_save_scheduler.dart';

void main() {
  test('сотня клеток подряд пишет холст один раз, а не сто', () {
    fakeAsync((async) {
      var saves = 0;
      final scheduler = StrokeSaveScheduler(
        save: () async => saves++,
        interval: const Duration(milliseconds: 600),
      );

      // Пиксельная раскраска: каждая клетка — отдельный штрих.
      for (var i = 0; i < 100; i++) {
        scheduler.schedule();
        async.elapse(const Duration(milliseconds: 5));
      }
      expect(saves, 0, reason: 'пока палец рисует, на диск не ходим');

      async.elapse(const Duration(seconds: 1));
      expect(saves, 1);
    });
  });

  test('после паузы копится заново', () {
    fakeAsync((async) {
      var saves = 0;
      final scheduler = StrokeSaveScheduler(
        save: () async => saves++,
        interval: const Duration(milliseconds: 600),
      );

      scheduler.schedule();
      async.elapse(const Duration(seconds: 1));
      scheduler.schedule();
      async.elapse(const Duration(seconds: 1));

      expect(saves, 2);
    });
  });

  test('выход с экрана дописывает последний штрих немедленно', () {
    fakeAsync((async) {
      var saves = 0;
      final scheduler = StrokeSaveScheduler(
        save: () async => saves++,
        interval: const Duration(milliseconds: 600),
      );

      scheduler.schedule();
      scheduler.flushNow();
      async.flushMicrotasks();

      expect(saves, 1, reason: 'нарисованное нельзя терять при выходе');

      async.elapse(const Duration(seconds: 1));
      expect(saves, 1, reason: 'отложенная запись отменена, дважды не пишем');
    });
  });

  test('без запланированных правок сброс ничего не пишет', () {
    fakeAsync((async) {
      var saves = 0;
      final scheduler = StrokeSaveScheduler(
        save: () async => saves++,
        interval: const Duration(milliseconds: 600),
      );

      scheduler.flushNow();
      async.flushMicrotasks();

      expect(saves, 0);
    });
  });

  test('уничтожение экрана не теряет последний штрих', () {
    fakeAsync((async) {
      var saves = 0;
      final scheduler = StrokeSaveScheduler(
        save: () async => saves++,
        interval: const Duration(milliseconds: 600),
      );

      scheduler.schedule();
      scheduler.dispose();
      async.flushMicrotasks();

      expect(saves, 1);

      async.elapse(const Duration(seconds: 1));
      expect(saves, 1, reason: 'после dispose таймер не оживает');
    });
  });

  test('пока идёт запись, новые правки ждут следующего круга', () {
    fakeAsync((async) {
      var saves = 0;
      var running = 0;
      final scheduler = StrokeSaveScheduler(
        save: () async {
          running++;
          expect(running, 1, reason: 'две записи разом затирают друг друга');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          running--;
          saves++;
        },
        interval: const Duration(milliseconds: 100),
      );

      scheduler.schedule();
      async.elapse(const Duration(milliseconds: 150));
      // Правка пришла, пока первая запись ещё идёт.
      scheduler.schedule();
      async.elapse(const Duration(seconds: 2));

      expect(saves, 2, reason: 'правка во время записи уходит следующим кругом');
    });
  });
}
