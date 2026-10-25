import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Сокет нашего сервера, за которым следит маршрут (TOG-27).
///
/// Маршрут меняет путь только после настоящего ответа сервера через него
/// ([onAnswer]: пришли первые байты ответа), а не по открытому соединению. И
/// замечает путь «живой, но душат» ([onStall]): запрос ушёл, а за
/// [stallAfter] не сдвинулось ничего, ни отправка, ни ответ. Так Россия душит
/// соединения с заграничными серверами: мелкие запросы проходят, загрузки
/// висят до срока.
///
/// Отправка тела идёт через [Socket.addStream] с обратным давлением TCP:
/// очередной кусок сокет забирает, только когда сеть приняла прежние. Поэтому
/// медленная, но идущая загрузка зависанием не считается.
///
/// После ответа `101` (веб-сокет) наблюдение кончается: там тишина в обе
/// стороны и ответ на пинг без ответа — обычное дело. Зависшее скачивание
/// уже начатого ответа не замечается: где кончается ответ, знает только
/// разбор HTTP, а его здесь нет.
///
/// Обёртка повторяет `_DetachedSocket` из dart:_http: тем же приёмом сам
/// HttpClient отдаёт сокет веб-сокету. Закрытый член `Socket._detachRaw` нужен
/// только `SecureSocket.secure`, а оборачивается уже защищённый сокет.
Socket watchSocket(
  Socket inner, {
  Duration? stallAfter,
  void Function()? onAnswer,
  void Function()? onStall,
  DateTime Function()? now,
}) {
  final watch = SocketWatch(
    stallAfter: stallAfter,
    onAnswer: onAnswer,
    onStall: onStall,
    now: now ?? DateTime.now,
  );
  unawaited(inner.done.then((_) {}, onError: (_) {}).whenComplete(watch.close));
  return inner is SecureSocket
      ? _WatchedSecureSocket(inner, watch)
      : _WatchedSocket(inner, watch);
}

/// Что видно по байтам одного соединения: ответил ли сервер и не встал ли
/// запрос. Отдельно от сокета, чтобы правило проверялось без сети.
class SocketWatch {
  SocketWatch({
    this.stallAfter,
    this.onAnswer,
    this.onStall,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration? stallAfter;
  final void Function()? onAnswer;
  final void Function()? onStall;
  final DateTime Function() _now;

  bool _answered = false;
  bool _stalled = false;
  bool _upgraded = false;
  bool _closed = false;

  /// Запрос ушёл, ответа на него ещё не было.
  bool _awaiting = false;

  /// Начало ответа: первые байты после запроса.
  bool _responseStarts = true;
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  bool get answered => _answered;
  bool get stalled => _stalled;

  /// Клиент отдал байты в сеть.
  void outgoing() {
    if (_closed) return;
    _lastMove = _now();
    if (_upgraded) return;
    if (!_awaiting) {
      _awaiting = true;
      _responseStarts = true;
      _arm(stallAfter);
    }
  }

  /// Пришли байты от сервера.
  void incoming(List<int> data) {
    if (_closed || data.isEmpty) return;
    _lastMove = _now();
    if (_responseStarts) {
      _responseStarts = false;
      if (_isUpgrade(data)) {
        _upgraded = true;
        _timer?.cancel();
      }
    }
    _awaiting = false;
    if (_answered || _stalled) return;
    _answered = true;
    onAnswer?.call();
  }

  void close() {
    _closed = true;
    _timer?.cancel();
  }

  void _arm(Duration? after) {
    if (after == null || onStall == null) return;
    _timer?.cancel();
    _timer = Timer(after, _check);
  }

  void _check() {
    if (_closed || _upgraded || !_awaiting || _stalled) return;
    final limit = stallAfter!;
    final quiet = _now().difference(_lastMove);
    if (quiet < limit) {
      _arm(limit - quiet);
      return;
    }
    _stalled = true;
    onStall?.call();
  }

  static final RegExp _upgrade = RegExp(r'^HTTP/1\.[01] 101\b');

  /// `HTTP/1.1 101` — сервер переключил соединение на веб-сокет.
  static bool _isUpgrade(List<int> data) => _upgrade.hasMatch(
        latin1.decode(data.take(16).toList(), allowInvalid: true),
      );
}

class _WatchedSocket extends Stream<Uint8List> implements Socket {
  _WatchedSocket(this._inner, this._watch);

  final Socket _inner;
  final SocketWatch _watch;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _WatchedSubscription(_watch)
      .._onData = onData
      .._onDone = onDone;
    subscription._inner = _inner.listen(
      subscription._data,
      onError: onError,
      onDone: subscription._done,
      cancelOnError: cancelOnError,
    );
    return subscription;
  }

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void write(Object? object) {
    _watch.outgoing();
    _inner.write(object);
  }

  @override
  void writeln([Object? object = '']) {
    _watch.outgoing();
    _inner.writeln(object);
  }

  @override
  void writeCharCode(int charCode) {
    _watch.outgoing();
    _inner.writeCharCode(charCode);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _watch.outgoing();
    _inner.writeAll(objects, separator);
  }

  @override
  void add(List<int> data) {
    if (data.isNotEmpty) _watch.outgoing();
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  /// Кусок отмечается, когда сокет его забирает: при забитой сети сокет
  /// встаёт на паузу, и отметки прекращаются.
  @override
  Future addStream(Stream<List<int>> stream) {
    return _inner.addStream(stream.map((chunk) {
      if (chunk.isNotEmpty) _watch.outgoing();
      return chunk;
    }));
  }

  @override
  Future flush() => _inner.flush();

  @override
  Future close() => _inner.close();

  @override
  Future get done => _inner.done;

  @override
  void destroy() {
    _watch.close();
    _inner.destroy();
  }

  @override
  int get port => _inner.port;

  @override
  InternetAddress get address => _inner.address;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  int get remotePort => _inner.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}

class _WatchedSecureSocket extends _WatchedSocket implements SecureSocket {
  _WatchedSecureSocket(SecureSocket super.inner, super.watch);

  SecureSocket get _secure => _inner as SecureSocket;

  @override
  X509Certificate? get peerCertificate => _secure.peerCertificate;

  @override
  String? get selectedProtocol => _secure.selectedProtocol;

  /// В SDK этот метод ничего не делает и помечен устаревшим.
  @override
  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
  }) {}
}

/// Подписка на входящие байты. Обработчики можно сменить и после подписки
/// (так HttpClient передаёт сокет веб-сокету), а наблюдение остаётся.
class _WatchedSubscription implements StreamSubscription<Uint8List> {
  _WatchedSubscription(this._watch);

  final SocketWatch _watch;
  late final StreamSubscription<Uint8List> _inner;
  void Function(Uint8List data)? _onData;
  void Function()? _onDone;

  void _data(Uint8List data) {
    _watch.incoming(data);
    _onData?.call(data);
  }

  void _done() {
    _watch.close();
    _onDone?.call();
  }

  @override
  void onData(void Function(Uint8List data)? handleData) => _onData = handleData;

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _onDone = handleDone;

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<void> cancel() {
    _watch.close();
    return _inner.cancel();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    // Свой asFuture у внутренней подписки сменил бы её обработчики мимо
    // наблюдения, поэтому будущее собирается здесь.
    final result = Completer<E>();
    onDone(() => result.complete(futureValue as E));
    onError((Object error, StackTrace stack) {
      unawaited(cancel().whenComplete(() => result.completeError(error, stack)));
    });
    return result.future;
  }
}
