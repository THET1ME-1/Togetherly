import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'server_reach.dart';
import 'staggered_race.dart';
import 'watched_socket.dart';

/// Запасной путь к нашему серверу (22.10.2026).
///
/// Часть украинских провайдеров режет российские сети, и до togetherly.day
/// (Timeweb) у них не доходит ни один пакет. У сервера есть второй адрес —
/// IPv6 от Hurricane Electric, его Украина пропускает; имя у него
/// edge.togetherly.day. Ссылки в приложении остаются прежними, подменяется
/// только то, КУДА открывается соединение: шифрование и проверка сертификата
/// идут на настоящее имя (togetherly.day), поэтому подсунуть через запасной
/// путь чужой сервер нельзя. Новые адреса для запасного пути — записи DNS у
/// edge.togetherly.day, без сборки: соединение пробует все его адреса.
///
/// Порядок как у Happy Eyeballs: сначала основной путь, не ответил за
/// [stagger] — параллельно запасной, берётся первый ответивший. Сработал
/// запасной — запоминаем и дальше начинаем с него, а основной раз в
/// [recheckEvery] проверяем в фоне и возвращаемся, когда он ожил. Россияне
/// запасного не касаются: основной отвечает им сразу.
///
/// С 24.10.2026 обход ставится только телефонам из Украины и США
/// ([serverRouteWanted], решает [install]). В 1.39 он стоял у всех, и на
/// телефонах через него не поднималась мгновенная связь Centrifugo: пропуск
/// телефон получал, а до подписки на канал пары не доходил ни один. С ноутбука
/// тот же сокет через обход подключается, причину на телефоне не нашли.
///
/// Видео, голосовые и комната просмотра ходят мимо сетевого клиента Dart
/// (системный плеер, браузер) — им ссылку переписывает [forNative].
class ServerRoute {
  ServerRoute({
    Set<String> ourHosts = const {
      'togetherly.day',
      'togetherly.duckdns.org',
      'rt.togetherly.day',
      'bugsink.togetherly.day',
    },
    this.spareHost = 'edge.togetherly.day',
    String Function(String host)? directHostFor,
    this.stagger = const Duration(seconds: 6),
    this.recheckEvery = const Duration(minutes: 10),
    this.recheckTimeout = const Duration(seconds: 8),
    this.slowAfter = const Duration(seconds: 15),
    this.connectDeadline = const Duration(seconds: 20),
    this.stallAfter = const Duration(seconds: 20),
    Future<int> Function()? loadSpareSince,
    Future<void> Function(int value)? saveSpareSince,
    void Function()? onReached,
    void Function()? onMissed,
    DateTime Function()? now,
  })  : _ourHosts = ourHosts,
        _directHostFor = directHostFor ?? _same,
        _loadSpareSince = loadSpareSince ?? _loadFromPrefs,
        _saveSpareSince = saveSpareSince ?? _saveToPrefs,
        _onReached = onReached ?? _tellReached,
        _onMissed = onMissed ?? _tellMissed,
        _now = now ?? DateTime.now;

  /// Один на процесс (и на каждый фоновый движок: у них свои глобалы).
  static ServerRoute instance = ServerRoute();

  static const prefsKey = 'server_route_spare_since_ms';

  /// Имена, которые обслуживает наш сервер (Caddy держит их сертификаты на
  /// всех своих адресах, включая запасной).
  final Set<String> _ourHosts;

  /// Имя запасного адреса. Через него соединение открывается, а имя в
  /// шифровании остаётся настоящим.
  final String spareHost;

  final String Function(String host) _directHostFor;
  final Duration stagger;
  final Duration recheckEvery;
  final Duration recheckTimeout;

  /// Соединение, которое открывается дольше этого, — повод проверить сеть
  /// (TOG-16): у части провайдеров соединение с нашим сервером не рвётся, а
  /// молчит, и человек ждёт минутами.
  final Duration slowAfter;

  /// Не открылось за этот срок ни по одному пути — обрыв. Без него запрос к
  /// закрытому провайдером серверу висел, пока не сдастся система: на
  /// эмуляторе 2 минуты 15 секунд, у людей «бесконечная загрузка» (TOG-16).
  final Duration connectDeadline;

  /// Запрос ушёл, а за этот срок не сдвинулось ничего: ни отправка, ни ответ.
  final Duration stallAfter;
  final Future<int> Function() _loadSpareSince;
  final Future<void> Function(int value) _saveSpareSince;

  /// Куда сообщать об открытых и сорванных соединениях с нашим сервером: по
  /// ним [ServerReach] решает, советовать ли VPN.
  final void Function() _onReached;
  final void Function() _onMissed;
  final DateTime Function() _now;

  int _spareSince = 0;
  DateTime? _lastRecheck;
  bool _rechecking = false;

