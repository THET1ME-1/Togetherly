// Выбор картинки раскраски сперва ищет уже начатый лист пары, а открывает его
// БЕЗ параметров раскраски. Передай туда `coloring:` — рисовалка заново
// заведёт раскраску (`setColoring` с пустым `coloring_done`) и сотрёт
// партнёру его «Готово» и выбранный режим.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/canvas_create_flow.dart').readAsStringSync();

  test('начатый лист ищется до того, как заводится новый', () {
    final branch = src.substring(src.indexOf('_CanvasKind.coloring) {'));
    final find = branch.indexOf('_startedSheet(');
    final create = branch.indexOf('storage.createCanvas(');
    expect(find, greaterThan(0));
    expect(create, greaterThan(find));
  });

  test('начатый лист открывается без параметров раскраски', () {
    final start = src.indexOf('if (join) {');
    expect(start, greaterThan(0));
    final end = src.indexOf('return true;', start);
    final joinOpen = src.substring(start, end);
    expect(joinOpen, contains('_open('));
    expect(joinOpen, isNot(contains('coloring:')));
  });
}
