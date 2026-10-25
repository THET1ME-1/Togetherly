import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Кнопки настроек не трогают контекст профиля (TOG-33).
///
/// Настройки — отдельный маршрут поверх профиля, а вкладку профиля под ними
/// могут пересобрать. Строка «Инструменты рисования» звала `_openDrawTools`,
/// тот открывал экран через контекст профиля, и у снятого профиля он был пуст:
/// «Null check operator used on a null value» (Bugsink 24.10.2026, 1.39.0).
/// Метод профиля, отданный кнопке как есть (`onX: _method,`), не должен читать
/// `context`: такому методу передают `ctx` настроек.
void main() {
  test('кнопки настроек не открывают экраны контекстом профиля', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _openSettings(BuildContext context)');
    expect(start, isNot(-1));
    final settings = source.substring(start, source.indexOf('\n  }\n', start));

    final offenders = <String>[];
    for (final match in RegExp(r'on\w+:\s*(_\w+),').allMatches(settings)) {
      final name = match.group(1)!;
      final definition = RegExp(
        '(?:Future<void>|void)\\s+$name\\(\\)\\s*(?:async\\s*)?\\{',
      ).firstMatch(source);
      if (definition == null) continue;
      final body = source.substring(
        definition.end,
        source.indexOf('\n  }\n', definition.end),
      );
      if (RegExp(r'\bcontext\b').hasMatch(body)) offenders.add(name);
    }
    expect(offenders, isEmpty);
  });
}
