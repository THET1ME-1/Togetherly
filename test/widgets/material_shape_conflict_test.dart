// `Material` не принимает `shape` и `borderRadius` одновременно.
//
// Ассерт самого Flutter: `!(shape != null && borderRadius != null)`. В релизе
// ассерты выключены и форму задаёт `shape`, поэтому промах живёт незамеченным;
// в отладочной сборке экран целиком встаёт красным. С 29 июля 2026 такими были
// оба слота карточек «Мой виджет» и «Виджет партнёра» (`_buildSlotRow`), и
// раздел «Уже стоят» на экране виджетов не открывался вовсе — ни фотографию
// поставить, ни виджет вынести на рабочий стол.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Тело вызова `Material(...)`: от открывающей скобки до парной закрывающей.
String _callBody(String source, int start) {
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i);
    }
  }
  return source.substring(start);
}

void main() {
  test('ни один Material не задаёт форму дважды', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      var from = 0;
      while (true) {
        final at = source.indexOf('Material(', from);
        if (at < 0) break;
        from = at + 1;
        // `MaterialApp(`, `MaterialPageRoute(` и родня — не тот виджет.
        final before = at == 0 ? '' : source[at - 1];
        if (RegExp(r'[A-Za-z0-9_]').hasMatch(before)) continue;
        final body = _callBody(source, at + 'Material'.length);
        // Смотрим только на СВОИ аргументы: вложенные вызовы (например
        // `shape: RoundedRectangleBorder(borderRadius: …)`) не в счёт, а
        // вложены они бывают в несколько слоёв — снимаем их по одному, пока
        // снимается.
        var own = body;
        while (true) {
          final stripped = own.replaceAll(RegExp(r'\w+\([^()]*\)'), '');
          if (stripped == own) break;
          own = stripped;
        }
        if (own.contains('shape:') && own.contains('borderRadius:')) {
          final line = '\n'.allMatches(source.substring(0, at)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Material со shape и borderRadius разом валит экран в отладке: '
            '${offenders.join(', ')}');
  });
}
