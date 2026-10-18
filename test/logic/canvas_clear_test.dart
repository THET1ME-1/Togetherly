// Метка очистки в мете холста стирает картинку, только если холст очистили
// при открытом экране. Обращение 294 (18.10.2026): лист раскраски при
// повторном входе открывался пустым, хотя на сервере лежали 1279 линий. Холст
// когда-то очищали, и первая мета после входа считалась свежей очисткой:
// если штрихи успевали прийти раньше неё, экран стирал их у себя.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/canvas_clear.dart';

void main() {
  test('первая мета после входа ничего не стирает', () {
    expect(
      clearWipesCanvas(metaSeen: false, seen: null, incoming: 1792316752772),
      isFalse,
    );
  });

  test('очистка при открытом экране стирает', () {
    expect(
      clearWipesCanvas(
          metaSeen: true, seen: 1792316752772, incoming: 1792330000000),
      isTrue,
    );
    expect(
      clearWipesCanvas(metaSeen: true, seen: null, incoming: 1792330000000),
      isTrue,
      reason: 'первая очистка холста, который раньше не чистили',
    );
  });

  test('прежняя метка и пустая мета не стирают', () {
    expect(
      clearWipesCanvas(
          metaSeen: true, seen: 1792316752772, incoming: 1792316752772),
      isFalse,
    );
    expect(
      clearWipesCanvas(metaSeen: true, seen: 1792316752772, incoming: null),
      isFalse,
    );
  });

  test('экран рисования решает очистку через clearWipesCanvas', () {
    final src = File('lib/screens/draw_screen.dart').readAsStringSync();
    final start = src.indexOf('void _onCanvasMeta(');
    expect(start, greaterThan(0));
    final body = src.substring(start, src.indexOf('bool bgChanged', start));
    expect(body, contains('clearWipesCanvas('));
    expect(body, contains('_canvasMetaSeen = true'));
  });
}
