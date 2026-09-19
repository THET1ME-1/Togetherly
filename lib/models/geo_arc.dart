import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

/// Точки дуги большого круга от [a] до [b] — кратчайший путь по шару.
///
/// На карте её рисует проекция: на глобусе она ложится на поверхность, на
/// плоской карте выгибается к полюсу. Отсюда начинается дуга между двумя
/// людьми на всех экранах «Где мы».
List<LatLng> greatCircle(LatLng a, LatLng b, {int segments = 64}) {
  final pa = _vec(a), pb = _vec(b);
  final dot = (pa[0] * pb[0] + pa[1] * pb[1] + pa[2] * pb[2]).clamp(-1.0, 1.0);
  final d = math.acos(dot);
  if (d < 1e-9) return [a, b];
  final s = math.sin(d);
  return [
    for (var i = 0; i <= segments; i++)
      () {
        final t = i / segments;
        final k1 = math.sin((1 - t) * d) / s, k2 = math.sin(t * d) / s;
        final x = k1 * pa[0] + k2 * pb[0];
        final y = k1 * pa[1] + k2 * pb[1];
        final z = k1 * pa[2] + k2 * pb[2];
        final lat = math.asin((z / math.sqrt(x * x + y * y + z * z)).clamp(-1.0, 1.0));
        final lon = math.atan2(y, x);
        return LatLng(lat * 180 / math.pi, lon * 180 / math.pi);
      }(),
  ];
}

List<double> _vec(LatLng p) {
  final la = p.latitudeInRad, lo = p.longitudeInRad;
  return [math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)];
}

/// Высота дуги над хордой: растёт с длиной, но в пределах 28…110 точек.
double arcHeight(double chord) => (chord * .3).clamp(28.0, 110.0);

/// Дуга над точками [pts]: к каждой добавляется подъём от хорды по синусу.
///
/// Одна формула на глобусе, на развёртке и на плоской карте, поэтому на
/// переходе дуга едет вместе с сушей и не ломается. Подъём идёт по нормали к
/// хорде в сторону верха экрана.
List<Offset> arcify(List<Offset> pts) {
  if (pts.length < 2) return pts;
  final m = pts.first, p = pts.last;
  final dx = p.dx - m.dx, dy = p.dy - m.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-6) return pts;
  var nx = -dy / len, ny = dx / len;
  if (ny > 0) {
    nx = -nx;
    ny = -ny;
  }
  final h = arcHeight(len);
  final last = pts.length - 1;
  return [
    for (var i = 0; i <= last; i++)
      () {
        final s = math.sin(math.pi * i / last) * h;
        return Offset(pts[i].dx + nx * s, pts[i].dy + ny * s);
      }(),
  ];
}

/// Склеивает прыжки через край мира: дуга Токио — Лос-Анджелес пересекает
/// антимеридиан, и проекция отдаёт соседние точки на разных краях карты.
List<Offset> unwrapScreenX(List<Offset> pts, double worldWidth) {
  if (pts.length < 2) return pts;
  final out = <Offset>[pts.first];
  var shift = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final jump = pts[i].dx - pts[i - 1].dx;
    if (jump > worldWidth / 2) shift -= worldWidth;
    if (jump < -worldWidth / 2) shift += worldWidth;
    out.add(Offset(pts[i].dx + shift, pts[i].dy));
  }
  return out;
}
