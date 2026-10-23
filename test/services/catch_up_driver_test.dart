// TOG-17: «сообщения от партнёра приходят, но при входе в чат их некоторое
// время не видно» (отзыв в Google Play, 1.38.0).
//
// Открытый чат узнаёт о новых сообщениях только из сокета. Сокет рвётся
// постоянно (мобильная сеть, сон телефона, MIUI), и события, пришедшие в
// разрыв, не досылаются никогда: на эмуляторе 23.10.2026 сокет не поднимался
// семь минут, и сообщение партнёра появилось только после выхода и входа.
// Значит, открытый список должен сам дотягивать пропущенное с сервера.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/catch_up_driver.dart';

class _Harness {
  final reconnected = StreamController<void>.broadcast();
  final foreground = StreamController<bool>.broadcast();
  bool subscribed = true;
  int runs = 0;
  Completer<void>? gate;
  late final CatchUpDriver driver;

  _Harness(FakeAsync async) {
    driver = CatchUpDriver(
      catchUp: () async {
        runs++;
        final g = gate;
        if (g != null) await g.future;
      },
      reconnected: reconnected.stream,
      foreground: foreground.stream,
      subscribed: () => subscribed,
      jitter: () => const Duration(milliseconds: 500),
      // Часы fakeAsync: DateTime.now() идёт по настоящему времени.
      now: async.getClock(DateTime(2026, 10, 23)).now,
    );
  }
}

void main() {
  test('переподключение сокета догоняет пропущенное', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.reconnected.add(null);
      async.elapse(const Duration(milliseconds: 400));
      expect(h.runs, 0, reason: 'догон идёт с разбросом, а не всеми разом');
      async.elapse(const Duration(milliseconds: 200));
      expect(h.runs, 1);
      h.driver.dispose();
    });
  });

  test('возврат приложения после паузы догоняет', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.foreground.add(false);
      async.elapse(const Duration(seconds: 20));
      h.foreground.add(true);
      async.elapse(const Duration(seconds: 1));
      expect(h.runs, 1);
      h.driver.dispose();
    });
  });

  test('короткий уход из приложения не дёргает сервер', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.foreground.add(false);
      async.elapse(const Duration(seconds: 1));
      h.foreground.add(true);
      async.elapse(const Duration(seconds: 1));
      expect(h.runs, 0);
      h.driver.dispose();
    });
  });

  test('пока сокет лежит, список дотягивается раз в 15 секунд', () {
    fakeAsync((async) {
      final h = _Harness(async)..subscribed = false;
      async.elapse(const Duration(seconds: 14));
      expect(h.runs, 0);
      async.elapse(const Duration(seconds: 1));
      expect(h.runs, 1);
      async.elapse(const Duration(seconds: 15));
      expect(h.runs, 2);
      h.driver.dispose();
    });
  });

  test('с живым сокетом таймер сервер не дёргает', () {
    fakeAsync((async) {
      final h = _Harness(async);
      async.elapse(const Duration(minutes: 2));
      expect(h.runs, 0);
      h.driver.dispose();
    });
  });

  test('в фоне таймер молчит, даже если сокета нет', () {
    fakeAsync((async) {
      final h = _Harness(async)..subscribed = false;
      h.foreground.add(false);
      async.elapse(const Duration(minutes: 2));
      expect(h.runs, 0);
      h.driver.dispose();
    });
  });

  test('догоны не идут вперехлёст, а повод во время догона даёт ещё один', () {
    fakeAsync((async) {
      final h = _Harness(async)..gate = Completer<void>();
      h.reconnected.add(null);
      async.elapse(const Duration(seconds: 1));
      expect(h.runs, 1);
      // Пока первый догон ждёт сервер, сокет переподключился ещё раз.
      h.reconnected.add(null);
      async.elapse(const Duration(seconds: 1));
      expect(h.runs, 1, reason: 'второй догон не стартует поверх первого');
      h.gate!.complete();
      h.gate = null;
      async.elapse(const Duration(seconds: 1));
      expect(h.runs, 2, reason: 'сообщение могло прийти, пока шёл первый');
      h.driver.dispose();
    });
  });

  test('ошибка догона не роняет следующий', () {
    fakeAsync((async) {
      var runs = 0;
      final reconnected = StreamController<void>.broadcast();
      final driver = CatchUpDriver(
        catchUp: () async {
          runs++;
          throw Exception('сервер молчит');
        },
        reconnected: reconnected.stream,
        foreground: const Stream<bool>.empty(),
        subscribed: () => true,
        jitter: () => Duration.zero,
      );
      reconnected.add(null);
      async.elapse(const Duration(seconds: 1));
      reconnected.add(null);
      async.elapse(const Duration(seconds: 1));
      expect(runs, 2);
      driver.dispose();
    });
  });

  test('после dispose догонов нет', () {
    fakeAsync((async) {
      final h = _Harness(async)..subscribed = false;
      h.reconnected.add(null);
      h.driver.dispose();
      async.elapse(const Duration(minutes: 1));
      expect(h.runs, 0);
    });
  });
}
