import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:love_app/models/geo_arc.dart';
import 'package:love_app/models/globe_math.dart';
import 'package:love_app/services/map/map_palette.dart';
import 'package:love_app/widgets/map/globe_view.dart';
import 'package:love_app/widgets/map/land_shapes.dart';

const _msk = LatLng(55.7520, 37.6175);
const _ber = LatLng(52.5200, 13.4050);
const _size = Size(360, 780);

/// Глобус, развёртка и переход рисуются без ошибок на настоящих контурах
/// суши, а суша на кадре занимает разумную долю. Картинки кадров кладутся в
/// `build/globe-frames/` — смотреть глазами после правок.
void main() {
  final palette = MapPalette.of(
    const ColorScheme.light().copyWith(
      surfaceContainerLow: const Color(0xFFFFF0F0),
      secondaryContainer: const Color(0xFFFFDADB),
      tertiaryContainer: const Color(0xFFFFDDB4),
      surface: const Color(0xFFFFF8F7),
    ),
    fill: const Color(0xFFF37094),
  );

  List<LandRing> land(String name) =>
      LandShapes.parse(ByteData.sublistView(File('assets/map/$name').readAsBytesSync()));

  final transition = GlobeTransition(
    rest: const GlobeView(lat: 55.5, lon: 25.5, radius: 520),
    target: GlobeTarget(lat: 54.5, lon: 25.5, radius: matchRadius(zoom: 2.68, lat: 54.5)),
    focus: const Offset(180, 330),
    horizonGap: 214,
    camera: const MercatorCamera(centerLat: 53.5, centerLon: 25.5, zoom: 2.68, size: _size),
  );

  Future<Uint8List> render(WidgetTester tester, GlobeScene scene, List<LandRing> rings) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & _size);
    canvas.drawRect(Offset.zero & _size, Paint()..color = palette.halo);
    GlobePainter(
      scene: scene,
      land: rings,
      palette: palette,
      arc: scene.arc(greatCircle(_msk, _ber)),
      fly: .5,
    ).paint(canvas, _size);
    final image = await tester.runAsync(() => recorder.endRecording().toImage(360, 780));
    final png = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    return png!.buffer.asUint8List();
  }

  for (final (name, p) in const [('rest', 0.0), ('zoom', .3), ('unroll', .7), ('flat', 1.0)]) {
    testWidgets('кадр перехода «$name»', (tester) async {
      final scene = p <= .55
          ? GlobeScene.globe(transition.viewAt(p / .55))
          : GlobeScene.unroll(transition, ((p - .55) / .3).clamp(0.0, 1.0),
              landMix: ((p - .85) / .15).clamp(0.0, 1.0));
      final rings = scene.radius > 700 ? land('land_50m.bin') : land('land_110m.bin');
      final png = await render(tester, scene, rings);
      Directory('build/globe-frames').createSync(recursive: true);
      File('build/globe-frames/$name.png').writeAsBytesSync(png);
      expect(png.length, greaterThan(3000));
      // Суша под Москвой: на шаре и на развёртке — цвет суши глобуса, в конце
      // перехода — цвет суши плоской карты, чтобы тайлы легли без вспышки.
      final at = scene.toScreen(const LatLng(55.0, 40.0))!;
      final raw = (await tester.runAsync(() async {
        final img = await ui.instantiateImageCodec(png).then((c) => c.getNextFrame());
        return img.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      }))!;
      final i = (at.dy.round() * 360 + at.dx.round()) * 4;
      final got = raw.buffer.asUint8List().sublist(i, i + 3);
      // Цвет суши держится до последнего шага и только там уходит в цвет карты.
      final want = p >= 1 ? palette.land : palette.globeLand;
      {
        expect(got, [for (final c in [want.r, want.g, want.b]) (c * 255).round()],
            reason: 'кадр $name, точка $at');
      }
      // Оба человека видны на кадре.
      expect(scene.toScreen(_msk), isNotNull);
      expect(scene.toScreen(_ber), isNotNull);
    });
  }
}
