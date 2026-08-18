// Замер цены кадра при рисовании: прежняя схема против нынешней.
//
// Файл назван без `_test`, поэтому `flutter test` его не подхватывает: это
// измерение, а не проверка. Запуск:
//   flutter test test/benchmarks/canvas_layer_bench.dart --plain-name замер
//
// Прежняя схема пересобирала картинку из ВСЕХ штрихов на каждый новый (ключом
// кэша было их число). Нынешняя держит префикс: слой сворачивается раз в
// сорок восемь штрихов, между ними рисуется только хвост.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/live_stroke_wire.dart';
import 'package:love_app/utils/stroke_layer_cache.dart';

const _size = ui.Size(1080, 1080);
const _tailLimit = 48;

DrawStroke _stroke(int i) => DrawStroke(
      id: 's$i',
      userId: 'u',
      colorValue: 0xFF223344,
      strokeWidth: 4,
      points: List.generate(
        12,
        (k) => DrawPoint(((i + k) % 100) / 100, ((i * 7 + k) % 100) / 100),
      ),
      orderIndex: i,
    );

void _paintStroke(ui.Canvas canvas, DrawStroke s) {
  final paint = ui.Paint()
    ..color = ui.Color(s.colorValue)
    ..strokeWidth = s.strokeWidth
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  final path = ui.Path();
  final first = s.points.first.toOffset(_size);
  path.moveTo(first.dx, first.dy);
  for (final p in s.points.skip(1)) {
    final o = p.toOffset(_size);
    path.lineTo(o.dx, o.dy);
  }
  canvas.drawPath(path, paint);
}

/// Прежняя схема: каждый кадр слой пересобирается целиком.
int _oldWay(List<DrawStroke> strokes, int frames) {
  final sw = Stopwatch()..start();
  for (var f = 0; f < frames; f++) {
    final recorder = ui.PictureRecorder();
    final buffer = ui.Canvas(recorder);
    final upTo = strokes.length - frames + f + 1;
    for (var i = 0; i < upTo; i++) {
      _paintStroke(buffer, strokes[i]);
    }
    recorder.endRecording().dispose();
  }
  return sw.elapsedMicroseconds;
}

/// Нынешняя: префикс лежит готовым, свежие рисуются поверх.
int _newWay(List<DrawStroke> strokes, int frames) {
  final cache = StrokeLayerCache();
  var revision = 0;
  final sw = Stopwatch()..start();
  for (var f = 0; f < frames; f++) {
    final upTo = strokes.length - frames + f + 1;
    final visible = strokes.sublist(0, upTo);
    var picture =
        cache.prefixFor(revision: revision, available: visible.length, size: _size);
    var painted = picture == null ? 0 : cache.prefixCount;
    if (picture != null && visible.length - painted > _tailLimit) {
      picture = null;
      painted = 0;
    }
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final buffer = ui.Canvas(recorder);
      for (final s in visible) {
        _paintStroke(buffer, s);
      }
      picture = recorder.endRecording();
      cache.save(picture,
          revision: revision, size: _size, prefixCount: visible.length);
      painted = visible.length;
    }
    // Кадр: выкладываем слой и дорисовываем хвост.
    final frameRecorder = ui.PictureRecorder();
    final frameCanvas = ui.Canvas(frameRecorder);
    frameCanvas.drawPicture(picture);
    for (var i = painted; i < visible.length; i++) {
      _paintStroke(frameCanvas, visible[i]);
    }
    frameRecorder.endRecording().dispose();
  }
  cache.dispose();
  return sw.elapsedMicroseconds;
}

void main() {
  test('замер веса пакетов живого мазка', () {
    const meta = LiveStrokeMeta(
      colorValue: 0xFF223344,
      strokeWidth: 4,
      isEraser: false,
      isFilledShape: false,
      shapeType: null,
    );
    // Мазок в двести точек: примерно две секунды ведения пальцем.
    final points = List.generate(
        200, (i) => DrawPoint((i % 100) / 100, (i * 7 % 100) / 100));

    var oldBytes = 0;
    // Прежняя схема: каждые 150 мс уходит весь мазок целиком.
    for (var sent = 10; sent <= points.length; sent += 10) {
      oldBytes += utf8
          .encode(jsonEncode(LiveStrokeWire.keyframe(
              sid: 's', seq: 0, points: points.sublist(0, sent), meta: meta)))
          .length;
    }

    var newBytes = 0;
    // Нынешняя: прирост каждые 40 мс, ключевой кадр раз в 150 мс.
    for (var sent = 3; sent <= points.length; sent += 3) {
      final isKeyframe = sent % 12 < 3;
      final packet = isKeyframe
          ? LiveStrokeWire.keyframe(
              sid: 's', seq: 0, points: points.sublist(0, sent), meta: meta)
          : LiveStrokeWire.increment(
              sid: 's',
              seq: 0,
              from: sent - 3,
              points: points.sublist(sent - 3, sent),
              meta: meta);
      newBytes += utf8.encode(jsonEncode(packet)).length;
    }

    // ignore: avoid_print
    print('мазок в 200 точек: было ${(oldBytes / 1024).toStringAsFixed(1)} КБ '
        'за 20 пакетов, стало ${(newBytes / 1024).toStringAsFixed(1)} КБ '
        'за 66 пакетов. Вес тот же, обновлений втрое больше: весь вес держат '
        'ключевые кадры, которые остались для сборок постарше.');
  });

  test('замер цены кадра', () {
    for (final total in [200, 1000, 3000]) {
      final strokes = List.generate(total, _stroke);
      const frames = 60;
      final oldUs = _oldWay(strokes, frames);
      final newUs = _newWay(strokes, frames);
      final perOld = (oldUs / frames / 1000).toStringAsFixed(2);
      final perNew = (newUs / frames / 1000).toStringAsFixed(2);
      final gain = (oldUs / (newUs == 0 ? 1 : newUs)).toStringAsFixed(1);
      // ignore: avoid_print
      print('$total штрихов, 60 кадров рисования: '
          'было $perOld мс на кадр, стало $perNew мс — в $gain раза дешевле');
    }
  });
}
