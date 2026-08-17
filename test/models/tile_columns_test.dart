// Плитки не оставляют пустого места справа.
//
// Жалоба 17.08.2026 со снимка экрана «Скучаю»: «если экран меньше, чем надо, они
// все в ряд, а справа место пустое». Чипы лежали в Wrap и сохраняли свою ширину:
// два рядом не влезали, а один занимал половину строки — остальное пустовало.
//
// Правило: считаем, сколько плиток заданной минимальной ширины влезает, и делим
// ширину между ними ровно. Одна плитка в строке растягивается на всю ширину, и
// пустоты не остаётся ни на узком экране, ни на планшете.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/tile_columns.dart';

void main() {
  test('узкий телефон: одна колонка на всю ширину', () {
    expect(tileColumns(width: 328, minTileWidth: 190), 1);
    expect(tileWidth(width: 328, columns: 1, spacing: 7), 328);
  });

  test('обычный телефон: две колонки', () {
    expect(tileColumns(width: 392, minTileWidth: 190), 2);
    expect(tileWidth(width: 392, columns: 2, spacing: 7), closeTo(192.5, 0.01));
  });

  test('планшет: три и больше', () {
    expect(tileColumns(width: 700, minTileWidth: 190), 3);
    expect(tileColumns(width: 1000, minTileWidth: 190), 5);
  });

  test('колонок не больше предела', () {
    expect(tileColumns(width: 2000, minTileWidth: 190, maxColumns: 3), 3);
  });

  test('нулевая и отрицательная ширина не роняют расчёт', () {
    expect(tileColumns(width: 0, minTileWidth: 190), 1);
    expect(tileColumns(width: -50, minTileWidth: 190), 1);
    expect(tileWidth(width: 0, columns: 1, spacing: 7), 0);
  });

  test('плитка никогда не выходит за ширину', () {
    for (final w in [200.0, 300.0, 360.0, 411.0, 480.0, 768.0]) {
      final n = tileColumns(width: w, minTileWidth: 190);
      final tile = tileWidth(width: w, columns: n, spacing: 7);
      expect(tile * n + 7 * (n - 1), lessThanOrEqualTo(w + 0.01),
          reason: 'при ширине $w плитки не должны переполнять строку');
    }
  });
}
