import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Живой фон карточки «Я скучаю» — поле мелких сердечек (макет «Фон сердца
/// «Скучаю»», вариант Б, выбран 28.09.2026).
///
/// В покое сердечки чуть покачиваются. Нажатие на большое сердце ([pulse])
/// пускает по узору волну от центра к краям: сердечки вспыхивают и
/// подпрыгивают.
///
/// Спам нажатиями продуман так:
///   * одна «энергия» вместо очереди анимаций — каждое нажатие прибавляет к
///     ней, она ограничена единицей и остывает вдвое за 0,7 с; узор ярче от
///     энергии, но не больше предела;
///   * волн одновременно не больше [maxWaves], старые уступают новым, каждая
///     живёт [waveLife];
///   * в покое кадр перерисовывается не чаще 20 раз в секунду — фон не ест
///     батарею, пока на экран просто смотрят; скрытый экран тикер глушит сам
///     (`TickerMode`);
///   * «уменьшить движение» в системе — без покачивания и волн, только
///     вспышка яркости.
class HeartField extends StatefulWidget {
  const HeartField({super.key, required this.color, required this.center});

  /// Цвет сердечек — заливка темы.
  final Color color;

  /// Центр волны в долях карточки (там большое сердце).
  final Offset Function(Size size) center;

  static const int maxWaves = 5;
  static const Duration waveLife = Duration(milliseconds: 1500);

  @override
  State<HeartField> createState() => HeartFieldState();
}

class HeartFieldState extends State<HeartField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);

  /// Время с запуска тикера, секунды — часы покачивания и волн.
  double _t = 0;
  double _energy = 0;
  final List<double> _waves = [];
  Duration _last = Duration.zero;
  double _lastPaint = -1;

  @visibleForTesting
  int get debugWaves => _waves.length;
  @visibleForTesting
  double get debugEnergy => _energy;
  @visibleForTesting
  bool get debugTicking => _ticker.isActive;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// Нажатие на большое сердце.
  void pulse() {
    if (!_ticker.isActive) {
      // Тикер спал (только при «уменьшить движение»): его часы начнутся с нуля.
      _ticker.start();
      _t = 0;
      _last = Duration.zero;
    }
    _energy = math.min(1, _energy + 0.28);
    if (!_still) {
      _waves.add(_t);
      if (_waves.length > HeartField.maxWaves) _waves.removeAt(0);
    }
    _repaint.value++;
  }

  void _tick(Duration elapsed) {
    // Остывание — по настоящему времени: на медленных кадрах (слабый
    // телефон, возврат с фона) энергия иначе висела бы секундами.
    final dt = math.max(0.0, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _t = elapsed.inMicroseconds / 1e6;
    _energy *= math.pow(0.5, dt / 0.7);
    final life = HeartField.waveLife.inMicroseconds / 1e6;
    _waves.removeWhere((w) => _t - w > life);
    final busy = _energy > 0.01 || _waves.isNotEmpty;
    if (_still && !busy) {
      // Двигаться нечему: тикер спит до следующего нажатия.
      _ticker.stop();
      _last = Duration.zero;
      _repaint.value++;
      return;
    }
    if (!busy && _t - _lastPaint < 0.05) return;
    _lastPaint = _t;
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HeartFieldPainter(
          repaint: _repaint,
          state: this,
          color: widget.color,
          still: _still,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HeartFieldPainter extends CustomPainter {
  _HeartFieldPainter({required Listenable repaint, required this.state, required this.color, required this.still})
      : super(repaint: repaint);

  final HeartFieldState state;
  final Color color;
  final bool still;

  static const double step = 30;

  /// Сердечко высотой 1 с вершиной выемки в (0, 0.35) — те же кривые, что на
  /// макете.
  static final Path _unit = () {
    return Path()
      ..moveTo(0, 0.35)
      ..cubicTo(0, 0, -0.5, 0, -0.5, 0.35)
      ..cubicTo(-0.5, 0.65, 0, 0.8, 0, 1)
      ..cubicTo(0, 0.8, 0.5, 0.65, 0.5, 0.35)
      ..cubicTo(0.5, 0, 0, 0, 0, 0.35)
      ..close();
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = state._t;
    final c = state.widget.center(size);
    final energy = state._energy;
    final paint = Paint()..style = PaintingStyle.fill;
    var row = 0;
    for (var y = step / 2; y < size.height + step; y += step, row++) {
      for (var x = row.isOdd ? step / 2 : 0.0; x < size.width + step; x += step) {
        final d = (Offset(x, y) - c).distance;
        var wave = 0.0;
        for (final w in state._waves) {
          final age = t - w;
          final k = (d - age * 420) / 38;
          wave += math.exp(-k * k) * math.max(0, 1 - age / 1.4);
        }
        wave = math.min(1.4, wave);
        final sway = still ? 0.0 : math.sin(t * 0.9 + x * 0.05 + y * 0.07) * 0.12;
        final s = 8 * (1 + 0.9 * wave);
        final a = (0.10 + 0.10 * energy + 0.45 * math.min(1, wave)).clamp(0.0, 1.0);
        paint.color = color.withValues(alpha: a);
        canvas
          ..save()
          ..translate(x, y - wave * 6)
          ..rotate(sway)
          ..translate(0, -s / 2)
          ..scale(s)
          ..drawPath(_unit, paint)
          ..restore();
      }
    }
  }

  @override
  bool shouldRepaint(_HeartFieldPainter old) => old.color != color || old.still != still;
}