  /// Сейчас ходим запасным путём.
  bool get onSpare => _spareSince > 0;

  /// Поднимает запомненный путь. Звать до первого запроса.
  Future<void> load() async {
    try {
      _spareSince = await _loadSpareSince();
    } catch (_) {
      _spareSince = 0;
    }
  }

  /// Подключает запасной путь ко всем сетевым клиентам Dart этого движка.
  /// Звать первой строкой каждой точки входа: глобалы у движков свои.
  ///
  /// Ставится всем телефонам. Страну по телефону не угадать: украинец ходит
  /// с телефоном на московском времени, сеть Timeweb режут и в Европе (на
  /// 26.10.2026 через Contabo шли люди из Германии, Финляндии, Британии), а
  /// тем, кому прямой путь открыт, обход ничего не стоит: запасной путь
  /// пробуется, только когда основной молчит [stagger]. С 24 по 26.10.2026
  /// обход ставился только Украине и США, потому что через него не поднимался
  /// сокет Centrifugo (порт 0, см. [portOf]).
  static Future<void> install() async {
    await instance.load();
    HttpOverrides.global = ServerRouteOverrides();
  }

  /// Порт, куда открывать соединение. Порт 0 значит «по умолчанию», как его
  /// понимает сам HttpClient: веб-сокет dart:io присылает адрес именно с
  /// нулём. В 1.39 обход брал его буквально, и сокет Centrifugo не открывался
  /// ни у кого, кому обход включён.
  static int portOf(Uri uri) {
    if (uri.hasPort && uri.port != 0) return uri.port;
    return uri.isScheme('https') || uri.isScheme('wss') ? 443 : 80;
  }

