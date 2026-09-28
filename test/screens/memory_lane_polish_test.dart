import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Шлифовка ленты воспоминаний (28.09.2026): цвета только из темы, листы
/// только общие, мёртвой старой карточки нет. Белый и чёрный поверх фото и
/// видео (затемнение, значки на кадре) разрешены — там они к месту.
void main() {
  final src = File('lib/screens/memory_lane_screen.dart').readAsStringSync();

  test('в ленте нет вшитых цветов мимо темы', () {
    final hits = RegExp(r'Colors\.(red|grey|green|blue|amber|orange|pink|purple)')
        .allMatches(src)
        .map((m) => m.group(0))
        .toList();
    expect(hits, isEmpty);
  });

  test('листы открываются общим showAppSheet', () {
    expect(src, isNot(contains('showModalBottomSheet(')));
  });

  test('старой карточки и её сирот больше нет', () {
    expect(src, isNot(contains('_showMemoryDetailLEGACY')));
    expect(src, isNot(contains('Widget _mediaCollage(')));
  });
}
