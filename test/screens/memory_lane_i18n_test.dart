// Лента воспоминаний говорит на всех семи языках (19.09.2026).
//
// Десять строк ленты были зашиты выбором `_ru ? 'Всё' : 'All'`: немец,
// француз и остальные видели английское «All», «No favorites yet» и плашки
// типов «Moment», «Note». Теперь всё идёт через словарь.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('в ленте нет выбора «русский или английский»', () {
    final files = [
      File('lib/screens/memory_lane_screen.dart'),
      ...Directory('lib/screens/memory_lane')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];
    final offenders = <String>[];
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'_ru\s*\?').hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('новые строки ленты есть на семи языках', () {
    final dict = File('lib/l10n/dict/memory_lane_feed.dart').readAsStringSync();
    for (final key in [
      'feedFilterAll',
      'feedNoFavorites',
      'feedNoneInCategory',
      'feedFavoritesHint',
      'memBadgeMoment',
      'memBadgeVideo',
      'memBadgeNote',
      'memBadgeBook',
      'memBadgeMovie',
    ]) {
      final at = dict.indexOf("'$key'");
      expect(at, isPositive, reason: 'нет ключа $key');
      final block = dict.substring(at, dict.indexOf('},', at));
      for (final lang in ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt']) {
        expect(block.contains("'$lang':"), isTrue, reason: '$key без $lang');
      }
    }
  });
}
