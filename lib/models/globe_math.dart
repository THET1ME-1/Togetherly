import 'dart:math' as math;
import 'dart:ui';

/// Точка на единичной сфере. Глобус «Где мы» хранит сушу векторами, чтобы
/// поворот шара стоил три скалярных произведения на точку.
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  factory Vec3.fromLatLng(double lat, double lon) {
    final la = lat * math.pi / 180, lo = lon * math.pi / 180;
    return Vec3(math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la));
  }

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get normalized {
    final l = length;
    return l < 1e-12 ? this : Vec3(x / l, y / l, z / l);
  }

  double get lat => math.asin(z.clamp(-1.0, 1.0)) * 180 / math.pi;
  double get lon => math.atan2(y, x) * 180 / math.pi;
}

/// Ортографический вид шара с центром в точке (lat, lon): восток вправо,
/// север вверх, глубина — к смотрящему. Та же проекция, что у
/// `d3.geoOrthographic` в макете.
class GlobeBasis {
  final Vec3 c, e, n;

  GlobeBasis._(this.c, this.e, this.n);

  factory GlobeBasis(double lat, double lon) {
    final la = lat * math.pi / 180, lo = lon * math.pi / 180;
    return GlobeBasis._(
      Vec3(math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)),
      Vec3(-math.sin(lo), math.cos(lo), 0),
      Vec3(-math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la)),
    );
  }

  /// Больше нуля — точка на видимой стороне.
  double depth(Vec3 v) => v.dot(c);

  Offset project(Vec3 v, double radius, Offset center) =>
      Offset(center.dx + radius * v.dot(e), center.dy - radius * v.dot(n));

  double angleOf(Vec3 v) => math.atan2(v.dot(n), v.dot(e));

  /// Точка края шапки с угловым радиусом acos([cosTheta]) под углом [phi].
  Vec3 boundary(double phi, double cosTheta) {
    final sinTheta = math.sqrt(math.max(0, 1 - cosTheta * cosTheta));
    return c * cosTheta + (e * math.cos(phi) + n * math.sin(phi)) * sinTheta;
  }

  Vec3 toBoundary(Vec3 v, double cosTheta) {
    final q = v - c * v.dot(c);
    if (q.length < 1e-12) return boundary(0, cosTheta);
    return boundary(angleOf(q), cosTheta);
  }
}

/// Обрезает кольцо суши по шапке вокруг центра вида (acos([cosTheta]) —
/// угловой радиус; 0 — видимое полушарие).
///
/// Там, где кольцо уходит за край, вместо него идёт дуга по самому краю, в
/// кратчайшую сторону. Кольцо целиком внутри возвращается как есть, целиком
/// снаружи — пустым.
List<Vec3> clipRingToCap(
  List<Vec3> ring,
  GlobeBasis b, {
  required double cosTheta,
  double stepDeg = 4,
}) {
  final n = ring.length;
  if (n < 3) return const [];
  final d = [for (final v in ring) b.depth(v) - cosTheta];
  final start = d.indexWhere((x) => x >= 0);
  if (start < 0) return const [];
  if (d.every((x) => x >= 0)) return ring;

  final out = <Vec3>[];
  double? exit;
  final step = stepDeg * math.pi / 180;
  for (var k = 0; k < n; k++) {
    final i = (start + k) % n, j = (i + 1) % n;
    final di = d[i], dj = d[j];
    if (di >= 0) out.add(ring[i]);
    if ((di >= 0) == (dj >= 0)) continue;
    final t = di / (di - dj);
    final p = b.toBoundary((ring[i] * (1 - t) + ring[j] * t).normalized, cosTheta);
    if (di >= 0) {
      out.add(p);
      exit = b.angleOf(p);
    } else {
      final entry = b.angleOf(p);
      if (exit != null) {
        var diff = entry - exit;
        while (diff > math.pi) {
          diff -= 2 * math.pi;
        }
        while (diff < -math.pi) {
          diff += 2 * math.pi;
        }
        final steps = math.max(1, (diff.abs() / step).ceil());
        for (var s = 1; s < steps; s++) {
          out.add(b.boundary(exit + diff * s / steps, cosTheta));
        }
      }
      out.add(p);
      exit = null;
    }
  }
  return out;
}

/// Мировая ширина карты в точках на зуме [zoom] (плитки по 256, как у
/// flutter_map).
double worldSize(double zoom) => 256 * math.pow(2, zoom).toDouble();

double _mercY(double lat) {
  final l = lat.clamp(-85.05, 85.05) * math.pi / 180;
  return (1 - math.log(math.tan(math.pi / 4 + l / 2)) / math.pi) / 2;
}

/// Плоская карта flutter_map без поворота: центр, зум и размер экрана.
class MercatorCamera {
  final double centerLat, centerLon, zoom;
  final Size size;
  const MercatorCamera({
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.size,
  });

  /// Точка по сдвигу долготы от центра [dLon] — без переноса через край мира,
  /// чтобы кольцо суши, переходящее антимеридиан, оставалось целым.
  Offset byDelta(double lat, double dLon) {
    final w = worldSize(zoom);
    return Offset(
      size.width / 2 + dLon / 360 * w,
      size.height / 2 + (_mercY(lat) - _mercY(centerLat)) * w,
    );
  }

