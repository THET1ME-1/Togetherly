// TOG-16: отзыв из США (18.10.2026) и семь обращений за ночь на 23.10 из
// Украины. Интернет у людей работал, а приложение писало «проверьте интернет»,
// «некорректный email» или крутило загрузку: провайдер не пускает к нашему
// серверу. Служба отличает этот случай от настоящего отсутствия сети, чтобы
// экран мог прямо сказать, что поможет VPN.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/server_reach.dart';

class _Probes {
  _Probes({DateTime Function()? now}) {
    reach = ServerReach(
      probeOurs: () async {
        oursCalls++;
        final g = gate;
        if (g != null) await g.future;
        return ours;
      },
      probeInternet: () async {
        internetCalls++;
        return internet;
      },
      now: now,
    );
  }

  bool ours = false;
  bool internet = true;
  int oursCalls = 0;
  int internetCalls = 0;
  Completer<void>? gate;
  late final ServerReach reach;
}

void main() {
  test('свой сервер отвечает — значит, он не закрыт', () async {
    final p = _Probes()..ours = true;
    expect(await p.reach.check(), ServerReachState.ok);
    expect(p.reach.state.value, ServerReachState.ok);
  });

  test('свой сервер молчит, а интернет есть — сервер закрыт в этой сети', () async {
    final p = _Probes();
    expect(await p.reach.check(), ServerReachState.blocked);
    expect(p.reach.state.value, ServerReachState.blocked);
  });

  test('не отвечает никто — интернета нет', () async {
    final p = _Probes()..internet = false;
    expect(await p.reach.check(), ServerReachState.offline);
  });

  test('соединение с сервером открылось — закрытость снимается сразу', () async {
    final p = _Probes();
    await p.reach.check();
    p.reach.reached();
    expect(p.reach.state.value, ServerReachState.ok);
  });

  test('проверки внахлёст идут одним походом', () async {
    final p = _Probes()..gate = Completer<void>();
    final first = p.reach.check();
    final second = p.reach.check();
    p.gate!.complete();
    expect(await first, ServerReachState.blocked);
    expect(await second, ServerReachState.blocked);
    expect(p.oursCalls, 1);
    expect(p.internetCalls, 1);
  });

  test('обрыв соединения проверяет сеть, но не чаще раза в минуту', () {
    fakeAsync((async) {
      final p = _Probes(now: async.getClock(DateTime(2026, 10, 23)).now);
      p.reach.missed();
      async.flushMicrotasks();
      expect(p.oursCalls, 1);
      expect(p.reach.state.value, ServerReachState.blocked);

      async.elapse(const Duration(seconds: 30));
      p.reach.missed();
      async.flushMicrotasks();
      expect(p.oursCalls, 1, reason: 'полминуты назад уже проверяли');

      async.elapse(const Duration(seconds: 31));
      p.reach.missed();
      async.flushMicrotasks();
      expect(p.oursCalls, 2);
    });
  });

  test('проверка, которую попросил экран, идёт и сразу после обрыва', () {
    fakeAsync((async) {
      final p = _Probes(now: async.getClock(DateTime(2026, 10, 23)).now);
      p.reach.missed();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      p.ours = true;
      ServerReachState? answer;
      p.reach.check().then((value) => answer = value);
      async.flushMicrotasks();
      expect(p.oursCalls, 2, reason: 'человек ждёт ответа сейчас');
      expect(answer, ServerReachState.ok);
    });
  });

  test('упавшая проверка считается молчанием, а не ломает службу', () async {
    final reach = ServerReach(
      probeOurs: () async => throw StateError('сокет закрыт'),
      probeInternet: () async => true,
    );
    expect(await reach.check(), ServerReachState.blocked);
  });
}
