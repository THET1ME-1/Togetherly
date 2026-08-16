import 'dart:async';

/// Откладывает запись холста на диск.
///
/// Экран рисования сохранял весь рисунок на КАЖДЫЙ штрих: `jsonEncode` всех
/// штрихов со всеми точками плюс запись в SharedPreferences. В обычной
/// раскраске штрих — это целый мазок, и цена терялась в шуме. В пиксельном
/// режиме штрих — одна клетка: закрашивая фон, человек делает их сотнями, и
/// сотая клетка сериализует сто штрихов, трёхсотая — триста. Работа растёт
/// квадратично, кадры пропускаются, палец «уезжает» с холста. Отсюда жалоба
/// «лагает очень, когда рисуешь по клеточкам, всё стирает, холст дрожит»
/// (письмо с 1.28.0, 16 августа 2026).
///
/// Здесь запись откладывается на [interval] и склеивается: сколько бы правок
/// ни пришло за это время, на диск уйдёт одна. Уход с экрана и сворачивание
/// приложения зовут [flushNow] — нарисованное не теряется.
class StrokeSaveScheduler {
  StrokeSaveScheduler({
    required Future<void> Function() save,
    this.interval = const Duration(milliseconds: 600),
  }) : _save = save;

  final Future<void> Function() _save;
  final Duration interval;

  Timer? _timer;
  bool _dirty = false;
  bool _running = false;
  bool _disposed = false;

  /// Холст изменился. Запись произойдёт не раньше, чем через [interval].
  void schedule() {
    if (_disposed) return;
    _dirty = true;
    _timer ??= Timer(interval, _run);
  }

  /// Записать немедленно, если есть что писать: выход с экрана, сворачивание.
  void flushNow() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    unawaited(_run());
  }

  /// Последняя правка всё равно доезжает на диск: терять штрих из-за закрытия
  /// экрана нельзя.
  void dispose() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _disposed = true;
    if (_dirty) unawaited(_run());
  }

  Future<void> _run() async {
    _timer = null;
    // Две записи разом затирают друг друга: пишем по очереди, а правки,
    // пришедшие во время записи, уедут следующим кругом.
    if (_running) {
      _rearm();
      return;
    }
    if (!_dirty) return;
    _dirty = false;
    _running = true;
    try {
      await _save();
    } finally {
      _running = false;
      if (_dirty) _rearm();
    }
  }

  void _rearm() {
    if (_disposed) {
      unawaited(_run());
      return;
    }
    _timer ??= Timer(interval, _run);
  }
}
