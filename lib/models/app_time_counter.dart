/// Счёт времени на экране для званий за часы, без таймеров и сети: их держит
/// `AppTimeService`, сюда приходят только события с отметкой времени.
///
/// Время идёт, пока приложение на экране, и не дольше [idle] после последнего
/// касания: забытый открытый телефон не должен набирать звания. Открытие
/// приложения считается касанием. Копится в миллисекундах, чтобы частые тики
/// не теряли доли секунд.
class AppTimeCounter {
  AppTimeCounter({this.idle = const Duration(minutes: 10)});

  final Duration idle;

  bool _onScreen = false;
  DateTime? _from;
  DateTime? _touch;
  int _pendingMs = 0;

  /// Насчитано и ещё не отправлено на сервер.
  int get pendingSeconds => _pendingMs ~/ 1000;

  /// Поднять несданное после перезапуска приложения.
  void restore(int seconds) => _pendingMs += seconds * 1000;

  void screen(bool on, DateTime now) {
    _settle(now);
    _onScreen = on;
    if (on) _touch = now;
  }

  void touch(DateTime now) {
    _settle(now);
    _touch = now;
  }

  void tick(DateTime now) => _settle(now);

  /// Сервер принял [seconds] — вычитаем, остаток копится дальше.
  void sent(int seconds) {
    _pendingMs -= seconds * 1000;
    if (_pendingMs < 0) _pendingMs = 0;
  }

  void _settle(DateTime now) {
    final from = _from;
    _from = now;
    final touch = _touch;
    if (!_onScreen || from == null || touch == null) return;
    final limit = touch.add(idle);
    final end = now.isBefore(limit) ? now : limit;
    if (end.isAfter(from)) _pendingMs += end.difference(from).inMilliseconds;
  }
}
