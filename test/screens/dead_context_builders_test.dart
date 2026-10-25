import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Построитель маршрута или листа не читает тему и размеры из чужого контекста
/// (TOG-33).
///
/// Маршрут перестраивается и тогда, когда экран или лист, открывший его, уже
/// снят, а у снятого `State.context` пуст. Окно Togetherly+, открытое с
/// холста, на перестройке читало `Theme.of(context)` закрытого холста и
/// падало «Null check operator used on a null value» (Bugsink 20.10 и
/// 24.10.2026, 1.37 и 1.38). Тему и размеры берут до перехода или из
/// собственного контекста построителя.
void main() {
  test('построители с отброшенным контекстом не читают чужую тему', () {
    final builder = RegExp(r'builder:\s*\((?:_|__)\)\s*=>');
    final reads = RegExp(
      r'Theme\.of\(context\)|context\.appTheme|MediaQuery\.of\(context\)'
      r'|ProfileTheme\.of\(context\)',
    );
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      for (final match in builder.allMatches(text)) {
        if (reads.hasMatch(_argument(text, match.end))) {
          final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
          found.add('${file.path}:$line');
        }
      }
    }
    expect(found, isEmpty);
  });
}

/// Выражение построителя: до запятой или закрывающей скобки своего уровня.
String _argument(String text, int from) {
  var depth = 0;
  final end = (from + 4000).clamp(0, text.length);
  for (var i = from; i < end; i++) {
    final char = text[i];
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) {
      if (depth == 0) return text.substring(from, i);
      depth--;
    }
    if (char == ',' && depth == 0) return text.substring(from, i);
  }
  return text.substring(from, end);
}
