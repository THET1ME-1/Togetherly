import 'dart:async';
import 'dart:math';

/// Открытый список дотягивает с сервера то, что прошло мимо сокета (TOG-17).
///
/// О новых сообщениях чат узнаёт из сокета Centrifugo, а сокет рвётся всё
/// время: мобильная сеть, сон телефона, MIUI. События, случившиеся в разрыв,
/// не досылаются никогда, и сообщение партнёра появлялось только после выхода
/// из чата и повторного входа («при входе в чат их некоторое время не видно»,
/// отзыв в Google Play, 1.38.0).
///
/// Поводов дотянуть три:
///  * сокет переподключился — с разбросом [jitter], чтобы после перезапуска
///    сервера все открытые чаты не пришли за списком одной секундой;
///  * приложение вернулось на экран после паузы дольше [minAway];
///  * сокета нет, а список открыт и приложение на экране — раз в [pollEvery],
///    пока сокет не оживёт.
///
/// Догоны не идут вперехлёст: повод, случившийся во время догона, даёт ещё
/// один догон после него — сообщение могло прийти, пока шёл запрос.
class CatchUpDriver {
  CatchUpDriver({
    required Future<void> Function() catchUp,
    required Stream<void> reconnected,
    required Stream<bool> foreground,
    required bool Function() subscribed,
    Duration pollEvery = const Duration(seconds: 15),
    Duration minAway = const Duration(seconds: 3),
    Duration Function()? jitter,
    DateTime Function()? now,
  })  : _catchUp = catchUp,
        _subscribed = subscribed,
        _minAway = minAway,
        _jitter = jitter ?? _randomJitter,
        _now = now ?? DateTime.now {
    _subs.add(reconnected.listen((_) => _schedule(_jitter())));
    _subs.add(foreground.listen(_onForeground));
    _poll = Timer.periodic(pollEvery, (_) {
      if (_inForeground && !_subscribed()) _request();
    });
  }

  final Future<void> Function() _catchUp;
  final bool Function() _subscribed;
  final Duration _minAway;
  final Duration Function() _jitter;
  final DateTime Function() _now;

  final List<StreamSubscription<Object?>> _subs = [];
  final List<Timer> _delays = [];
  Timer? _poll;
  bool _inForeground = true;
  DateTime? _awayAt;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  static final Random _rnd = Random();
  static Duration _randomJitter() =>
      Duration(milliseconds: 300 + _rnd.nextInt(1200));

  void _onForeground(bool visible) {
    if (!visible) {
      _inForeground = false;
      _awayAt ??= _now();
      return;
    }
    _inForeground = true;
    final away = _awayAt;
    _awayAt = null;
    if (away != null && _now().difference(away) >= _minAway) _request();
  }

  void _schedule(Duration delay) {
    if (_disposed) return;
    if (delay <= Duration.zero) {
      _request();
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _delays.remove(timer);
      _request();
    });
    _delays.add(timer);
  }

  void _request() {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    try {
      do {
        _again = false;
        try {
          await _catchUp();
        } catch (_) {
          // Сеть или сервер не ответили — следующий повод попробует снова.
        }
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    for (final t in _delays) {
      t.cancel();
    }
    _delays.clear();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }
}
