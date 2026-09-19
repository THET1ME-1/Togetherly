import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../theme/fonts.dart';
import '../../utils/safe_text.dart';
import '../connect_expressive.dart';
import '../storage_image.dart';

/// Размер шарика и где в нём точка на карте.
const double kBalloonWidth = 80;
const double kBalloonHeight = 104;
const double kBalloonDotY = 96;

/// Якорь для `Marker` flutter_map: точка на карте ложится на кружок под
/// ниточкой, а не на край виджета.
const Alignment kBalloonAlignment = Alignment(0, 1 - 2 * kBalloonDotY / kBalloonHeight);

/// Цвета шарика берутся из схемы темы.
class BalloonColors {
  final Color ring, string, dot, face, onFace;
  const BalloonColors({
    required this.ring,
    required this.string,
    required this.dot,
    required this.face,
    required this.onFace,
  });
}

/// Аватарка на ниточке, как воздушный шарик. Форма та же, что на экране связи
/// (`kAvatarShapes`), поэтому человек узнаёт себя и партнёра по силуэту.
///
/// Живая точка пульсирует; устаревшая выцветает — бледная метка без подписи
/// читалась бы как «дома», поэтому давность пишется в панели словами.
class MapBalloon extends StatefulWidget {
  final RoundedPolygon shape;
  final String avatarUrl;
  final String name;
  final BalloonColors colors;
  final bool live;
  final bool stale;

  const MapBalloon({
    super.key,
    required this.shape,
    required this.avatarUrl,
    required this.name,
    required this.colors,
    this.live = false,
    this.stale = false,
  });

  @override
  State<MapBalloon> createState() => _MapBalloonState();
}

class _MapBalloonState extends State<MapBalloon> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant MapBalloon old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    final on = widget.live && !widget.stale && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (on && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!on && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    Widget face = AvatarFace(
      shape: widget.shape,
      size: 58,
      avatarUrl: widget.avatarUrl,
      name: widget.name,
      fill: c.face,
      onFill: c.onFace,
    );
    if (widget.stale) {
      face = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          .33, .59, .11, 0, 0, //
          .33, .59, .11, 0, 0, //
          .33, .59, .11, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
        child: face,
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        width: kBalloonWidth,
        height: kBalloonHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _StringPainter(
                  pulse: _pulse,
                  colors: c,
                  stale: widget.stale,
                ),
              ),
            ),
            Positioned(
              left: kBalloonWidth / 2 - 33,
              top: 1,
              child: ClipPath(
                clipper: M3ShapeClipper(widget.shape),
                child: Container(
                  width: 66,
                  height: 66,
                  color: c.ring,
                  alignment: Alignment.center,
                  child: face,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Лицо в форме: фото или первая буква имени на тональной заливке.
class AvatarFace extends StatelessWidget {
  final RoundedPolygon shape;
  final double size;
  final String avatarUrl;
  final String name;
  final Color fill, onFill;

  const AvatarFace({
    super.key,
    required this.shape,
    required this.size,
    required this.avatarUrl,
    required this.name,
    required this.fill,
    required this.onFill,
  });

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      color: fill,
      alignment: Alignment.center,
      child: Text(
        name.firstGraphemeUpper('♥'),
        style: AppFonts.unbounded(size: size * .38, weight: 800, color: onFill),
      ),
    );
    return ClipPath(
      clipper: M3ShapeClipper(shape),
      child: SizedBox(
        width: size,
        height: size,
        child: avatarUrl.isEmpty
            ? letter
            : StorageImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).round(),
                errorWidget: (_, _, _) => letter,
              ),
      ),
    );
  }
}

class _StringPainter extends CustomPainter {
  final Animation<double> pulse;
  final BalloonColors colors;
  final bool stale;

  _StringPainter({required this.pulse, required this.colors, required this.stale}) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    const x = kBalloonWidth / 2;
    final halo = Paint()
      ..color = colors.ring
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = colors.string
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(x, 66), const Offset(x, 90), halo);
    canvas.drawLine(const Offset(x, 66), const Offset(x, 90), line);
    const dot = Offset(x, kBalloonDotY);
    if (pulse.isAnimating) {
      final t = Curves.easeOutQuart.transform(pulse.value);
      canvas.drawCircle(dot, 6 + 13 * t, Paint()..color = colors.dot.withValues(alpha: .55 * (1 - t)));
    }
    canvas.drawCircle(dot, 7.5, Paint()..color = colors.ring);
    canvas.drawCircle(dot, 5.5, Paint()..color = stale ? colors.string.withValues(alpha: .5) : colors.dot);
  }

  @override
  bool shouldRepaint(covariant _StringPainter old) => old.colors != colors || old.stale != stale;
}
