// SKAdNetwork: через эти идентификаторы рекламодатель засчитывает установки,
// пришедшие с рекламы на iPhone. Яндекс: «Otherwise, some of the conversions
// will be lost, which may impact your ad revenue» (boost.yandex.com, раздел
// SKAdNetwork). До 22.10.2026 в Info.plist не было ни одного.
//
// Список — https://yastatic.net/pcode-static/skadnetwork/skadids.json.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  List<String> skadIds() {
    final start = plist.indexOf('<key>SKAdNetworkItems</key>');
    if (start < 0) return const [];
    final end = plist.indexOf('</array>', start);
    return RegExp(r'<string>([^<]+)</string>')
        .allMatches(plist.substring(start, end))
        .map((m) => m.group(1)!)
        .toList();
  }

  test('Info.plist объявляет сети SKAdNetwork Яндекса', () {
    final ids = skadIds();
    expect(ids, contains('zq492l623r.skadnetwork'),
        reason: 'нет собственной сети Яндекса');
    expect(ids.length, greaterThanOrEqualTo(200),
        reason: 'список Яндекса короче, чем был на 22.10.2026 (228)');
  });

  test('идентификаторы целые и не повторяются', () {
    final ids = skadIds();
    final bad = ids
        .where((id) => !RegExp(r'^[a-z0-9]{10}\.skadnetwork$').hasMatch(id))
        .toList();
    expect(bad, isEmpty);
    expect(ids.toSet().length, ids.length);
  });
}
