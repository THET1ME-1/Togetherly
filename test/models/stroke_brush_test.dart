import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_replay.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/stroke_brush.dart';
import 'package:love_app/models/stroke_transform.dart';

DrawStroke _stroke({StrokeBrush brush = StrokeBrush.pen}) => DrawStroke(
      id: 's1',
      clientId: 'c1',
      userId: 'u',
      colorValue: 0xFFFF0000,
      strokeWidth: 8,
      points: const [DrawPoint(0.1, 0.1), DrawPoint(0.5, 0.5), DrawPoint(0.9, 0.2)],
      orderIndex: 3,
      layer: 1,
      brush: brush,
    );

void main() {
  test('кисть читается по имени, незнакомая и пустая — перо', () {
    expect(parseStrokeBrush('marker'), StrokeBrush.marker);
    expect(parseStrokeBrush('calligraphy'), StrokeBrush.calligraphy);
    expect(parseStrokeBrush(null), StrokeBrush.pen);
    expect(parseStrokeBrush('glitter'), StrokeBrush.pen);
  });

  test('перо в карту не пишется: старые и новые рисунки одинаковы', () {
    expect(_stroke().toFirestore().containsKey('brush'), isFalse);
    expect(_stroke(brush: StrokeBrush.pencil).toFirestore()['brush'], 'pencil');
  });

  test('кисть переживает круг через базу и через живую карту', () {
    final saved = _stroke(brush: StrokeBrush.airbrush).toFirestore();
    expect(DrawStroke.fromFirestore(saved, 'x').brush, StrokeBrush.airbrush);
    expect(DrawStroke.fromFirestore({'points': []}, 'x').brush, StrokeBrush.pen);

    final live = _stroke(brush: StrokeBrush.marker).toLiveMap();
    expect(DrawStroke.fromLiveMap(live, 'u').brush, StrokeBrush.marker);
  });

  test('мягкий ластик кладётся аэрографом, твёрдый — пером', () {
    expect(brushForEraser(EraserMode.hard), StrokeBrush.pen);
    expect(brushForEraser(EraserMode.soft), StrokeBrush.airbrush);
    expect(parseEraserMode('soft'), EraserMode.soft);
    expect(parseEraserMode('whole'), EraserMode.whole);
    expect(parseEraserMode(null), EraserMode.hard);
  });

  test('зерно кисти одинаково везде: FNV-1a от ключа', () {
    // Контрольное значение FNV-1a 32 для «abc».
    expect(brushSeedFor('abc'), 0x1A47E90B);
    expect(brushSeedFor('abc'), brushSeedFor('abc'));
    expect(brushSeedFor('abc'), isNot(brushSeedFor('abd')));
    expect(_stroke().brushSeed, brushSeedFor('c1'));
  });

  test('копии штриха не теряют кисть', () {
    final s = _stroke(brush: StrokeBrush.calligraphy);
    expect(strokeWithPoints(s, s.points).brush, StrokeBrush.calligraphy);
    expect(copyImageStroke(s, x: 0.3).brush, StrokeBrush.calligraphy);
    final partial = strokesUpTo([s], 2).single;
    expect(partial.points.length, 2);
    expect(partial.brush, StrokeBrush.calligraphy);
  });

  test('каждая сборка мазка в холсте передаёт кисть', () {
    // Копия, собранная руками, теряет поле молча: маркер после отмены,
    // зеркала или повтора стал бы пером. Сторожим все места разом.
    final files = [
      ...Directory('lib/models')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];
    final missing = <String>[];
    for (final file in files) {
      final src = file.readAsStringSync();
      var at = src.indexOf('DrawStroke(');
      while (at >= 0) {
        final block = _callBlock(src, at + 'DrawStroke'.length);
        if (block.contains('isEraser:') && !block.contains('brush:')) {
          final line = '\n'.allMatches(src.substring(0, at)).length + 1;
          missing.add('${file.path}:$line');
        }
        at = src.indexOf('DrawStroke(', at + 1);
      }
    }
    expect(missing, isEmpty, reason: 'без brush: $missing');
  });
}

/// Текст вызова от открывающей скобки до парной закрывающей.
String _callBlock(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return src.substring(open);
}
