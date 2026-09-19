import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../models/geo_arc.dart';
import '../../models/globe_math.dart';
import '../../services/map/map_palette.dart';
import 'arc_paint.dart';
import 'land_shapes.dart';

/// Как в этот кадр точка сферы становится точкой экрана.
///
/// Два состояния: шар ([GlobeScene.globe]) и развёртка
/// ([GlobeScene.unroll]). Шар режет сушу по видимому полушарию. Развёртка не
/// режет ничего: точки с обратной стороны прижаты к краю шара, долгота
/// склеивается вдоль каждого кольца (`GlobeTransition.screenLine`).
class GlobeScene {
  final GlobeBasis basis;
  final Offset sphereCenter;
  final double radius;
  final double graticule; // непрозрачность сетки
  final GlobeTransition? transition;
  final double alpha;

  /// Доля пути цвета суши от глобуса к плоской карте. Меняется только на
  /// последнем шаге, вместе с тайлами: на середине развёртки цвет прошёл бы
  /// через цвет воды, и берега пропали бы.
  final double landMix;

  const GlobeScene._({
    required this.basis,
    required this.sphereCenter,
    required this.radius,
    required this.graticule,
    this.transition,
    this.alpha = 0,
    this.landMix = 0,
  });

  factory GlobeScene.globe(GlobeFrame f) => GlobeScene._(
        basis: f.basis,
        sphereCenter: f.center,
        radius: f.radius,
        graticule: .7,
      );

  factory GlobeScene.unroll(GlobeTransition t, double alpha, {double landMix = 0}) => GlobeScene._(
        basis: t.targetBasis,
        sphereCenter: t.focus,
        radius: t.target.radius,
        graticule: .7 * (1 - alpha),
        transition: t,
        alpha: alpha,
        landMix: landMix,
      );

  bool get unrolled => transition != null;

  bool visible(Vec3 v) => unrolled || basis.depth(v) >= 0;

  Offset project(Vec3 v) =>
      transition?.screenAt(v, alpha: alpha) ?? basis.project(v, radius, sphereCenter);

  /// Ломаная: на шаре — только видимые куски, на развёртке — целиком.
  List<List<Offset>> lines(List<Vec3> line) {
    final t = transition;
    if (t != null) return [t.screenLine(line, alpha: alpha)];
    final out = <List<Offset>>[];
    var run = <Offset>[];
    for (final v in line) {
      if (basis.depth(v) < 0) {
        if (run.length > 1) out.add(run);
        run = <Offset>[];
        continue;
      }
      run.add(basis.project(v, radius, sphereCenter));
    }
    if (run.length > 1) out.add(run);
    return out;
  }

  Offset? toScreen(LatLng p) {
    final v = Vec3.fromLatLng(p.latitude, p.longitude);
    return visible(v) ? project(v) : null;
  }

  /// Дуга между двумя людьми в этом кадре. Целиком видна — приподнята той же
  /// формулой, что на карте; иначе рисуется видимый кусок как есть.
  List<Offset> arc(List<LatLng> gc) {
    final pts = [for (final p in gc) Vec3.fromLatLng(p.latitude, p.longitude)];
    final runs = lines(pts);
    if (runs.length == 1 && runs.first.length == pts.length) return arcify(runs.first);
    return runs.isEmpty ? const [] : runs.reduce((a, b) => a.length >= b.length ? a : b);
  }
}

/// Сетка шара через 30°: меридианы и параллели, заранее точками на сфере.
final List<List<Vec3>> kGraticule = [
  for (var lon = -180; lon < 180; lon += 30)
    [for (var lat = -80; lat <= 80; lat += 4) Vec3.fromLatLng(lat.toDouble(), lon.toDouble())],
  for (var lat = -60; lat <= 60; lat += 30)
    [for (var lon = -180; lon <= 180; lon += 4) Vec3.fromLatLng(lat.toDouble(), lon.toDouble())],
];

class GlobePainter extends CustomPainter {
  final GlobeScene scene;
  final List<LandRing> land;
  final MapPalette palette;
  final List<Offset> arc;
  final double? fly;

  GlobePainter({
    required this.scene,
    required this.land,
    required this.palette,
    required this.arc,
    this.fly,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final water = Paint()..color = palette.water;
    canvas.drawCircle(scene.sphereCenter, scene.radius, water);
    if (scene.unrolled && scene.alpha > 0) {
      // Шар раскатывается в плоскость — вода растекается на весь экран.
      canvas.drawRect(Offset.zero & size, Paint()..color = palette.water.withValues(alpha: scene.alpha));
    }

    final screen = (Offset.zero & size).inflate(40);
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in land) {
      final List<Offset> pts;
      if (scene.unrolled) {
        pts = scene.transition!.screenLine(ring.points, alpha: scene.alpha);
      } else {
        final a = math.acos(ring.center.dot(scene.basis.c).clamp(-1.0, 1.0));
        if (a - ring.radius > math.pi / 2) continue;
        final src = a + ring.radius < math.pi / 2
            ? ring.points
            : clipRingToCap(ring.points, scene.basis, cosTheta: 0);
        pts = [for (final v in src) scene.project(v)];
      }
      if (pts.length < 3 || !_touches(pts, screen)) continue;
      path.moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = Color.lerp(palette.globeLand, palette.land, scene.landMix)!);

    if (scene.graticule > .02) {
      final grat = Path();
      for (final line in kGraticule) {
        for (final run in scene.lines(line)) {
          grat.moveTo(run.first.dx, run.first.dy);
          for (var i = 1; i < run.length; i++) {
            grat.lineTo(run[i].dx, run[i].dy);
          }
        }
      }
      canvas.drawPath(
        grat,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..color = palette.region.withValues(alpha: scene.graticule),
      );
    }

    paintDottedArc(canvas, arc, color: palette.thread, halo: palette.halo);
    final f = fly;
    if (f != null) paintFlyingHeart(canvas, arc, f, color: palette.thread, halo: palette.halo);
  }

  /// Кольцо хоть краем задевает экран — иначе в путь его не кладём: при
  /// большом приближении суша уходит за экран на миллионы точек.
  static bool _touches(List<Offset> pts, Rect screen) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in pts) {
      if (p.dx < l) l = p.dx;
      if (p.dx > r) r = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dy > b) b = p.dy;
    }
    return screen.overlaps(Rect.fromLTRB(l, t, r, b));
  }

  @override
  bool shouldRepaint(covariant GlobePainter old) => true;
}
