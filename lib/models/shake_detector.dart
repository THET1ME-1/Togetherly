import 'dart:math' as math;

/// Узнаёт встряску телефона по ускорению без силы тяжести (м/с²).
///
/// Встряска — [hits] резких рывков (сильнее [threshold]) за [window]. Один
/// удар о стол, шаги и транспорт под это не попадают. После встряски
/// [cooldown] тишины: человек трясёт телефон секунду, а облачко должно
/// испугаться один раз.
class ShakeDetector {
  ShakeDetector({
    this.threshold = 18,
    this.hits = 3,
    this.window = const Duration(milliseconds: 800),
    this.cooldown = const Duration(seconds: 2),
  });

  final double threshold;
  final int hits;
  final Duration window;
  final Duration cooldown;

  final List<Duration> _peaks = [];
  Duration? _firedAt;

  /// Новое показание датчика в момент [at]. true — это встряска.
  bool add(Duration at, double x, double y, double z) {
    final fired = _firedAt;
    if (fired != null && at - fired < cooldown) return false;
    if (math.sqrt(x * x + y * y + z * z) < threshold) return false;
    _peaks.add(at);
    _peaks.removeWhere((t) => at - t > window);
    if (_peaks.length < hits) return false;
    _peaks.clear();
    _firedAt = at;
    return true;
  }
}