  /// Фабрика соединений для [HttpClient.connectionFactory].
  ///
  /// Для https клиент сам шифрование не включает, раз фабрика задана, —
  /// возвращаем уже зашифрованный сокет. Через прокси отдаём голое соединение
  /// с прокси: туннель и шифрование клиент поднимает сам.
  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
    SecurityContext? context,
  ) {
    final secure = uri.isScheme('https') || uri.isScheme('wss');
    if (proxyHost != null) {
      return Socket.startConnect(proxyHost, proxyPort ?? 80);
    }
    final host = uri.host;
    final port = portOf(uri);
    if (!_ourHosts.contains(host.toLowerCase())) {
      return secure
          ? SecureSocket.startConnect(host, port, context: context)
          : Socket.startConnect(host, port);
    }

    _maybeRecheck(host, port, secure, context);
    final direct = _directHostFor(host);
    final targets = onSpare ? [spareHost, direct] : [direct, spareHost];
    final abort = Completer<void>();
    final slow = Timer(slowAfter, _onMissed);
    var timedOut = false;
    final deadline = Timer(connectDeadline, () {
      if (abort.isCompleted) return;
      timedOut = true;
      abort.complete();
    });
    final socket = staggeredRace<Socket>(
      [
        for (final target in targets)
          () => _dial(target, port, host, secure, context),
      ],
      stagger: stagger,
      discard: (late) => late.destroy(),
      abort: abort.future,
    ).then((win) {
      slow.cancel();
      deadline.cancel();
      _onReached();
      final viaSpare = targets[win.index] == spareHost;
      // Путь меняем, только если победил не тот, с которого начинали: значит,
      // начальный не ответил. Победа начального ни о чём не говорит, и без
      // этого запрос по запасному пути возвращал бы на запасной сразу после
      // того, как фоновая проверка вернула на основной. И меняем только после
      // настоящего ответа сервера через победителя (TOG-27): россиянина
      // открытое соединение уводило на запасной, а там мелкие запросы
      // проходят, а загрузки висят.
      final switches = win.index != 0;
      if (!switches && !viaSpare) return win.value;
      return watchSocket(
        win.value,
        stallAfter: viaSpare ? stallAfter : null,
        onAnswer: switches ? () => _remember(spare: viaSpare) : null,
        onStall: viaSpare ? () => _spareStalled(host) : null,
        now: _now,
      );
    }, onError: (Object error, StackTrace stack) {
      slow.cancel();
      deadline.cancel();
      if (timedOut) {
        _onMissed();
        throw SocketException(
          'нет соединения с $host за ${connectDeadline.inSeconds} с',
        );
      }
      // Соединение отменил сам клиент — о сервере это ничего не говорит.
      if (!abort.isCompleted) _onMissed();
      Error.throwWithStackTrace(error, stack);
    });
    return Future.value(ConnectionTask.fromSocket(socket, () {
      if (!abort.isCompleted) abort.complete();
    }));
  }

  /// Ссылка для системного плеера и браузера: они ходят мимо [connect], и на
  /// запасном пути им нужно настоящее имя запасного адреса. У edge свой
  /// сертификат и те же маршруты, что у togetherly.day.
  String forNative(String url) {
    if (!onSpare) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('wss'))) {
      return url;
    }
    final host = uri.host.toLowerCase();
    if (host != 'togetherly.day' && host != 'togetherly.duckdns.org') {
      return url;
    }
    return uri.replace(host: spareHost).toString();
  }

  /// Соединение через [connectHost] с шифрованием на имя [nameHost].
  RaceAttempt<Socket> _dial(
    String connectHost,
    int port,
    String nameHost,
    bool secure,
    SecurityContext? context,
  ) {
    ConnectionTask<Socket>? task;
    var cancelled = false;
    Future<Socket> open() async {
      task = await Socket.startConnect(connectHost, port);
      if (cancelled) {
        task!.cancel();
        throw const SocketException('соединение отменено');
      }
      final raw = await task!.socket;
      if (!secure) return raw;
      if (cancelled) {
        raw.destroy();
        throw const SocketException('соединение отменено');
      }
      return SecureSocket.secure(raw, host: nameHost, context: context);
    }

    return RaceAttempt(open(), () {
      cancelled = true;
      task?.cancel();
    });
  }

  void _remember({required bool spare}) {
    if (spare == onSpare) return;
    _spareSince = spare ? _now().millisecondsSinceEpoch : 0;
    if (spare) _lastRecheck = _now();
    debugPrint(spare
        ? 'ServerRoute: сервер ответил по запасному пути, дальше начинаем с него'
        : 'ServerRoute: возвращаемся на основной путь');
    unawaited(_saveSpareSince(_spareSince).catchError((_) {}));
  }

  /// Запрос по запасному пути ушёл, а за [stallAfter] не сдвинулось ничего:
  /// путь живой, но душат (TOG-27). Возвращаемся на основной, не дожидаясь
  /// проверки раз в [recheckEvery]. Сам запрос не рвём: его срок решает
  /// приложение, а сервер может просто долго думать.
  void _spareStalled(String host) {
    debugPrint('ServerRoute: запасной путь к $host завис');
    _remember(spare: false);
  }

  /// На запасном пути изредка проверяем основной: провайдер мог снять
  /// блокировку, человек мог уехать или включить VPN. Возвращаемся, только
  /// когда сервер по основному ответил на запрос (TOG-27): открытое соединение
  /// ещё ничего не значит.
  void _maybeRecheck(String host, int port, bool secure, SecurityContext? context) {
    if (!onSpare || _rechecking) return;
    final last = _lastRecheck;
    if (last != null && _now().difference(last) < recheckEvery) return;
    _rechecking = true;
    _lastRecheck = _now();
    final attempt = _dial(_directHostFor(host), port, host, secure, context);
    Socket? opened;
    final asked = attempt.result.then((socket) {
      opened = socket;
      return _askHealth(socket, host);
    });
    unawaited(asked.timeout(recheckTimeout, onTimeout: () {
      attempt.cancel();
      opened?.destroy();
      // Соединение могло достроиться уже после срока — закрываем и его.
      unawaited(attempt.result.then((late) => late.destroy()).catchError((_) {}));
      throw TimeoutException('основной путь молчит');
    }).then((_) {
      _remember(spare: false);
    }).catchError((_) {}).whenComplete(() => _rechecking = false));
  }

  /// Спрашивает сервер по уже открытому соединению и ждёт первых байт ответа,
  /// какой бы он ни был. Соединение после этого закрывается.
  static Future<void> _askHealth(Socket socket, String host) async {
    final answered = Completer<void>();
    final subscription = socket.listen(
      (_) {
        if (!answered.isCompleted) answered.complete();
      },
      onError: (Object error) {
        if (!answered.isCompleted) answered.completeError(error);
      },
      onDone: () {
        if (!answered.isCompleted) {
          answered.completeError(const SocketException('сервер закрыл соединение без ответа'));
        }
      },
      cancelOnError: true,
    );
    try {
      socket.add(ascii.encode(
        'GET /api/health HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
      ));
      await answered.future;
    } finally {
      unawaited(subscription.cancel());
      socket.destroy();
    }
  }

  static String _same(String host) => host;

  static void _tellReached() => ServerReach.instance.reached();

  static void _tellMissed() => ServerReach.instance.missed();

  static Future<int> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(prefsKey) ?? 0;
  }

  static Future<void> _saveToPrefs(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, value);
  }
}

/// Ставит фабрику [ServerRoute.connect] в каждый [HttpClient] движка: им
/// пользуются пакет http, PocketBase, кэш картинок, Image.network и веб-сокеты.
class ServerRouteOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) =>
        ServerRoute.instance.connect(uri, proxyHost, proxyPort, context);
    return client;
  }
}
