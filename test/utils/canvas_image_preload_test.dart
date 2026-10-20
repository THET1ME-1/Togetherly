import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/utils/canvas_image_cache.dart';

/// Виджет «Холст» на рабочем столе рисуется один раз и сам не обновляется,
/// поэтому заливки ему надо дождаться заранее (20.10.2026: без них
/// раскраска на виджете и на плитке галереи стояла пустой).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DrawStroke fill(String url) => DrawStroke(
        id: 'fill',
        userId: 'u',
        points: const [],
        colorValue: 0xFF000000,
        strokeWidth: 0,
        orderIndex: 0,
        imageUrl: url,
      );

  testWidgets('дожидается растра заливки', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fill');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/fill.png');

    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = const Color(0xFFFFC107));
      final image = await recorder.endRecording().toImage(8, 8);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      file.writeAsBytesSync(png!.buffer.asUint8List());

      final cache = CanvasImageCache(decodeSide: 64);
      final stroke = fill('file://${file.path}');
      expect(cache.imageFor(stroke), isNull, reason: 'до загрузки растра нет');
      await cache.preload([stroke], timeout: const Duration(seconds: 5));
      expect(cache.imageFor(stroke), isNotNull);
      cache.dispose();
    });
  });

  testWidgets('битая картинка не держит дольше предела', (tester) async {
    await tester.runAsync(() async {
      final cache = CanvasImageCache(decodeSide: 64);
      final started = DateTime.now();
      await cache.preload([fill('file:///нет/такого/файла.png')], timeout: const Duration(seconds: 2));
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 3)));
      cache.dispose();
    });
  });
}
