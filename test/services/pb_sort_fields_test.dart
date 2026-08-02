import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сортировка по полю, которого нет в коллекции, — это 400 от PocketBase на
/// каждый запрос. Ловится такое плохо: вызовы обёрнуты в `catch`, экран молча
/// показывает пустоту, а в журнал сервера сыплется «invalid sort field».
/// Так `watch_videos_service` сортировал `memories` по `created`, которого у
/// коллекции нет (там `created_at`), — 2298 отказов за сутки, и видео-
/// воспоминания не появлялись в комнате просмотра вообще никогда.
///
/// Тест сверяет каждый `sort:` в `lib/` со схемой `collections_schema.json`.
/// Коллекции, которой в схеме нет, он не касается: судить о ней не по чему.
void main() {
  test('sort ссылается только на существующие поля коллекции', () {
    final schemaFile = File('pocketbase/collections_schema.json');
    expect(schemaFile.existsSync(), isTrue,
        reason: 'нет pocketbase/collections_schema.json');

    final decoded = jsonDecode(schemaFile.readAsStringSync());
    final collections = decoded is List
        ? decoded
        : (decoded['collections'] as List? ?? const []);

    final fieldsOf = <String, Set<String>>{};
    for (final raw in collections) {
      final col = raw as Map<String, dynamic>;
      final fields = (col['fields'] ?? col['schema'] ?? const []) as List;
      fieldsOf[col['name'] as String] = {
        for (final f in fields) (f as Map<String, dynamic>)['name'] as String,
        'id', // системное, в схеме не перечисляется
      };
    }

    final callRe = RegExp(r"""collection\(\s*'([a-z_]+)'\s*\)""");
    final sortRe = RegExp(r"""sort:\s*'([^']+)'""");

    final problems = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Строчные комментарии гасим пробелами: разбор в них тоже поминает
      // поля сортировки, и тест ловил бы описание бага вместо самого бага.
      // Пробелы вместо вырезания — чтобы не съехали номера строк.
      final source = entity.readAsStringSync().replaceAllMapped(
            RegExp(r'//[^\n]*'),
            (m) => ' ' * m.group(0)!.length,
          );

      for (final call in callRe.allMatches(source)) {
        final name = call.group(1)!;
        final known = fieldsOf[name];
        if (known == null) continue;

        // Окно = ровно этот вызов: от имени коллекции до его закрывающей
        // скобки. Без границы регулярка цепляет `sort:` соседнего метода.
        final tail = source.substring(call.end);
        final end = tail.indexOf(');');
        final call_ = end == -1 ? tail : tail.substring(0, end);

        for (final sort in sortRe.allMatches(call_)) {
          for (final part in sort.group(1)!.split(',')) {
            final field = part.trim().replaceFirst(RegExp(r'^[-+]'), '');
            if (field.isEmpty || field.startsWith('@')) continue;
            if (known.contains(field)) continue;

            final line = '\n'.allMatches(source.substring(0, call.start)).length + 1;
            problems.add(
              '${entity.path}:$line — коллекция «$name» сортируется по «$field», '
              'такого поля в схеме нет',
            );
          }
        }
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
