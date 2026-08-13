import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож общих ключей приложения и виджет-расширения.
///
/// Виджет читает App Group по строковому ключу. Если приложение такой ключ не
/// пишет, виджет молча остаётся пустым — ни ошибки, ни лога, а на Linux этого
/// не видно вовсе. Так уже было дважды: `ios_love_*` и `ios_days_*` читались, а
/// не писались (эмодзи и аватары не появлялись), и так же — до 13 августа
/// 2026 — жили все четыре фото-виджета: белый прямоугольник вместо снимка.
void main() {
  final swiftFiles = Directory('ios/TogetherlyWidget')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.swift'))
      .toList();

  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  test('каждый ключ ios_* из расширения пишется приложением', () {
    final key = RegExp(r'"(ios_[a-z0-9_]+)');
    final missing = <String>[];
    final seen = <String>{};

    for (final file in swiftFiles) {
      final name = file.uri.pathSegments.last;
      for (final line in file.readAsLinesSync()) {
        final code = line.trimLeft();
        // Комментарии описывают историю ключей, в том числе снятых.
        if (code.startsWith('//')) continue;
        for (final m in key.allMatches(line)) {
          final k = m.group(1)!;
          seen.add(k);
          // `ios_photo_grid_` собирается с индексом — префикса достаточно.
          if (dart.contains(k)) continue;
          missing.add('$name: $k');
        }
      }
    }

    // Пустой список ключей означал бы, что тест ничего не проверил: разбор
    // исходников сломался, и сторож молча пропустил бы всё.
    expect(seen.length, greaterThanOrEqualTo(8),
        reason: 'Ключи ios_* в расширении не нашлись — проверьте разбор');
    expect(missing, isEmpty,
        reason: 'Расширение ждёт этих ключей, а Dart их не пишет:\n'
            '${missing.join('\n')}');
  });
}
