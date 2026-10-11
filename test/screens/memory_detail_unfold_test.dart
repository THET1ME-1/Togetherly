import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Запись из ленты открывается переходом «экран вырастает из карточки»
/// (макет https://claude.ai/artifact/Ssgdjfc37xm7TigCWy6NGC, вариант А).
///
/// Сама лента живёт на потоке PocketBase и в тесте не поднимается, поэтому
/// сверяем по исходникам то, что ломается молча: метки общих элементов в
/// карточке и на экране записи обязаны совпадать. Разъедутся — обложка просто
/// перестанет лететь, без единой ошибки.
void main() {
  final feed = File('lib/screens/memory_lane_screen.dart').readAsStringSync();
  final detail =
      File('lib/screens/memory_lane/detail.dart').readAsStringSync();

  Set<String> tags(String source) => RegExp(r"UnfoldShared\(\s*tag: '(\w+)'")
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toSet();

  test('карточка ленты — источник перехода', () {
    final tile = feed.substring(
        feed.indexOf('Widget _baseTile('), feed.indexOf('_memoryTypeColor('));
    expect(tile, contains('UnfoldSource('));
    expect(tile, contains('_showMemoryDetail(memory, from: source)'));
  });

  test('запись открывается маршрутом раскрытия, а не проявлением', () {
    final open = feed.substring(feed.indexOf('void _showMemoryDetail('),
        feed.indexOf('MEMORY ACTIONS (long press)'));
    expect(open, contains('UnfoldRoute<void>('));
    expect(open, contains('source: from'));
    expect(open, isNot(contains('PageRouteBuilder(')));
  });

  test('общие элементы названы одинаково в карточке и на экране записи', () {
    expect(tags(feed), containsAll(<String>['cover', 'avatar', 'name']));
    expect(tags(detail), containsAll(<String>['cover', 'avatar', 'name']));
  });

  test('блоки экрана записи проявляются по очереди сверху вниз', () {
    final layout = detail.substring(detail.indexOf('Widget _momentLayout('),
        detail.indexOf('Widget _momentBar('));
    final order = RegExp(r'UnfoldStagger\(\s*index: (\d)')
        .allMatches(layout)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    expect(order, isNotEmpty);
    final sorted = [...order]..sort();
    expect(order, sorted, reason: 'нижний блок не должен появляться раньше');
    expect(order.last, 5, reason: 'последним приходит тулбар');
  });
}
