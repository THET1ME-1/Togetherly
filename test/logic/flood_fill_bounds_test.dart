// Границы закрашенной области. По ним заливка обрезается до самого пятна:
// раньше на сервер уезжал прозрачный слой во весь холст — по файлу на каждый
// залитый лепесток, и все они оседали в общем хранилище.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/flood_fill.dart';

/// Рисует картинку [w]×[h] с непрозрачным прямоугольником [rect].
Future<ui.Image> _imageWithRect(int w, int h, Rect? rect) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Фон оставляем пустым (прозрачным) — как у слоя заливки.
  if (rect != null) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFF0000));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('границы совпадают с закрашенным прямоугольником', () async {
    final image = await _imageWithRect(100, 80, const Rect.fromLTWH(20, 10, 30, 25));
    final bounds = await FloodFill.opaqueBounds(image);
    image.dispose();

    expect(bounds, isNotNull);
    expect(bounds!.left, 20);
    expect(bounds.top, 10);
    expect(bounds.width, 30);
    expect(bounds.height, 25);
  });

  test('пятно у самого края не обрезается', () async {
    final image = await _imageWithRect(40, 40, const Rect.fromLTWH(0, 0, 40, 40));
    final bounds = await FloodFill.opaqueBounds(image);
    image.dispose();

    expect(bounds, const Rect.fromLTWH(0, 0, 40, 40));
  });

  test('пустой слой — null, обрезать нечего', () async {
    final image = await _imageWithRect(30, 30, null);
    final bounds = await FloodFill.opaqueBounds(image);
    image.dispose();

    expect(bounds, isNull);
  });

  test('один пиксель тоже находится', () async {
    final image = await _imageWithRect(50, 50, const Rect.fromLTWH(7, 9, 1, 1));
    final bounds = await FloodFill.opaqueBounds(image);
    image.dispose();

    expect(bounds, const Rect.fromLTWH(7, 9, 1, 1));
  });
}
