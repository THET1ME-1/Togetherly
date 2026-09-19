import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:love_app/models/geo_arc.dart';
import 'package:love_app/models/globe_math.dart';
import 'package:love_app/models/map_distance.dart';

const _pit = LatLng(59.9398, 30.3146);
const _msk = LatLng(55.7520, 37.6175);
const _ber = LatLng(52.5200, 13.4050);

String _ru(double m) => formatMapDistance(m, lang: 'ru', nearby: 'Рядом', unitM: 'м', unitKm: 'км');
String _en(double m) => formatMapDistance(m, lang: 'en', nearby: 'Nearby', unitM: 'm', unitKm: 'km');

void main() {
  group('formatMapDistance', () {
    test('ближе 50 метров — «рядом»: GPS ошибается на 5–15 м', () {
      expect(_ru(0.34), 'Рядом');
      expect(_ru(49), 'Рядом');
    });

    test('метры округляются до десятка', () {
      expect(_ru(344), '340 м');
      expect(_ru(50), '50 м');
    });

    test('до десяти километров — одна цифра после запятой по языку', () {
      expect(_ru(2880), '2,9 км');
      expect(_en(2880), '2.9 km');
    });

    test('тысячи километров разделены пробелом', () {
      expect(_ru(1608825), '1 609 км');
      expect(_en(1608825), '1,609 km');
    });

    test('сотни километров без дробной части', () {
      expect(_ru(634599), '635 км');
    });
  });

  group('greatCircle', () {
    test('концы совпадают с точками, середина — на дуге большого круга', () {
      final pts = greatCircle(_msk, _ber, segments: 32);
      expect(pts.first.latitude, closeTo(_msk.latitude, 1e-9));
      expect(pts.last.longitude, closeTo(_ber.longitude, 1e-9));
      // Дуга большого круга между Москвой и Берлином выгибается к северу.
      final mid = pts[16];
      expect(mid.latitude, greaterThan((_msk.latitude + _ber.latitude) / 2));
    });
  });

  group('arcify', () {
    test('концы остаются на месте, середина поднимается вверх экрана', () {
      final flat = [for (var i = 0; i <= 10; i++) Offset(i * 20.0, 300)];
      final arc = arcify(flat);
      expect(arc.first, flat.first);
      expect(arc.last, flat.last);
      expect(arc[5].dy, closeTo(300 - arcHeight(200), 1e-9));
    });

    test('высота дуги растёт с длиной, но в пределах 28…110', () {
      expect(arcHeight(10), 28);
      expect(arcHeight(200), closeTo(60, 1e-9));
      expect(arcHeight(2000), 110);
    });

    test('вертикальная хорда всё равно выгибается, а не ломается', () {
      final flat = [for (var i = 0; i <= 10; i++) Offset(100, i * 30.0)];
      final arc = arcify(flat);
      expect(arc[5].dx, isNot(closeTo(100, 1)));
      expect(arc.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    });
  });

  group('unwrapScreenX', () {
    test('прыжок через край мира склеивается', () {
      const world = 1024.0;
      final out = unwrapScreenX(const [Offset(1000, 0), Offset(10, 0)], world);
      expect(out[1].dx, closeTo(1034, 1e-9));
    });
  });

  group('GlobeBasis', () {
    test('центр вида попадает в центр экрана', () {
      final b = GlobeBasis(_msk.latitude, _msk.longitude);
      final p = b.project(Vec3.fromLatLng(_msk.latitude, _msk.longitude), 300, const Offset(180, 320));
      expect(p.dx, closeTo(180, 1e-6));
      expect(p.dy, closeTo(320, 1e-6));
    });

    test('север — вверх экрана', () {
      final b = GlobeBasis(_msk.latitude, _msk.longitude);
      final p = b.project(Vec3.fromLatLng(_pit.latitude, _msk.longitude), 300, const Offset(180, 320));
      expect(p.dy, lessThan(320));
    });

    test('точка на обратной стороне шара не видна', () {
      final b = GlobeBasis(0, 0);
      expect(b.depth(Vec3.fromLatLng(0, 180)), lessThan(0));
      expect(b.depth(Vec3.fromLatLng(0, 10)), greaterThan(0));
    });
  });

  group('clipRingToCap', () {
    final basis = GlobeBasis(0, 0);

    test('кольцо целиком внутри шапки не меняется', () {
      final ring = [
        for (final (la, lo) in const [(1.0, 1.0), (1.0, 2.0), (2.0, 2.0), (2.0, 1.0)]) Vec3.fromLatLng(la, lo)
      ];
      expect(clipRingToCap(ring, basis, cosTheta: 0).length, ring.length);
    });

    test('кольцо на обратной стороне исчезает', () {
      final ring = [
        for (final (la, lo) in const [(1.0, 179.0), (1.0, 178.0), (2.0, 178.0)]) Vec3.fromLatLng(la, lo)
      ];
      expect(clipRingToCap(ring, basis, cosTheta: 0), isEmpty);
    });

    test('кольцо поперёк горизонта обрезается по краю шапки', () {
      final ring = [
        for (final (la, lo) in const [(-10.0, 60.0), (-10.0, 120.0), (10.0, 120.0), (10.0, 60.0)])
          Vec3.fromLatLng(la, lo)
      ];
      final clipped = clipRingToCap(ring, basis, cosTheta: 0);
      expect(clipped, isNotEmpty);
      for (final v in clipped) {
        expect(basis.depth(v), greaterThanOrEqualTo(-1e-9));
      }
      // На краю лежат по меньшей мере две точки: вход и выход.
      expect(clipped.where((v) => basis.depth(v).abs() < 1e-6).length, greaterThanOrEqualTo(2));
    });
  });

  group('GlobeTransition', () {
    // Камера карты: центр между Берлином и Москвой, зум 3.
    Offset merc(double lat, double lon) => mercatorScreen(lat, lon,
        centerLat: 54.5, centerLon: 25.5, zoom: 3, size: const Size(360, 780));

    test('масштаб шара в конце приближения равен масштабу карты в центре', () {
      final r = matchRadius(zoom: 3, lat: 54.5);
      final dLat = 0.01;
      final a = merc(54.5, 25.5), b = merc(54.5 + dLat, 25.5);
      final pxPerRad = (a - b).distance / (dLat * math.pi / 180);
      expect(r, closeTo(pxPerRad, pxPerRad * 1e-3));
    });

    test('на полной развёртке точка стоит там же, где её рисует карта', () {
      final t = GlobeTransition(
        rest: const GlobeView(lat: 55, lon: 25, radius: 520),
        target: const GlobeTarget(lat: 54.5, lon: 25.5, radius: 900),
        focus: const Offset(180, 390),
        camera: const MercatorCamera(centerLat: 54.5, centerLon: 25.5, zoom: 3, size: Size(360, 780)),
      );
      final v = Vec3.fromLatLng(_msk.latitude, _msk.longitude);
      final got = t.screenAt(v, alpha: 1), want = merc(_msk.latitude, _msk.longitude);
      expect((got - want).distance, lessThan(1e-6));
    });

    test('без развёртки точка лежит на шаре конечного приближения', () {
      final t = GlobeTransition(
        rest: const GlobeView(lat: 55, lon: 25, radius: 520),
        target: const GlobeTarget(lat: 54.5, lon: 25.5, radius: 900),
        focus: const Offset(180, 390),
        camera: const MercatorCamera(centerLat: 54.5, centerLon: 25.5, zoom: 3, size: Size(360, 780)),
      );
      final v = Vec3.fromLatLng(54.5, 25.5);
      expect(t.screenAt(v, alpha: 0).dx, closeTo(180, 1e-6));
      expect(t.screenAt(v, alpha: 0).dy, closeTo(390, 1e-6));
    });

    test('приближение снимает наклон к концу', () {
      final t = GlobeTransition(
        rest: const GlobeView(lat: 55, lon: 25, radius: 520),
        target: const GlobeTarget(lat: 54.5, lon: 25.5, radius: 900),
        focus: const Offset(180, 390),
        camera: const MercatorCamera(centerLat: 54.5, centerLon: 25.5, zoom: 3, size: Size(360, 780)),
      );
      expect(t.viewAt(1).tilt, 0);
      expect(t.viewAt(0).tilt, greaterThan(0));
    });
  });
}
