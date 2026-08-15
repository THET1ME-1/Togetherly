import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Поток, созданный прямо в аргументе `stream:`, пересоздаётся на каждой
/// перерисовке. Каждая новая подписка `watchList` зовёт `syncOnce()` и уходит
/// в сеть за списком, а картинки внутри списка пересоздаются вместе с ним и не
/// успевают дописаться в кэш до отмены загрузки.
///
/// Так экран «Хочу с тобой» устроил цикл: 52 запроса `wishes/records` и 180
/// скачиваний двух аватарок с одного телефона за сорок секунд. По серверу это
/// вышло в 131 тысячу запросов аватарок из 149 тысяч всех обращений к файлам,
/// то есть в 88% раздачи.
///
/// Поток положено создать один раз (в `initState`) и держать в поле состояния.
/// Осознанное исключение помечается комментарием `// stream-ok:` на строке
/// с `stream:` или на предыдущей — с объяснением, почему пересоздание дёшево.
void main() {
  test('поток не создаётся в build', () {
    final problems = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // В комментариях этот же образец поминает сам разбор бага.
        if (line.trimLeft().startsWith('//')) continue;

        final match = RegExp(r'stream:\s*(.*)$').firstMatch(line);
        if (match == null) continue;

        // Аргумент может переноситься на следующую строку.
        var expr = match.group(1)!.trim();
        if (expr.isEmpty && i + 1 < lines.length) expr = lines[i + 1].trim();

        // Вызов метода в аргументе и есть создание потока на месте.
        if (!expr.contains('(')) continue;

        final prev = i > 0 ? lines[i - 1] : '';
        if (line.contains('// stream-ok:') || prev.contains('// stream-ok:')) {
          continue;
        }

        problems.add('${entity.path}:${i + 1}  $expr');
      }
    }

    expect(
      problems,
      isEmpty,
      reason: 'поток создаётся в build (вынести в поле состояния):\n'
          '${problems.join('\n')}',
    );
  });
}
