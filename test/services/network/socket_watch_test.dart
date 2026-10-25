// TOG-27: по чему маршрут решает, ответил ли сервер через путь и не душат ли
// его. Правило без сети: байты туда и обратно подаются руками, часы
// поддельные.
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/watched_socket.dart';

void main() {
  const stall = Duration(seconds: 20);
  final ok = ascii.encode('HTTP/1.1 200 OK\r\n');

  SocketWatch watch(FakeAsync async, List<String> log, {bool stalls = true}) =>
      SocketWatch(
        stallAfter: stall,
        onAnswer: () => log.add('ответ'),
        onStall: stalls ? () => log.add('завис') : null,
        now: () => async.getClock(DateTime(2026, 10, 25)).now(),
      );

  test('первые байты ответа — это ответ, и он один на соединение', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      w.incoming(ok);
      w.outgoing();
      w.incoming(ok);
      expect(log, ['ответ']);
    });
  });

  test('запрос ушёл, и двадцать секунд не движется ничего — завис', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      async.elapse(const Duration(seconds: 19));
      expect(log, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(log, ['завис']);
    });
  });

  test('отправка идёт — не завис, сколько бы ни молчал сервер', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      for (var i = 0; i < 12; i++) {
        async.elapse(const Duration(seconds: 15));
        w.outgoing();
      }
      expect(log, isEmpty, reason: 'три минуты загрузки приняли за удушение');
      async.elapse(const Duration(seconds: 21));
      expect(log, ['завис'], reason: 'отправка встала, а зависание не заметили');
    });
  });

  test('ответ пришёл — ждать больше нечего, тишина после него не зависание', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      async.elapse(const Duration(seconds: 5));
      w.incoming(ok);
      async.elapse(const Duration(minutes: 2));
      expect(log, ['ответ']);
    });
  });

  test('завис и потом ответил — поздний ответ путь не меняет', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      async.elapse(const Duration(seconds: 21));
      w.incoming(ok);
      expect(log, ['завис']);
    });
  });

  test('следующий запрос по тому же соединению ждёт ответа заново', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      w.incoming(ok);
      async.elapse(const Duration(seconds: 30));
      w.outgoing();
      async.elapse(const Duration(seconds: 21));
      expect(log, ['ответ', 'завис']);
    });
  });

  test('веб-сокет: после 101 запись без ответа и тишина — не зависание', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      w.incoming(ascii.encode('HTTP/1.1 101 Switching Protocols\r\n'));
      // Ответ на пинг сервера: отвечать на него серверу нечего.
      w.outgoing();
      async.elapse(const Duration(minutes: 2));
      expect(log, ['ответ']);
    });
  });

  test('100 Continue — ещё не конец: ждём настоящего ответа на тело', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      w.incoming(ascii.encode('HTTP/1.1 100 Continue\r\n\r\n'));
      w.outgoing();
      async.elapse(const Duration(seconds: 21));
      expect(log, ['ответ', 'завис']);
    });
  });

  test('закрытое соединение не зависает', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log);
      w.outgoing();
      w.close();
      async.elapse(const Duration(minutes: 1));
      expect(log, isEmpty);
    });
  });

  test('основному пути зависание не считают: таймеров нет вовсе', () {
    fakeAsync((async) {
      final log = <String>[];
      final w = watch(async, log, stalls: false);
      w.outgoing();
      expect(async.pendingTimers, isEmpty);
      w.incoming(ok);
      expect(log, ['ответ']);
    });
  });
}
