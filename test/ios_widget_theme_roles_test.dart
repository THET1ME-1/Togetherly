import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож ролей темы в расширении.
///
/// `WidgetTheme` на iOS — это набор объявленных свойств, и обращение к
/// необъявленному роняет ВСЮ сборку расширения: «Value of type 'WidgetTheme'
/// has no member 'tertiary'». На Linux этого не видно, ошибка всплывает
/// через двадцать минут на macOS-раннере — так и случилось 20.09.2026, когда
/// дорожка вех в `TogetherWidget.swift` позвала роль, которой не было.
void main() {
  final dir = Directory('ios/TogetherlyWidget');

  test('каждая роль темы, которую зовёт Swift, объявлена в WidgetTheme', () {
    final theme = File('${dir.path}/WidgetTheme.swift').readAsStringSync();
    final declared = RegExp(r'var (\w+): Color')
        .allMatches(theme)
        .map((m) => m.group(1)!)
        .toSet();
    expect(declared, isNotEmpty);

    // Ищем только те переменные, которым ПРИСВОЕНА тема: короткое имя `t`
    // в этом проекте занято и таймером, и текстом.
    final used = <String, Set<String>>{};
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.swift')) continue;
      if (file.path.endsWith('WidgetTheme.swift')) continue;
      final code = file.readAsStringSync();
      final names = RegExp(r'(?:let|var) (\w+)(?::\s*WidgetTheme)?\s*=\s*WidgetTheme\(\)')
          .allMatches(code)
          .map((m) => m.group(1)!)
          .toSet();
      if (names.isEmpty) continue;
      for (final name in names) {
        for (final m in RegExp('\\b$name\\.([a-z][A-Za-z]*)\\b').allMatches(code)) {
          used.putIfAbsent(m.group(1)!, () => {}).add(file.uri.pathSegments.last);
        }
      }
    }

    // Отбрасываем то, что заведомо не роль: методы темы и свойства других
    // сущностей с тем же именем переменной.
    const notRoles = {'color', 'isDark'};

    final missing = <String>[];
    used.forEach((role, files) {
      if (notRoles.contains(role) || declared.contains(role)) return;
      missing.add('$role (${files.join(", ")})');
    });

    expect(
      missing,
      isEmpty,
      reason: 'Swift зовёт роли, которых нет в WidgetTheme: ${missing.join("; ")}',
    );
  });
}
