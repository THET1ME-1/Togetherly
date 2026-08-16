import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож символа таймера.
///
/// С версии 1.20 в поле `timers.emoji` лежит ИМЯ значка Material Symbols
/// (`local_fire_department`, `favorite`), а не эмодзи. Напечатать такое поле
/// через `Text` — значит показать человеку служебное имя вместо картинки: в
/// списке выбора таймера для виджета строка так и выглядела —
/// «local_fire_department» во всю ширину, а название таймера уезжало за край
/// (жалоба со снимком экрана, 15.08.2026).
///
/// Рисовать символ можно только через `SymbolIcon` / `SymbolCatalog.iconFor`:
/// они разбирают и новое имя, и эмодзи старых таймеров
/// (`SymbolCatalog.nameFromStored`).
void main() {
  test('символ таймера не печатается текстом', () {
    final offenders = <String>[];
    // Поле символа таймера: `timer.emoji`, `activeTimer.emoji`, `sys.emoji`.
    final timerSymbol = RegExp(r'\b\w*[Tt]imer\w*\.emoji\b|\bsys\.emoji\b');
    final textCall = RegExp(r'\bText\s*\(');

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in textCall.allMatches(source)) {
        final args = _argumentsOf(source, match.end - 1);
        if (args == null || !timerSymbol.hasMatch(args)) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'В `timers.emoji` лежит имя значка, а не эмодзи — рисовать через '
          'SymbolIcon: ${offenders.join(', ')}',
    );
  });
}

/// Текст аргументов вызова: от открывающей скобки до парной ей закрывающей.
String? _argumentsOf(String source, int openParen) {
  var depth = 0;
  String? quote;
  for (var i = openParen; i < source.length; i++) {
    final ch = source[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen + 1, i);
    }
  }
  return null;
}
