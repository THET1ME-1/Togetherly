import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/server_route.dart';

/// Настоящие сокеты на петле. «Наш сервер» — TLS на 127.0.0.1 с сертификатом
/// на togetherly.test, а путь, который режут, — 127.0.0.2: соединение он
/// принимает и молчит, как молчит сеть Timeweb у части украинских провайдеров.
void main() {
  final cert = File('test/fixtures/network/server_cert.pem').readAsBytesSync();
  final key = File('test/fixtures/network/server_key.pem').readAsBytesSync();
  late SecureServerSocket server;
  late ServerSocket silent;
  late int port;
  final held = <Socket>[];

  setUpAll(() async {
    final serverContext = SecurityContext()
      ..useCertificateChainBytes(cert)
      ..usePrivateKeyBytes(key);
    server = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, serverContext);
    port = server.port;
    server.listen(
      (socket) {
        socket.listen(
          (_) {
            socket.write('HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok');
            socket.close();
          },
          onError: (_) {},
        );
      },
      onError: (_) {},
    );
    silent = await ServerSocket.bind('127.0.0.2', port);
    silent.listen(held.add);
  });

  tearDownAll(() async {
    for (final socket in held) {
      socket.destroy();
    }
    await silent.close();
    await server.close();
  });

  ServerRoute route({
    required String direct,
    String spare = '127.0.0.1',
    int spareSince = 0,
    Duration recheckEvery = const Duration(minutes: 10),
    Duration slowAfter = const Duration(seconds: 15),
    Duration connectDeadline = const Duration(seconds: 20),
    List<int>? saved,
    List<String>? reach,
  }) {
    return ServerRoute(
      ourHosts: const {'togetherly.test'},
      spareHost: spare,
      directHostFor: (_) => direct,
      stagger: const Duration(milliseconds: 300),
      recheckEvery: recheckEvery,
      slowAfter: slowAfter,
      connectDeadline: connectDeadline,
      loadSpareSince: () async => spareSince,
      saveSpareSince: (value) async => saved?.add(value),
      onReached: () => reach?.add('доступен'),
      onMissed: () => reach?.add('обрыв'),
    );
  }

  Future<String> fetch(ServerRoute route, String host, {bool trust = true}) async {
    final context = SecurityContext(withTrustedRoots: false);
    if (trust) context.setTrustedCertificatesBytes(cert);
    final client = HttpClient(context: context)
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          route.connect(uri, proxyHost, proxyPort, context);
    try {
      final request = await client.getUrl(Uri.parse('https://$host:$port/api/health'));
      final response = await request.close();
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  test('основной путь отвечает — запасной не нужен и не запоминается', () async {
    final saved = <int>[];
    final r = route(direct: '127.0.0.1', saved: saved);
    await r.load();
    expect(await fetch(r, 'togetherly.test'), 'ok');
    expect(r.onSpare, isFalse);
    expect(saved, isEmpty);
  });

  test('основной молчит — через нахлёст соединение уходит на запасной, и это запоминается',
      () async {
    final saved = <int>[];
    final r = route(direct: '127.0.0.2', saved: saved);
    await r.load();
    final watch = Stopwatch()..start();
    expect(await fetch(r, 'togetherly.test'), 'ok');
    expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
    expect(r.onSpare, isTrue);
    expect(saved, hasLength(1));
    expect(saved.single, greaterThan(0));
  });

  test('основной не находится вовсе — запасной пробуется сразу, без нахлёста', () async {
    final r = route(direct: 'no-such-host.invalid');
    await r.load();
    expect(await fetch(r, 'togetherly.test'), 'ok');
    expect(r.onSpare, isTrue);
  });

  test('запомненный запасной — сразу с него, основной не ждём', () async {
    final r = route(direct: '127.0.0.2', spareSince: 1);
    await r.load();
    expect(r.onSpare, isTrue);
    final watch = Stopwatch()..start();
    expect(await fetch(r, 'togetherly.test'), 'ok');
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 300)));
  });

  test('на запасном фоновая проверка возвращает на основной, когда тот ожил', () async {
    final saved = <int>[];
    final r = route(
      direct: '127.0.0.1',
      spareSince: 1,
      recheckEvery: Duration.zero,
      saved: saved,
    );
    await r.load();
    expect(await fetch(r, 'togetherly.test'), 'ok');
    for (var i = 0; i < 50 && r.onSpare; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(r.onSpare, isFalse);
    expect(saved.last, 0);
  });

  test('на запасном пути сертификат сверяется с настоящим именем: чужой не пропускается',
      () async {
    // Запасной первым, основной не находится: ошибка гонки — ошибка запасного.
    final r = route(direct: 'no-such-host.invalid', spareSince: 1);
    await r.load();
    await expectLater(
      fetch(r, 'togetherly.test', trust: false),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('запрос, открывшийся по запасному, не возвращает на запасной после фоновой проверки',
      () async {
    final saved = <int>[];
    final r = route(
      direct: '127.0.0.1',
      spareSince: 1,
      recheckEvery: Duration.zero,
      saved: saved,
    );
    await r.load();
    for (var i = 0; i < 5; i++) {
      expect(await fetch(r, 'togetherly.test'), 'ok');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(r.onSpare, isFalse);
    expect(saved.where((value) => value > 0), isEmpty);
  });

  test('чужие адреса идут как обычно, мимо запасного пути', () async {
    final r = route(direct: 'no-such-host.invalid');
    await r.load();
    expect(await fetch(r, 'localhost'), 'ok');
    expect(r.onSpare, isFalse);
  });

  // TOG-16: по этим сигналам ServerReach решает, показывать ли совет про VPN.
  group('связь с сервером для подсказки про VPN', () {
    test('открытое соединение сообщает, что сервер доступен', () async {
      final reach = <String>[];
      final r = route(direct: '127.0.0.1', reach: reach);
      await r.load();
      expect(await fetch(r, 'togetherly.test'), 'ok');
      expect(reach, ['доступен']);
    });

    test('не открылся ни основной, ни запасной путь — сообщает обрыв', () async {
      final reach = <String>[];
      final r = route(
        direct: 'no-such-host.invalid',
        spare: 'no-such-spare.invalid',
        reach: reach,
      );
      await r.load();
      await expectLater(fetch(r, 'togetherly.test'), throwsA(anything));
      expect(reach, ['обрыв']);
    });

    test('затянувшееся соединение сообщает обрыв, но не рвёт его', () async {
      final reach = <String>[];
      final r = route(
        direct: '127.0.0.2',
        slowAfter: const Duration(milliseconds: 100),
        reach: reach,
      );
      await r.load();
      expect(await fetch(r, 'togetherly.test'), 'ok');
      expect(reach, ['обрыв', 'доступен']);
    });

    // На эмуляторе с закрытым адресом сервера запросы висели по 2 минуты 15
    // секунд, пока не сдавалась система: та самая «бесконечная загрузка».
    test('соединение, не открывшееся за отведённый срок, обрывается само',
        () async {
      final reach = <String>[];
      final r = route(
        direct: '127.0.0.2',
        spare: 'no-such-spare.invalid',
        connectDeadline: const Duration(milliseconds: 600),
        reach: reach,
      );
      await r.load();
      final watch = Stopwatch()..start();
      await expectLater(fetch(r, 'togetherly.test'), throwsA(anything));
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(reach, contains('обрыв'));
    });

    test('чужие адреса о нашем сервере ничего не говорят', () async {
      final reach = <String>[];
      final r = route(direct: '127.0.0.1', reach: reach);
      await r.load();
      expect(await fetch(r, 'localhost'), 'ok');
      expect(reach, isEmpty);
    });
  });

  group('ссылки для системного плеера и браузера', () {
    ServerRoute production(int spareSince) => ServerRoute(
          loadSpareSince: () async => spareSince,
          saveSpareSince: (_) async {},
        );

    test('на основном пути ссылка не меняется', () async {
      final r = production(0);
      await r.load();
      const url = 'https://togetherly.day/api/files/media/abc/v.mp4?token=t';
      expect(r.forNative(url), url);
    });

    test('на запасном наш адрес меняется на edge, путь и токен остаются', () async {
      final r = production(1);
      await r.load();
      expect(
        r.forNative('https://togetherly.day/api/files/media/abc/v.mp4?token=t'),
        'https://edge.togetherly.day/api/files/media/abc/v.mp4?token=t',
      );
      expect(
        r.forNative('https://togetherly.duckdns.org/watch/room/?src=x'),
        'https://edge.togetherly.day/watch/room/?src=x',
      );
    });

    test('чужие ссылки и не https не трогаются', () async {
      final r = production(1);
      await r.load();
      const youtube = 'https://www.youtube.com/watch?v=1';
      const local = 'file:///data/v.mp4';
      expect(r.forNative(youtube), youtube);
      expect(r.forNative(local), local);
    });
  });
}
