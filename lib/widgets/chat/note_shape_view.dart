import 'package:flutter/material.dart';

import 'note_shapes.dart';

/// Содержимое, обрезанное формой фигурки, и обод по её контуру.
///
/// Один виджет на все три места, где фигурка появляется: превью камеры при
/// съёмке, пузырь в ленте, полный экран. Из-за этого форма, обод и центровка
/// кадра везде считаются одинаково — разойтись им негде.
///
/// Смена формы — морф: радиусы профиля переезжают из одной формы в другую за
/// [morphDuration]. Кадр при этом не прерывается, потому что меняется только
/// маска.
class NoteShapeView extends StatefulWidget {
  final NoteShape shape;

  /// Сторона квадрата, в который вписана форма.
  final double size;

  /// Что показывать внутри: кадр, превью камеры, обложка.
  final Widget child;

  /// Доля обода 0..1. Игнорируется, если задан [ringListenable].
  final double ringProgress;

  /// Живой обод: значение берётся из [ringValue] на каждый тик слушателя, а
  /// перерисовывается ТОЛЬКО обод — содержимое и маска не трогаются.
  final Listenable? ringListenable;
  final double Function()? ringValue;

  final Color ringColor;

  /// Дорожка под ободом. null — обода-дорожки нет (в ленте она лишняя).
  final Color? trackColor;

  final double ringWidth;

  /// Пауза морфа. Ноль — форма меняется мгновенно (первая отрисовка).
  final Duration morphDuration;

  const NoteShapeView({
    super.key,
    required this.shape,
    required this.size,
    required this.child,
    this.ringProgress = 0,
    this.ringListenable,
    this.ringValue,
    this.ringColor = const Color(0xFFFFFFFF),
    this.trackColor,
    this.ringWidth = 4,
    this.morphDuration = const Duration(milliseconds: 340),
  });

  @override
  State<NoteShapeView> createState() => _NoteShapeViewState();
}

class _NoteShapeViewState extends State<NoteShapeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: widget.morphDuration,
    value: 1,
  );
  late NoteShape _from = widget.shape;
  late NoteShape _to = widget.shape;

  @override
  void didUpdateWidget(covariant NoteShapeView old) {
    super.didUpdateWidget(old);
    if (old.shape.id != widget.shape.id) {
      // Морф начинаем с того, что человек видит сейчас: если предыдущий не
      // доиграл, форма не прыгнет к началу.
      _from = _currentShape();
      _to = widget.shape;
      _morph
        ..duration = widget.morphDuration
        ..value = 0
        ..animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  NoteShape _currentShape() {
    if (_morph.value >= 1) return _to;
    final t = Curves.easeOutCubic.transform(_morph.value);
    return NoteShape(
      id: _to.id,
      profile: lerpNoteProfile(_from.profile, _to.profile, t),
      safeRadius: _from.safeRadius + (_to.safeRadius - _from.safeRadius) * t,
      centerX: _from.centerX + (_to.centerX - _from.centerX) * t,
      centerY: _from.centerY + (_to.centerY - _from.centerY) * t,
    );
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _morph,
        builder: (context, _) {
          final shape = _currentShape();
          // Кадр прижимается к центру безопасной зоны, а не к середине рамки:
          // у сердца широкая часть ниже, и лицо иначе уезжает в вырез.
          final side = s * 1.12;
          final left = s * shape.centerX - side / 2;
          final top = s * shape.centerY - side / 2;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipPath(
                clipper: NoteShapeClipper(
                  profile: shape.profile,
                  centerX: shape.centerX,
                  centerY: shape.centerY,
                ),
                child: SizedBox(
                  width: s,
                  height: s,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: left,
                        top: top,
                        width: side,
                        height: side,
                        child: widget.child,
                      ),
                    ],
                  ),
                ),
              ),
              // Обод живёт отдельным слоем: пока он бежит, ни маска, ни кадр
              // не перерисовываются.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RingPainter(
                      shape: shape,
                      color: widget.ringColor,
                      track: widget.trackColor,
                      width: widget.ringWidth,
                      staticProgress: widget.ringProgress,
                      value: widget.ringValue,
                      repaint: widget.ringListenable,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  /// Линейка контура переживает кадры: пересчитывается только при смене формы
  /// или размера.
  static NoteArcRuler? _ruler;

  final NoteShape shape;
  final Color color;
  final Color? track;
  final double width;
  final double staticProgress;
  final double Function()? value;

  _RingPainter({
    required this.shape,
    required this.color,
    required this.track,
    required this.width,
    required this.staticProgress,
    required this.value,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = (value?.call() ?? staticProgress).clamp(0.0, 1.0);
    if (p <= 0 && track == null) return;
    final path = shape.pathIn(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final t = track;
    if (t != null) {
      canvas.drawPath(path, paint..color = t);
    }
    if (p <= 0) return;
    paint.color = color;
    if (p >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    var ruler = _ruler;
    if (ruler == null ||
        !ruler.matches(shape.profile, size, shape.centerX, shape.centerY)) {
      ruler = _ruler = NoteArcRuler(
        profile: shape.profile,
        size: size,
        centerX: shape.centerX,
        centerY: shape.centerY,
      );
    }
    canvas.drawPath(ruler.arc(p), paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color ||
      old.track != track ||
      old.width != width ||
      old.staticProgress != staticProgress ||
      !identical(old.shape.profile, shape.profile);
}

/// Плоский значок формы — для ленты выбора и цитат. Рисуется тем же профилем,
/// что и сама фигурка, поэтому в ленте видно ровно то, что получится.
class NoteShapeGlyph extends StatelessWidget {
  final NoteShape shape;
  final double size;
  final Color color;

  const NoteShapeGlyph({
    super.key,
    required this.shape,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GlyphPainter(shape: shape, color: color)),
      );
}

class _GlyphPainter extends CustomPainter {
  final NoteShape shape;
  final Color color;

  const _GlyphPainter({required this.shape, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      shape.pathIn(size),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.color != color || !identical(old.shape.profile, shape.profile);
}
