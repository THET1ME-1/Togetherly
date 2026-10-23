// Живая проверка обхода для Украины на настоящей сети, без телефона.
//
//   flutter test test/services/network/server_route_live_probe.dart
//
// Имя без `_test`: в общий прогон не входит, ходит на боевой сервер.
// У ноутбука нет IPv6, поэтому запасной путь изображает тот же сервер по
// IPv4, а основной адрес подменяется «чёрной дырой» (провайдер, который
// режет сервер, выглядит для приложения именно так: соединение молчит).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/server_route.dart';

Future<int> _health() async {
  final client = HttpClient();
  try {
    final req = await client
        .getUrl(Uri.parse('https://togetherly.day/api/health'))
        .timeout(const Duration(seconds: 30));
    final res = await req.close().timeout(const Duration(seconds: 30));
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<void> _socket() async {
  final ws = await WebSocket.connect('wss://togetherly.day/connection/websocket')
      .timeout(const Duration(seconds: 20));
  await ws.close();
}

void _install(ServerRoute route) {
  ServerRoute.instance = route;
  HttpOverrides.global = ServerRouteOverrides();
}

void main() {
  tearDown(() => HttpOverrides.global = null);

  test('основной путь: запрос и веб-сокет', () async {
    _install(ServerRoute(
      loadSpareSince: () async => 0,
      saveSpareSince: (_) async {},
    ));
    final watch = Stopwatch()..start();
    expect(await _health(), 200);
    print('запрос: ${watch.elapsedMilliseconds} мс');
    watch.reset();
    await _socket();
    print('веб-сокет: ${watch.elapsedMilliseconds} мс');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('основной заблокирован: запрос и веб-сокет уходят на запасной', () async {
    final route = ServerRoute(
      directHostFor: (_) => '10.255.255.1',
      spareHost: '86.110.220.22',
      loadSpareSince: () async => 0,
      saveSpareSince: (_) async {},
    );
    _install(route);
    final watch = Stopwatch()..start();
    expect(await _health(), 200);
    print('запрос через запасной: ${watch.elapsedMilliseconds} мс, onSpare=${route.onSpare}');
    expect(route.onSpare, isTrue);
    watch.reset();
    await _socket();
    print('веб-сокет через запасной: ${watch.elapsedMilliseconds} мс');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
