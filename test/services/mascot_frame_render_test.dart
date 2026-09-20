import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/services/mascot/mascot_frame_render.dart';

/// Атлас-полосатик: у каждой строки свой цвет, поэтому по цвету кадра видно,
/// какую именно строку взял рендер.
Future<ui.Image> _stripedSheet({
  required int frame,
  required int cols,
  required int rows,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var r = 0; r < rows; r++) {
    canvas.drawRect(
      Rect.fromLTWH(0, (r * frame).toDouble(), (cols * frame).toDouble(), frame.toDouble()),
      Paint()..color = _rowColor(r),
    );
  }
  return recorder.endRecording().toImage(cols * frame, rows * frame);
}

Color _rowColor(int row) => Color.fromARGB(255, 10 + row * 20, 40 + row * 5, 200 - row * 15);

MascotAnim _anim({
  required List<String> rows,
  String nightIdle = '',
  Map<int, int> levelOffsets = const {3: 0, 1: 9, 2: 18},
  int frame = 48,
}) =>
    MascotAnim(
      id: 'test',
      nameRu: 'Тест',
      nameEn: 'Test',
      sheetUrl: 'https://example.invalid/sheet.png',
      frame: frame,
      cols: 12,
      fps: 9,
      rows: rows,
      levelOffsets: levelOffsets,
      nightIdle: nightIdle,
    );

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

Future<Color> _pixel(Uint8List png, int x, int y) async {
  final image = await _decode(png);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  final bytes = data!.buffer.asUint8List();
  image.dispose();
  return Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

Future<Size> _size(Uint8List png) async {
  final image = await _decode(png);
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  return size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const standardRows = ['live', 'grow', 'freeze', 'sad', 'happy', 'grab', 'drag', 'drop', 'resize'];

  test('день, ночь и грусть берутся из разных строк атласа', () async {
    final sheet = await _stripedSheet(frame: 48, cols: 12, rows: 27);
    final anim = _anim(rows: [...standardRows, 'sleep'], nightIdle: 'sleep');

    final frames = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 3,
      now: DateTime(2026, 9, 20, 12),
    );

    expect(await _pixel(frames[MascotWidgetFrame.day]!, 4, 4), _rowColor(0));
    expect(await _pixel(frames[MascotWidgetFrame.night]!, 4, 4), _rowColor(9));
    expect(await _pixel(frames[MascotWidgetFrame.sad]!, 4, 4), _rowColor(3));
    sheet.dispose();
  });

  test('кадр выходит размером со сторону атласного кадра', () async {
    final sheet = await _stripedSheet(frame: 48, cols: 12, rows: 27);
    final anim = _anim(rows: standardRows);

    final frames = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 3,
      now: DateTime(2026, 9, 20, 12),
    );

    expect(await _size(frames[MascotWidgetFrame.day]!), const Size(48, 48));
    sheet.dispose();
  });

  test('ступень сдвигает строку на свой блок', () async {
    final sheet = await _stripedSheet(frame: 48, cols: 12, rows: 27);
    final anim = _anim(rows: standardRows);

    final baby = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 1,
      now: DateTime(2026, 9, 20, 12),
    );
    final teen = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 2,
      now: DateTime(2026, 9, 20, 12),
    );

    expect(await _pixel(baby[MascotWidgetFrame.day]!, 4, 4), _rowColor(9));
    expect(await _pixel(teen[MascotWidgetFrame.day]!, 4, 4), _rowColor(18));
    sheet.dispose();
  });

  test('без ночной строки ночного кадра нет', () async {
    final sheet = await _stripedSheet(frame: 48, cols: 12, rows: 27);
    final anim = _anim(rows: standardRows);

    final frames = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 3,
      now: DateTime(2026, 9, 20, 12),
    );

    expect(frames.containsKey(MascotWidgetFrame.night), isFalse);
    expect(frames.containsKey(MascotWidgetFrame.day), isTrue);
    sheet.dispose();
  });

  test('без строки грусти грустного кадра нет', () async {
    final sheet = await _stripedSheet(frame: 48, cols: 12, rows: 27);
    final anim = _anim(rows: ['live', 'grow', 'happy']);

    final frames = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 3,
      now: DateTime(2026, 9, 20, 12),
    );

    expect(frames.containsKey(MascotWidgetFrame.sad), isFalse);
    sheet.dispose();
  });

  test('сезонный наряд попадает в дневной кадр', () async {
    final sheet = await _stripedSheet(frame: 48, cols: 12, rows: 27);
    final anim = MascotAnim(
      id: 'sezonnik',
      nameRu: 'Сезонник',
      nameEn: 'Seasonal',
      sheetUrl: 'https://example.invalid/sheet.png',
      frame: 48,
      cols: 12,
      fps: 9,
      rows: [...standardRows, 'winter'],
      levelOffsets: const {3: 0, 1: 9, 2: 18},
      seasonIdles: const {1: 'winter'},
    );

    final january = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 3,
      now: DateTime(2026, 1, 15, 12),
    );

    expect(await _pixel(january[MascotWidgetFrame.day]!, 4, 4), _rowColor(9));
    sheet.dispose();
  });

  test('кадр 96 отдаётся своим размером', () async {
    final sheet = await _stripedSheet(frame: 96, cols: 12, rows: 14);
    final anim = _anim(
      rows: [...standardRows, 'cuckoo', 'front', 'swing', 'wind', 'sleep'],
      nightIdle: 'sleep',
      levelOffsets: const {3: 0, 1: 14, 2: 28},
      frame: 96,
    );

    final frames = await renderMascotWidgetFrames(
      sheet: sheet,
      anim: anim,
      level: 3,
      now: DateTime(2026, 9, 20, 12),
    );

    expect(await _size(frames[MascotWidgetFrame.day]!), const Size(96, 96));
    sheet.dispose();
  });
}
