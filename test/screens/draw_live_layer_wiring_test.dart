import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Холст шлёт слой в каждом живом пакете и кладёт мазки партнёра в их слой.
///
/// Разъедутся — линия партнёра снова окажется не в своём слое, а молчит это
/// без единой ошибки (20.10.2026, «криво работают слои»).
void main() {
  final source = File('lib/screens/draw_screen.dart').readAsStringSync();

  String body(String start) {
    final from = source.indexOf(start);
    expect(from, greaterThanOrEqualTo(0), reason: 'нет «$start»');
    return source.substring(from, from + 900);
  }

  test('живые пакеты несут слой мазка', () {
    expect(body('LiveStrokeMeta _liveMeta() => LiveStrokeMeta('), contains('layer: _activeLayer'));
    expect(body('Future<void> _pushLiveDone(DrawStroke stroke)'), contains('layer: stroke.layer'));
  });

  test('мазок партнёра без слоя встаёт в верхний слой, как раньше', () {
    expect(source, contains('assembler.buildStroke(uid, fallbackLayer: _topLayer)'));
    expect(source, contains('assembler.buildLive(uid, fallbackLayer: _topLayer)'));
  });
}