  /// Точка на экране; долгота берётся ближайшей к центру.
  Offset screen(double lat, double lon) => byDelta(lat, wrap180(lon - centerLon));
}

double wrap180(double d) {
  while (d > 180) {
    d -= 360;
  }
  while (d < -180) {
    d += 360;
  }
  return d;
}

/// Где точка встанет на плоской карте с центром (centerLat, centerLon) на
/// зуме [zoom] и экраном [size] — та же формула, что у камеры flutter_map.
Offset mercatorScreen(
  double lat,
  double lon, {
  required double centerLat,
  required double centerLon,
  required double zoom,
  required Size size,
}) =>
    MercatorCamera(centerLat: centerLat, centerLon: centerLon, zoom: zoom, size: size).screen(lat, lon);

/// Радиус шара, при котором масштаб в центре совпадает с плоской картой:
/// меркатор растягивает всё на 1/cos(широты).
double matchRadius({required double zoom, required double lat}) =>
    worldSize(zoom) / (2 * math.pi) / math.cos(lat * math.pi / 180);

class GlobeView {
  final double lat, lon, radius;
  const GlobeView({required this.lat, required this.lon, required this.radius});
}

class GlobeTarget {
  final double lat, lon, radius;
  const GlobeTarget({required this.lat, required this.lon, required this.radius});
}

/// Кадр глобуса: центр проекции, радиус, где на экране центр шара и
/// насколько он наклонён (градусы).
class GlobeFrame {
  final double lat, lon, radius, tilt;
  final Offset center;
  const GlobeFrame({
    required this.lat,
    required this.lon,
    required this.radius,
    required this.center,
    required this.tilt,
  });

  GlobeBasis get basis => GlobeBasis(lat, lon);
}

double _easeInOutCubic(double t) =>
    t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

/// Переход «глобус → карта» в двух частях.
///
/// Приближение ([viewAt]): шар растёт от вида [rest] до [target], где его
/// масштаб в центре совпадает с картой, наклон горизонта уходит. Развёртка
/// ([screenAt], [screenLine]): каждая точка едет из ортографической проекции
/// конечного шара в плоскую карту [camera]; на `alpha = 1` она стоит ровно
/// там, где её рисует карта, и тайлы проявляются поверх без сдвига.
///
/// Точки с обратной стороны шара прижимаются к его краю — на развёртке они
/// уезжают с экрана, а резать сушу шапкой нельзя: шапка у полюса захватывает
/// все долготы, и на плоской карте кольца рвутся полосой.
///
/// [focus] — точка экрана, где у шара центр пары, а у карты — точка [target].
/// [horizonGap] — сколько точек от фокуса до края шара в покое: наклон
/// поднимает горизонт до этой высоты, и шар выглядит планетой, а не кругом.
class GlobeTransition {
  final GlobeView rest;
  final GlobeTarget target;
  final Offset focus;
  final MercatorCamera camera;
  final double horizonGap;

  GlobeTransition({
    required this.rest,
    required this.target,
    required this.focus,
    required this.camera,
    this.horizonGap = 214,
  }) : targetBasis = GlobeBasis(target.lat, target.lon);

  final GlobeBasis targetBasis;

  GlobeFrame viewAt(double p) {
    final e = _easeInOutCubic(p.clamp(0.0, 1.0));
    final lat = rest.lat + (target.lat - rest.lat) * e;
    final lon = rest.lon + wrap180(target.lon - rest.lon) * e;
    final r = math.exp(math.log(rest.radius) + (math.log(target.radius) - math.log(rest.radius)) * e);
    final s = (1 - horizonGap / r).clamp(0.0, .8) * (1 - e);
    final tilt = math.asin(s) * 180 / math.pi;
    return GlobeFrame(
      lat: lat - tilt,
      lon: lon,
      radius: r,
      center: Offset(focus.dx, focus.dy + r * s),
      tilt: tilt,
    );
  }

  Offset _ortho(Vec3 v) {
    var x = v.dot(targetBasis.e), y = v.dot(targetBasis.n);
    if (targetBasis.depth(v) < 0) {
      final l = math.sqrt(x * x + y * y);
      if (l > 1e-9) {
        x /= l;
        y /= l;
      }
    }
    return Offset(focus.dx + target.radius * x, focus.dy - target.radius * y);
  }

  static Offset _mix(Offset a, Offset b, double t) =>
      Offset(a.dx * (1 - t) + b.dx * t, a.dy * (1 - t) + b.dy * t);

  /// Одна точка развёртки.
  Offset screenAt(Vec3 v, {required double alpha}) =>
      _mix(_ortho(v), camera.screen(v.lat, v.lon), alpha);

  /// Ломаная развёртки: долгота склеивается вдоль неё, поэтому кольцо,
  /// переходящее антимеридиан, не рвётся через весь экран.
  List<Offset> screenLine(List<Vec3> line, {required double alpha}) {
    final out = List<Offset>.filled(line.length, Offset.zero);
    double? prev;
    for (var i = 0; i < line.length; i++) {
      final v = line[i];
      var d = v.lon - camera.centerLon;
      if (prev == null) {
        d = wrap180(d);
      } else {
        d = prev + wrap180(d - prev);
      }
      prev = d;
      out[i] = _mix(_ortho(v), camera.byDelta(v.lat, d), alpha);
    }
    return out;
  }
}
