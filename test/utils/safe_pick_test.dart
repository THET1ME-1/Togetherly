import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:love_app/utils/safe_pick.dart';

/// Сторож выбора файлов.
///
/// Жалоба 23.08.2026 (@yaneulyana, «не могу добавить фото в момент»): на экране
/// воспоминания вместо галереи выскакивала красная плашка
/// `PlatformException(multiple_request, Cancelled by a second request)`.
/// Так `image_picker` отвечает, когда его зовут второй раз, пока открыт первый
/// лист — на iOS он открывается заметно медленнее, чем человек успевает нажать
/// повторно, а зона «Фото/Видео» занимает пол-экрана.
///
/// Глотать это исключение мало: пикер к тому моменту уже сорван, и человек
/// остаётся ни с чем. Поэтому второй вызов до нативного слоя не доходит вовсе.
void main() {
  group('safePick не пускает второй пикер поверх открытого', () {
    test('пока первый лист открыт, второй вызов возвращает null', () async {
      var calls = 0;
      final gate = Completer<void>();

      final first = safePick<List<XFile>>(() async {
        calls++;
        await gate.future;
        return <XFile>[];
      });
      // Даём первому вызову дойти до нативной части.
      await Future<void>.delayed(Duration.zero);

      final second = await safePick<List<XFile>>(() async {
        calls++;
        return <XFile>[];
      });

      expect(second, isNull, reason: 'второй лист открывать нечему');
      expect(calls, 1, reason: 'до пикера должен дойти только первый вызов');

      gate.complete();
      expect(await first, isEmpty);
    });

    test('после закрытия первого листа пикер снова доступен', () async {
      var calls = 0;
      Future<List<XFile>?> pick() =>
          safePick<List<XFile>>(() async {
            calls++;
            return <XFile>[];
          });

      expect(await pick(), isEmpty);
      expect(await pick(), isEmpty);
      expect(calls, 2);
    });

    test('замок снимается и когда пикер бросил исключение', () async {
      final failed = await safePick<List<XFile>>(
        () async => throw Exception('пикер сорвался'),
      );
      expect(failed, isNull);

      var called = false;
      final next = await safePick<List<XFile>>(() async {
        called = true;
        return <XFile>[];
      });
      expect(called, isTrue, reason: 'замок не должен пережить сбой');
      expect(next, isEmpty);
    });
  });

  test('в lib/ не осталось вызовов пикера мимо safePick', () {
    // Вырезаем сбалансированные вызовы safePick(...) и ищем пикер в остатке:
    // сам вызов часто стоит на другой строке, чем обёртка.
    String stripSafePick(String source) {
      final out = StringBuffer();
      var i = 0;
      while (i < source.length) {
        final start = source.indexOf('safePick', i);
        if (start < 0) {
          out.write(source.substring(i));
          break;
        }
        out.write(source.substring(i, start));
        var j = source.indexOf('(', start);
        if (j < 0) {
          i = start + 8;
          continue;
        }
        var depth = 0;
        for (; j < source.length; j++) {
          if (source[j] == '(') depth++;
          if (source[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        i = j + 1;
      }
      return out.toString();
    }

    final picker = RegExp(
      r'\.pick(Image|Video|Media|MultipleMedia|MultiImage)\(',
    );
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final rest = stripSafePick(file.readAsStringSync());
      for (final m in picker.allMatches(rest)) {
        final line = '\n'.allMatches(rest.substring(0, m.start)).length + 1;
        offenders.add('${file.path}: строка ~$line: ${m.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'пикер зовётся только через safePick:\n${offenders.join('\n')}',
    );
  });
}
