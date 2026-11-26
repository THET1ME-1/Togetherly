import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree_geometry.dart';

/// Порт геометрии 2,5D-ёлки (мастерская, `xmas_tree3d.js`) обязан отвечать
/// так же, как рисунок: иначе игрушка, повешенная на ветку, ляжет в приложении
/// мимо хвои. Эталон снят node-скриптом из JS (`test/fixtures/xmas_tree_geometry.json`).
void main() {
  final cases = (jsonDecode(File('test/fixtures/xmas_tree_geometry.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('эталон не пустой: есть точки на хвое и мимо', () {
    expect(cases.length, 320);
    expect(cases.where((c) => c['can'] == true).length, greaterThan(40));
    expect(cases.where((c) => c['can'] == false).length, greaterThan(40));
  });

  test('«можно ли повесить» совпадает с рисунком во всех точках', () {
    final wrong = [
      for (final c in cases)
        if (xtCanHang(c['kind'] as String, (c['x'] as num).toDouble(), (c['y'] as num).toDouble()) != c['can'])
          '${c['kind']} ${c['x']} ${c['y']}',
    ];
    expect(wrong, isEmpty);
  });

  test('точка подвеса на хвое совпадает с рисунком', () {
    for (final c in cases) {
      final kind = c['kind'] as String;
      final a = xtAnchor(kind, (c['x'] as num).toDouble(), (c['y'] as num).toDouble());
      final want = c['hang'] as Map<String, dynamic>?;
      if (want == null) {
        expect(a, isNull, reason: '$kind ${c['x']} ${c['y']}');
        continue;
      }
      expect(a, isNotNull, reason: '$kind ${c['x']} ${c['y']}');
      final h = xtHangPoint(kind, a!);
      expect(h.tier, want['tier']);
      expect(h.screen.dx, closeTo((want['sx'] as num).toDouble(), 0.05));
      expect(h.screen.dy, closeTo((want['sy'] as num).toDouble(), 0.05));
      expect(h.visible, closeTo((want['vis'] as num).toDouble(), 0.01));
    }
  });

  test('масштаб игрушки растёт к зрителю', () {
    final front = xtAnchor('fir', 50, 70)!;
    final h = xtHangPoint('fir', front);
    expect(h.scale, greaterThan(0.15));
    expect(h.scale, lessThan(0.17));
  });
}
