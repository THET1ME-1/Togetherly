import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож картинок настроения.
///
/// Настроение приходит либо бандленным ассетом, либо адресом из каталога
/// (`https://…/api/files/catalog_items/dog/love_….webp`) — паки приезжают с
/// сервера без обновления приложения. `Image.asset` второй случай не понимает:
/// он бросает `Unable to load asset`, и вместо стикера остаётся пустое место.
/// Так превью виджетов в каталоге падало у каждого, кто выбрал «Пёсика» или
/// «Моти» — 260 событий за трое суток на 1.24.0.
///
/// Рисовать такие пути можно только через `MoodImage`: он сам различает ассет и
/// адрес, а при сбое показывает классический эквивалент.
void main() {
  test('пути настроений не рисуются через Image.asset', () {
    final offenders = <String>[];
    // Поля, в которых лежит путь настроения: он бывает и адресом каталога.
    final moodField = RegExp(r'\b\w*(moodEmoji|moodImagePath|previewImage)\b');
    final assetCall = RegExp(r'Image\.asset\s*\(');

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in assetCall.allMatches(source)) {
        final args = _argumentsOf(source, match.end - 1);
        if (args == null || !moodField.hasMatch(args)) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Каталожный пак приезжает адресом, Image.asset его не покажет — '
          'рисовать через MoodImage: ${offenders.join(', ')}',
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
