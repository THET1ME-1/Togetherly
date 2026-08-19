import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Тест «Умение любить» бесплатный, и на iPhone он обязан быть виден.
///
/// Togetherly+ на iOS не существует, поэтому всё за
/// `PlusService.instance.visible` там не рисуется вовсе. Полной статистике
/// пары так и надо, она платная. Но вход в тест стоял в том же блоке и
/// пропадал заодно: на Android он есть, на iPhone его нет ни у кого.
///
/// Проверяем буквально: вызов входа в тест не лежит внутри блока, закрытого
/// проверкой видимости Плюса.
void main() {
  test('вход в «Умение любить» не закрыт проверкой Togetherly+', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      final openGates = <int>[]; // отступы открытых блоков «за Плюсом»
      for (final line in lines) {
        final indent = line.length - line.trimLeft().length;
        if (line.trimLeft().startsWith(']')) {
          openGates.removeWhere((gate) => indent <= gate);
        }
        if (RegExp(r'^\s*if\s*\(.*PlusService\.instance\.visible')
            .hasMatch(line)) {
          openGates.add(indent);
        }
        if (openGates.isNotEmpty && line.contains('_loveTestLink(')) {
          offenders.add('${file.path}:${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'тест бесплатный, а его вход спрятан вместе с платным разделом, '
          'и на iPhone о нём никто не узнает: ${offenders.join('; ')}',
    );
  });
}
