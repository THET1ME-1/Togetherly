import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож рассылки: на что подписан клиент, то обязана публиковать сборка.
///
/// Рассылка изменений живёт не в `pb_hooks`, а в самой сборке PocketBase —
/// словарь `rtCollections` в `pocketbase/pb-cgo/main.go` (перенесено 14.08.2026,
/// когда исполнение JS съедало четверть процессора). Коллекции, которой там
/// нет, события в канал `pair:<groupId>` не уходят вовсе, и это молчаливая
/// поломка: подписка на клиенте живёт, экран не обновляется никогда.
///
/// Так и вышло с `watch_videos`: раздел «Смотрим» читал список один раз, при
/// входе, и залитый партнёром ролик у второго не появлялся — жалоба «поставил
/// видео, а партнёр не видит его» (16.08.2026).
void main() {
  test('каждая подписка клиента объявлена в rtCollections сборки', () {
    final main = File('pocketbase/pb-cgo/main.go').readAsStringSync();

    final block = RegExp(
      r'var rtCollections = map\[string\]bool\{([\s\S]*?)\}',
    ).firstMatch(main);
    expect(
      block,
      isNotNull,
      reason:
          'В main.go не нашёлся словарь rtCollections — сборка могла '
          'разъехаться с этим тестом.',
    );

    final published = RegExp(
      '"([a-z_]+)"\\s*:\\s*true',
    ).allMatches(block!.group(1)!).map((m) => m.group(1)!).toSet();
    expect(published, isNotEmpty);

    // Обёртки живых списков: имя коллекции первым аргументом, канал — в
    // `rtChannel`. Берём только те, что реально просят канал: остальные
    // работают на разовом чтении и рассылки не требуют.
    final source = File(
      'lib/services/pb_realtime_service.dart',
    ).readAsStringSync();
    final subscribed = <String>{};
    for (final m in RegExp(
      r"watchList\(\s*'([a-z_]+)'([\s\S]{0,700}?)\);",
    ).allMatches(source)) {
      if (!m.group(2)!.contains('rtChannel')) continue;
      subscribed.add(m.group(1)!);
    }
    expect(
      subscribed,
      isNotEmpty,
      reason:
          'Ни одной подписки не нашлось — проверь, не поменялась ли '
          'форма обёрток watchList.',
    );

    final missing = subscribed.difference(published).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'Клиент подписан на эти коллекции, а сборка PocketBase их не '
          'публикует: $missing. Дописать в rtCollections в '
          'pocketbase/pb-cgo/main.go и пересобрать бинарь, иначе экран не '
          'обновится никогда и в журнале не будет ни одной ошибки.',
    );
  });
}
