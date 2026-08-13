import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connections_manager.dart';

/// Активный индекс переживает любую перестройку списка связей.
///
/// 6 августа 2026 уборка устаревших связей писала `_connections.length - 1` при
/// пустом списке, то есть −1, и следующее обращение к активной связи роняло
/// приложение: `RangeError (length): Invalid value: Not in inclusive range
/// 0..1: -1`. За два часа 185 падений на 1.24.0+166.
void main() {
  group('clampedActiveIndex', () {
    test('индекс внутри списка остаётся собой', () {
      expect(clampedActiveIndex(1, 3), 1);
      expect(clampedActiveIndex(0, 1), 0);
    });

    test('пустой список не даёт отрицательного индекса', () {
      expect(clampedActiveIndex(0, 0), 0);
      expect(clampedActiveIndex(5, 0), 0);
    });

    test('отрицательный индекс приводится к первой связи', () {
      expect(clampedActiveIndex(-1, 1), 0);
      expect(clampedActiveIndex(-1, 2), 0);
    });

    test('за верхней границей при единственной связи — она сама', () {
      expect(clampedActiveIndex(3, 1), 0);
    });

    test('за верхней границей при нескольких — первая после соло', () {
      expect(clampedActiveIndex(9, 4), 1);
    });
  });

  group('незащищённых обращений по индексу не осталось', () {
    test('никто не индексирует список сырым активным индексом', () {
      final src = File('lib/models/connections_manager.dart').readAsStringSync();
      // Разрешено ровно одно место — сам clampedActiveIndex внутри выражения.
      final raw = RegExp(r'_connections\[_activeConnectionIndex\]').allMatches(src).length;
      expect(
        raw,
        0,
        reason: 'обращение по сырому индексу падает, когда он −1: '
            'так ронялось приложение и в августе, и в ночь на 14-е',
      );
    });

    test('активный индекс не получает −1 от indexOf', () {
      final src = File('lib/models/connections_manager.dart').readAsStringSync();
      expect(
        src.contains('_activeConnectionIndex = _connections.indexOf('),
        isFalse,
        reason: 'indexOf отдаёт −1, когда связи в списке уже нет',
      );
    });
  });
}
