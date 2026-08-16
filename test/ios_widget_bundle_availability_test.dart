// Блок виджетов не может состоять из одного `if #available`.
//
// 13.08.2026 виджеты экрана блокировки завели отдельным
// `@WidgetBundleBuilder`-свойством, целиком закрытым `if #available(iOS 16)`.
// Расширение после этого стало ПАДАТЬ: chronod запускает его, чтобы забрать
// список виджетов, процесс умирает с SIGTRAP, дескрипторы не приходят — и в
// галерее пропадают не три виджета блокировки, а все двадцать два. Люди пишут
// «нажимаю плюс, а приложения нет», и по коду это не видно совсем: собирается,
// подписывается, устанавливается, регистрируется.
//
// Проверено двумя одинаковыми сборками на симуляторе: со свойством — SIGTRAP и
// пустые Descriptors, без него — ноль падений и виджеты доезжают до системы.
//
// Правило: условная ветка живёт рядом с безусловными виджетами в одном блоке
// (так устроены `body` и `photoWidgets`), а не составляет блок целиком.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw =
      File('ios/TogetherlyWidget/TogetherlyWidgetBundle.swift').readAsStringSync();
  // Комментарии выкидываем до разбора: в них те же слова, что в коде, и
  // `if #available` из пояснения уводил вырезание за пределы настоящей ветки.
  final source = raw
      .split('\n')
      .map((l) => l.trimLeft().startsWith('//') ? '' : l)
      .join('\n');

  test('у каждого блока бандла есть безусловный виджет', () {
    final blocks = _bundleBlocks(source);
    expect(blocks, isNotEmpty, reason: 'не нашёл ни одного блока — разбор сломан');

    final offenders = <String>[];
    for (final block in blocks.entries) {
      if (!_hasUnconditionalWidget(block.value)) offenders.add(block.key);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'блок целиком под `if #available` роняет расширение с SIGTRAP, '
          'и галерея пустеет у всех виджетов: ${offenders.join(', ')}',
    );
  });

  test('виджеты экрана блокировки на месте', () {
    // Здесь смотрим исходник как есть — комментарии не мешают.
    // Чинить падение выбрасыванием функции нельзя: их отсутствие — тоже
    // жалоба («виджетов на экране блокировки нет», 13.08.2026).
    for (final widget in ['LockDaysWidget', 'LockMissWidget', 'LockMoodWidget']) {
      expect(source, contains('$widget()'), reason: '$widget пропал из бандла');
    }
    expect(raw, contains('if #available(iOS 16.0, *)'));
  });
}

/// Тела всех `@WidgetBundleBuilder`-свойств: имя → содержимое фигурных скобок.
Map<String, String> _bundleBlocks(String source) {
  final blocks = <String, String>{};
  final header = RegExp(r'@WidgetBundleBuilder\s+var\s+(\w+)\s*:\s*some Widget\s*\{');
  for (final match in header.allMatches(source)) {
    final body = _bracedBody(source, match.end - 1);
    if (body != null) blocks[match.group(1)!] = body;
  }
  return blocks;
}

/// Есть ли в блоке виджет вне условной ветки.
bool _hasUnconditionalWidget(String block) {
  // Убираем всё, что стоит под `if #available { … }`, и смотрим на остаток:
  // ссылка на другой блок (`coreWidgets`) годится так же, как `LoveWidget()`.
  var rest = block;
  final ifBlock = RegExp(r'if\s+#available[^{]*\{');
  while (true) {
    final match = ifBlock.firstMatch(rest);
    if (match == null) break;
    final body = _bracedBody(rest, match.end - 1);
    if (body == null) break;
    rest = rest.replaceRange(match.start, match.end + body.length + 1, '');
  }
  final code = rest
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('//'))
      .join(' ');
  return RegExp(r'\w+\(\)').hasMatch(code) || RegExp(r'\b\w*[Ww]idgets\b').hasMatch(code);
}

/// Содержимое от открывающей скобки до парной ей закрывающей.
String? _bracedBody(String source, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(openBrace + 1, i);
    }
  }
  return null;
}
