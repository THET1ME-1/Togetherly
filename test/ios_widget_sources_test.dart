import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож сборки iOS-расширения.
///
/// Файл, лежащий в `ios/TogetherlyWidget`, сам в сборку не попадает: его надо
/// прописать в `project.pbxproj` тремя строками — ссылкой, членством в группе и
/// шагом Sources. Забыть один из трёх легко, а расплата дорогая: на Linux
/// проверить нечем, ошибка всплывает через двадцать минут на CI, и виджет
/// молча отсутствует в собранном приложении.
void main() {
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
  final widgetDir = Directory('ios/TogetherlyWidget');

  test('каждый Swift-файл виджета включён в таргет расширения', () {
    final project = pbxproj.readAsStringSync();
    final sources = _sourcesPhase(project);

    final missing = <String>[];
    for (final file in widgetDir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.swift')) continue;
      if (!project.contains('path = $name;') || !sources.contains(name)) {
        missing.add(name);
      }
    }

    expect(missing, isEmpty,
        reason: 'Не попадут в сборку расширения: ${missing.join(', ')}');
  });

  test('каждый виджет бандла объявлен в исходниках', () {
    final bundle =
        File('ios/TogetherlyWidget/TogetherlyWidgetBundle.swift').readAsStringSync();
    final swift = widgetDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.swift'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    // Строки вида «TogetherWidget()» внутри @WidgetBundleBuilder.
    final declared = RegExp(r'^\s{8}([A-Za-z]+Widget[A-Za-z]*)\(\)\s*$',
            multiLine: true)
        .allMatches(bundle)
        .map((m) => m.group(1)!)
        .toSet();

    expect(declared, isNotEmpty, reason: 'Бандл не разобрался — проверьте отступы');

    final undefined = declared
        .where((name) => !swift.contains('struct $name: Widget'))
        .toList();
    expect(undefined, isEmpty,
        reason: 'В бандле есть, в коде нет: ${undefined.join(', ')}');
  });
}

/// Тело шага Sources у таргета расширения.
String _sourcesPhase(String project) {
  // Именно с ` = {`: тот же идентификатор встречается раньше, в списке
  // buildPhases таргета, и поиск по голому имени приводил в пустой блок.
  final start = project.indexOf('FE000000000000000000F002 /* Sources */ = {');
  if (start < 0) return '';
  final end = project.indexOf('};', start);
  return end < 0 ? '' : project.substring(start, end);
}
