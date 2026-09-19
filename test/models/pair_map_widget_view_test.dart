// Виджет «Где мы» на рабочем столе (19.09.2026): как двое вписываются в
// каждый из трёх размеров, когда показывать карту, глобус или «рядом», какие
// плитки нужны и в каком масштабе рисовать картинку.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:love_app/models/globe_math.dart';
import 'package:love_app/models/pair_map_widget_view.dart';

const chisinau = LatLng(47.0245, 28.8325);
const botanica = LatLng(47.0060, 28.8575);
const berlin = LatLng(52.52, 13.405);
const newYork = LatLng(40.7128, -74.006);

void main() {
  group('размеры', () {
    test('три размера и свои отступы', () {
      expect(MapWidgetSize.values.map((s) => s.id), ['s', 'm', 'l']);
      for (final s in MapWidgetSize.values) {
        final safe = s.safe;
        expect(safe.left + safe.right, lessThan(s.width));
        expect(safe.top + safe.bottom, lessThan(s.height));
      }
    });

    test('масштаб картинки: не больше трёх и в пределах памяти', () {
      for (final s in MapWidgetSize.values) {
        for (final size in [Size(s.width, s.height), const Size(400, 420)]) {
          final k = pixelScaleFor(size);
          expect(k, lessThanOrEqualTo(3));
          final bytes = size.width * k * size.height * k * 2; // RGB_565
          expect(bytes, lessThanOrEqualTo(kMapWidgetImageBudget + 1));
        }
      }
    });

    test('размер берётся из присланного лончером, иначе по умолчанию', () {
      expect(MapWidgetSize.m.sizeFrom('300,180'), const Size(300, 180));
      expect(MapWidgetSize.m.sizeFrom(''), Size(MapWidgetSize.m.width, MapWidgetSize.m.height));
      expect(MapWidgetSize.m.sizeFrom('мусор'), Size(MapWidgetSize.m.width, MapWidgetSize.m.height));
      expect(MapWidgetSize.m.sizeFrom('0,0'), Size(MapWidgetSize.m.width, MapWidgetSize.m.height));
    });

    test('размеры виджетов iPhone по ширине экрана', () {
      expect(iosWidgetSizes(430)[MapWidgetSize.m], const Size(364, 170));
      expect(iosWidgetSizes(393)[MapWidgetSize.s], const Size(158, 158));
      expect(iosWidgetSizes(375)[MapWidgetSize.l], const Size(329, 345));
      expect(iosWidgetSizes(320)[MapWidgetSize.m], const Size(292, 141));
    });
  });

  group('что показать', () {
    PairMapMode mode({bool paired = true, LatLng? me, LatLng? her}) => pairMapMode(
          paired: paired,
          me: me,
          partner: her,
          size: const Size(364, 170),
          safe: MapWidgetSize.m.safe,
        );

    test('без пары — приглашение', () {
      expect(mode(paired: false, me: chisinau, her: botanica), PairMapMode.noPair);
    });
    test('ни у кого нет точки', () => expect(mode(), PairMapMode.noPoints));
    test('точка только у одного', () {
      expect(mode(me: chisinau), PairMapMode.onlyMe);
      expect(mode(her: botanica), PairMapMode.onlyPartner);
    });
    test('ближе пятидесяти метров — рядом', () {
      expect(mode(me: chisinau, her: const LatLng(47.02452, 28.83256)), PairMapMode.near);
    });
    test('в одном городе — карта', () {
      expect(mode(me: chisinau, her: botanica), PairMapMode.map);
    });
    test('между странами — глобус', () {
      expect(mode(me: chisinau, her: berlin), PairMapMode.globe);
      expect(mode(me: chisinau, her: newYork), PairMapMode.globe);
    });
  });

  group('карта двоих', () {
    test('обе точки внутри безопасной зоны', () {
      for (final s in MapWidgetSize.values) {
        final size = Size(s.width, s.height);
        final fit = fitTwo(chisinau, botanica, size, s.safe);
        final cam = MercatorCamera(
            centerLat: fit.center.latitude, centerLon: fit.center.longitude, zoom: fit.zoom, size: size);
        final inner = s.safe.deflateRect(Offset.zero & size).inflate(0.5);
        for (final p in [chisinau, botanica]) {
          expect(inner.contains(cam.screen(p.latitude, p.longitude)), isTrue,
              reason: '${s.id}: $p вне безопасной зоны');
        }
      }
    });

    test('одна точка — в середине безопасной зоны на заданном зуме', () {
      for (final s in MapWidgetSize.values) {
        final size = Size(s.width, s.height);
        final fit = fitOne(chisinau, size, s.safe, zoom: 13.5);
        expect(fit.zoom, 13.5);
        final cam = MercatorCamera(
            centerLat: fit.center.latitude, centerLon: fit.center.longitude, zoom: fit.zoom, size: size);
        final at = cam.screen(chisinau.latitude, chisinau.longitude);
        final mid = s.safe.deflateRect(Offset.zero & size).center;
        expect((at - mid).distance, lessThan(1), reason: s.id);
      }
    });

    test('близкие точки не приближаются бесконечно', () {
      final fit = fitTwo(chisinau, const LatLng(47.0247, 28.8328), const Size(364, 170), MapWidgetSize.m.safe);
      expect(fit.zoom, lessThanOrEqualTo(kMapWidgetMaxZoom));
    });

    test('плитки покрывают всю картинку и не выходят за 14-й зум', () {
      const size = Size(364, 170);
      final fit = fitTwo(chisinau, botanica, size, MapWidgetSize.m.safe);
      final tiles = tilesFor(fit.center, fit.zoom, size);
      expect(tiles, isNotEmpty);
      expect(tiles.every((t) => t.z <= 14), isTrue);
      final covered = tiles.map((t) => t.rect).reduce((a, b) => a.expandToInclude(b));
      expect(covered.contains(Offset.zero), isTrue);
      expect(covered.contains(Offset(size.width - 0.1, size.height - 0.1)), isTrue);
      // Лишнего не качаем: каждая плитка задевает картинку.
      expect(tiles.every((t) => t.rect.overlaps(Offset.zero & size)), isTrue);
    });

    test('плитки за краем мира заворачиваются', () {
      final tiles = tilesFor(const LatLng(64, 179.99), 6, const Size(364, 170));
      final n = 1 << 6;
      expect(tiles.every((t) => t.x >= 0 && t.x < n), isTrue);
    });
  });

  group('глобус', () {
    const sydney = LatLng(-33.87, 151.21);
    for (final s in MapWidgetSize.values) {
      for (final (name, far) in [('Берлин', berlin), ('Нью-Йорк', newYork), ('Сидней', sydney)]) {
        test('${s.id}: Кишинёв и $name видны и стоят в безопасной зоне', () {
          final size = Size(s.width, s.height);
          final f = globeFrameFor(chisinau, far, size, s.safe);
          final b = f.basis;
          final inner = s.safe.deflateRect(Offset.zero & size).inflate(1);
          for (final p in [chisinau, far]) {
            final v = Vec3.fromLatLng(p.latitude, p.longitude);
            expect(b.depth(v), greaterThan(0), reason: '$p за горизонтом');
            expect(inner.contains(b.project(v, f.radius, f.center)), isTrue,
                reason: '${s.id}: $p вне зоны');
          }
          // Верх шара — в верхней половине: горизонт читается, а не шар
          // болтается внизу маленьким кругом.
          expect(f.center.dy - f.radius, lessThanOrEqualTo(size.height * .5));
          // Двое не слипаются: между ними не меньше трети ширины зоны.
          final pa0 = b.project(Vec3.fromLatLng(chisinau.latitude, chisinau.longitude), f.radius, f.center);
          final pb0 = b.project(Vec3.fromLatLng(far.latitude, far.longitude), f.radius, f.center);
          expect((pa0.dx - pb0.dx).abs(), greaterThanOrEqualTo(math.min(inner.width * .6, 150)));
          // Пара стоит по горизонтали.
          final pa = b.project(Vec3.fromLatLng(chisinau.latitude, chisinau.longitude), f.radius, f.center);
          final pb = b.project(Vec3.fromLatLng(far.latitude, far.longitude), f.radius, f.center);
          expect((pa.dy - pb.dy).abs(), lessThan(1));
        });
      }
    }
  });

  group('дуга', () {
    test('нижний предел подъёма поднимает дугу выше естественной', () {
      final base = [for (var i = 0; i <= 10; i++) Offset(i * 20.0, 100)];
      final pts = liftAlong(base, maxLift: 90, minLift: 80);
      expect(pts.map((p) => p.dy).reduce(math.min), closeTo(20, 0.5));
    });

    test('подъём вдоль ломаной сохраняет концы и не выше предела', () {
      final base = [for (var i = 0; i <= 10; i++) Offset(i * 20.0, 100)];
      final pts = liftAlong(base, maxLift: 30);
      expect(pts.first, base.first);
      expect(pts.last, base.last);
      expect(pts.map((p) => p.dy).reduce(math.min), closeTo(70, 0.5));
    });

    test('поднимается вверх и не вылезает за верх картинки', () {
      final a = const Offset(60, 120), b = const Offset(300, 120);
      final pts = liftedArc(a, b, maxLift: 60);
      final top = pts.map((p) => p.dy).reduce(math.min);
      expect(top, lessThan(120));
      expect(top, greaterThanOrEqualTo(60 - 0.001));
      expect(pts.first, a);
      expect(pts.last, b);
    });

    test('вершина дуги — середина по длине', () {
      final pts = liftedArc(const Offset(0, 100), const Offset(200, 100), maxLift: 40);
      final apex = arcApex(pts);
      expect(apex.dx, closeTo(100, 4));
      expect(apex.dy, closeTo(60, 1));
    });
  });
}
