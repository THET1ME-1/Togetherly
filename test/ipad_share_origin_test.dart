import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож iPad-поповера.
///
/// На iPad системный лист «Поделиться» — popover, и без `sharePositionOrigin`
/// он не открывается: кнопка выглядит мёртвой. Ревью App Store идёт как раз на
/// iPad (реджект 2.1(a) «Unresponsive share button», июль), а найти такое на
/// глаз тяжело — вызовов шаринга в проекте десяток, и новый легко написать без
/// якоря. Поэтому проверяем исходники: каждый вызов `Share.*` обязан передавать
/// origin, хоть своим параметром, хоть через `shareOriginFromContext`.
void main() {
  test('каждый вызов Share.* передаёт sharePositionOrigin', () {
    final offenders = <String>[];
    final pattern = RegExp(r'Share\.(share|shareXFiles|shareUri)\s*\(');

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        final args = _argumentsOf(source, match.end - 1);
        if (args == null || args.contains('sharePositionOrigin')) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Без якоря лист «Поделиться» не открывается на iPad: '
          '${offenders.join(', ')}',
    );
  });
}

/// Текст аргументов вызова: от открывающей скобки до парной ей закрывающей.
///
/// Скобки внутри строковых литералов не считаем — иначе `Share.share('(')`
/// увёл бы счётчик и обрезал список аргументов на середине.
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
