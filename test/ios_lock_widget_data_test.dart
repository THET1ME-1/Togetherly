import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Виджету экрана блокировки мало того, что его будят: ему нужны данные.
///
/// Жалоба: «виджет на экране блокировки стоит, а данных в нём нет». Будить их
/// научились 19.08.2026 (`ios_widget_kinds_reloaded_test.dart`), но три набора
/// ключей наполняются на разных экранах, и один из них — `miss_*` — писал
/// только экран настройки виджетов. Человек ставит виджет с экрана
/// блокировки, в приложении на этот экран не заходит никогда, и «Скучаю»
/// остаётся с нулями, пока не придёт тихий пуш.
///
/// Виджет блокировки ставят, не открывая приложение, поэтому его данные
/// обязаны наполняться на пути, по которому человек проходит всегда: на
/// главном экране.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Ключи App Group, которые читают виджеты экрана блокировки.
  Set<String> lockKeys() {
    final swift = read('ios/TogetherlyWidget/LockScreenWidgets.swift');
    final re = RegExp(r'"((?:together|miss|tgmood)_[^"]*)"');
    return re.allMatches(swift).map((m) => m.group(1)!).toSet();
  }

  /// Ключ вида `miss_\(g)_my_count` в Dart пишется как `miss_${g}_my_count`.
  String dartKey(String swiftKey) =>
      swiftKey.replaceAll(r'\(g)', r'${g}');

  test('каждый ключ виджетов блокировки кто-то пишет в приложении', () {
    final dart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final keys = lockKeys();
    expect(keys.length, greaterThanOrEqualTo(12),
        reason: 'разобрано подозрительно мало ключей: ${keys.length}');

    final orphans =
        keys.map(dartKey).where((k) => !dart.contains("'$k'")).toList();
    expect(orphans, isEmpty,
        reason: 'эти ключи виджет читает, но никто не пишет: $orphans');
  });

  test('данные всех трёх виджетов блокировки наполняются с главного экрана',
      () {
    // Что зовёт главный экран напрямую и через каталожный синк.
    final fromHome = read('lib/screens/home_screen.dart') +
        read('lib/services/catalog_widget_sync.dart');

    // syncTogether → together_*, syncMoodTiles → tgmood_*, syncMiss → miss_*.
    for (final entry in {
      'syncTogether': 'together_* (дни вместе)',
      'syncMoodTiles': 'tgmood_* (настроение)',
      'syncMiss': 'miss_* (скучаю)',
    }.entries) {
      expect(fromHome.contains('${entry.key}('), isTrue,
          reason: 'с главного экрана не наполняется ${entry.value}: '
              '${entry.key} зовут только другие экраны, и виджет блокировки '
              'стоит пустой у того, кто туда не заходит');
    }
  });

  test('пустые данные виджет объясняет словами, а не нулями', () {
    final swift = read('ios/TogetherlyWidget/LockScreenWidgets.swift');
    // Отличить «приложение ещё ни разу не записало данные» от «данные есть,
    // но они нулевые» можно только по отсутствию самого ключа.
    expect(swift.contains('stringOrNil('), isTrue,
        reason: 'виджет блокировки не отличает «данных нет» от «ноль», '
            'и человек видит 0 там, где надо просить открыть приложение');
  });
}
