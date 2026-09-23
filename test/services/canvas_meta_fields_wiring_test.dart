import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Запись о холсте (`canvas_meta`) живёт в hotpath, и поле, которого нет в его
/// карте `COLLECTIONS["canvas_meta"]`, выбрасывается МОЛЧА: ответ 200, запись
/// без поля. Так контур своей раскраски (`coloring_outline`) ни разу не доехал
/// до партнёра: на проде к 23.09.2026 51 своя раскраска, колонки не было, и
/// второму доставался пустой лист без контура.
void main() {
  final hotpath = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
  final block = hotpath.split('"canvas_meta": {')[1].split('"sortable"')[0];

  test('каждое поле, которое приложение пишет в canvas_meta, знает hotpath', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    final body = src
        .split('Future<bool> upsertCanvasMeta(')[1]
        .split("_upsertByFilter('canvas_meta'")[0];
    final keys = RegExp(r"body\['([a-z_]+)'\]")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet()
      ..addAll(RegExp(r"'([a-z_]+)'\s*:").allMatches(body).map((m) => m.group(1)!));
    expect(keys, contains('coloring_outline'),
        reason: 'сканер разучился находить поля записи');
    for (final k in keys) {
      expect(block, contains('"$k"'),
          reason: 'hotpath выбросит $k молча — добавь в COLLECTIONS и в Postgres');
    }
  });

  test('колонка контура заведена миграцией Postgres', () {
    final sql =
        File('pocketbase/hotpath/canvas_meta_outline.sql').readAsStringSync();
    expect(sql, contains('coloring_outline'));
  });
}
