import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/globe_math.dart';

/// Кольцо суши Natural Earth: точки на сфере плюс шапка, в которую оно
/// целиком помещается. Шапка нужна, чтобы не обрезать по краю вида кольца,
/// которые заведомо внутри или заведомо снаружи.
class LandRing {
  final List<Vec3> points;
  final Vec3 center;
  final double radius; // радианы

  LandRing(this.points)
      : center = _centroid(points),
        radius = _radius(points, _centroid(points));

  static Vec3 _centroid(List<Vec3> pts) {
    var s = const Vec3(0, 0, 0);
    for (final p in pts) {
      s = s + p;
    }
    return s.length < 1e-9 ? pts.first : s.normalized;
  }

  static double _radius(List<Vec3> pts, Vec3 c) {
    var minDot = 1.0;
    for (final p in pts) {
      final d = p.dot(c);
      if (d < minDot) minDot = d;
    }
    return math.acos(minDot.clamp(-1.0, 1.0));
  }
}

/// Контуры суши для глобуса. Формат пишет `tool/gen_map_assets.py`:
/// `uint32 колец`, дальше на каждое `uint32 n` и n пар float32 (долгота,
/// широта). Грубые (110m) — для дальнего плана, подробные (50m) — ближе.
class LandShapes {
  LandShapes._();

  static final Map<String, Future<List<LandRing>>> _cache = {};

  static Future<List<LandRing>> coarse() => _load('assets/map/land_110m.bin');
  static Future<List<LandRing>> detailed() => _load('assets/map/land_50m.bin');

  static Future<List<LandRing>> _load(String asset) => _cache[asset] ??= () async {
        final data = await rootBundle.load(asset);
        return parse(data);
      }();

  static List<LandRing> parse(ByteData data) {
    var o = 0;
    final count = data.getUint32(o, Endian.little);
    o += 4;
    final rings = <LandRing>[];
    for (var r = 0; r < count; r++) {
      final n = data.getUint32(o, Endian.little);
      o += 4;
      final pts = List<Vec3>.generate(n, (i) {
        final lon = data.getFloat32(o + i * 8, Endian.little);
        final lat = data.getFloat32(o + i * 8 + 4, Endian.little);
        return Vec3.fromLatLng(lat, lon);
      });
      o += n * 8;
      if (pts.length >= 3) rings.add(LandRing(pts));
    }
    return rings;
  }
}
