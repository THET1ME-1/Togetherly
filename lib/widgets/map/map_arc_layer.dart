import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/geo_arc.dart';
import '../../services/map/map_palette.dart';
import 'arc_paint.dart';

/// Дуга между двумя людьми на плоской карте — слой внутри `FlutterMap`.
///
/// Точки дуги большого круга переводятся камерой в экран и поднимаются той же
/// формулой, что на глобусе, поэтому после перехода дуга не прыгает. Переход
/// через антимеридиан склеивается по ширине мира. [fly] — сердце «Скучаю» на
/// дуге, от меня к партнёру.
class MapArcLayer extends StatelessWidget {
  final LatLng from;
  final LatLng to;
  final MapPalette palette;
  final ValueListenable<double?>? fly;

  const MapArcLayer({
    super.key,
    required this.from,
    required this.to,
    required this.palette,
    this.fly,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final gc = greatCircle(from, to, segments: 64);
    final pts = arcify(unwrapScreenX(
      [for (final p in gc) camera.latLngToScreenOffset(p)],
      camera.getWorldWidthAtZoom(),
    ));
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _ArcPainter(pts, palette, fly),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final List<Offset> pts;
  final MapPalette palette;
  final ValueListenable<double?>? fly;

  _ArcPainter(this.pts, this.palette, this.fly) : super(repaint: fly);

  @override
  void paint(Canvas canvas, Size size) {
    paintDottedArc(canvas, pts, color: palette.thread, halo: palette.halo);
    final f = fly?.value;
    if (f != null) paintFlyingHeart(canvas, pts, f, color: palette.thread, halo: palette.halo);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.pts != pts || old.palette != palette;
}
