import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show PlatformException;
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

  // Разбор жалобы 01.09.2026 (realme C67, Android 14): при добавлении фото
  // человек видит окно «Something went wrong. Check that Google Play is
  // enabled on your device». Текста этого нет ни в нашем коде, ни в наших
  // библиотеках — проверено поиском по APK и по всем .aar: окно рисует сам
  // Google Play на устройстве. Наша сторона при этом молчала: отказ пикера
  // уходил в debugPrint, и в трекере за месяц не нашлось ни одной записи о
  // сбоях выбора фото. Разбирать такое нечем.
  //
  // Поэтому отказ теперь докладывается наружу вместе с кодом: следующий такой
  // случай будет виден с моделью телефона и версией Android.
  group('safePick докладывает об отказе пикера', () {
    test('код отказа уходит наблюдателю', () async {
      final seen = <String>[];
      final off = onPickFailure((code, _) => seen.add(code));
      addTearDown(off);

      final got = await safePick<XFile>(
        () async => throw PlatformException(code: 'photo_access_denied'),
      );

      expect(got, isNull, reason: 'отказ по-прежнему читается как отмена');
      expect(seen, ['photo_access_denied']);
    });

    test('обычная отмена наблюдателя не будит', () async {
      final seen = <String>[];
      final off = onPickFailure((code, _) => seen.add(code));
      addTearDown(off);

      await safePick<XFile>(() async => null);

      expect(seen, isEmpty, reason: 'человек просто закрыл галерею');
    });

    test('отказ не из PlatformException тоже доносится', () async {
      // Нативный путь пикера умеет падать и без кода — например, TypeError при
      // пересоздании активити. Такой отказ так же важен для разбора.
      final seen = <String>[];
      final off = onPickFailure((code, _) => seen.add(code));
      addTearDown(off);

      await safePick<XFile>(() async => throw StateError('нет результата'));

      expect(seen, ['unknown']);
    });
  });
}
