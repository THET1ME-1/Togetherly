import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RemoteViews бросает исключение на действии с id, которого нет в разметке, и
/// лончер вместо виджета рисует серую плашку «Невозможно загрузить виджет».
/// Разметки «Кольца года» переписаны 14.09.2026, поэтому сверяем: каждый id,
/// который трогает провайдер, есть в той разметке, для которой он его трогает.
void main() {
  final provider = File(
    'android/app/src/main/kotlin/com/togetherly/love/YearRingWidgetProvider.kt',
  ).readAsStringSync();

  Set<String> idsIn(String src) =>
      RegExp(r'R\.id\.(\w+)').allMatches(src).map((m) => m.group(1)!).toSet();

  Set<String> layoutIds(String name) => RegExp(r'@\+id/(\w+)')
      .allMatches(
        File('android/app/src/main/res/layout/$name.xml').readAsStringSync(),
      )
      .map((m) => m.group(1)!)
      .toSet();

  String body(String fun) {
    final start = provider.indexOf('private fun $fun(');
    expect(start, greaterThan(-1), reason: 'нет функции $fun');
    final end = provider.indexOf('\n    private fun ', start + 1);
    return provider.substring(start, end < 0 ? provider.length : end);
  }

  test('4×2 трогает только свои id', () {
    final missing = idsIn(body('renderMedium')).difference(layoutIds('tg_ring_4x2'));
    expect(missing, isEmpty, reason: 'нет в tg_ring_4x2.xml: $missing');
  });

  test('2×2 трогает только свои id', () {
    final missing = idsIn(body('renderSmall')).difference(layoutIds('tg_ring_2x2'));
    expect(missing, isEmpty, reason: 'нет в tg_ring_2x2.xml: $missing');
  });

  test('общая часть есть в обеих разметках', () {
    final common = idsIn(body('render'));
    for (final layout in ['tg_ring_4x2', 'tg_ring_2x2']) {
      final missing = common.difference(layoutIds(layout));
      expect(missing, isEmpty, reason: 'нет в $layout.xml: $missing');
    }
  });
}
