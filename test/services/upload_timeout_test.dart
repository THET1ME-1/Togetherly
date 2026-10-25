import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/upload_timeout.dart';

/// Срок заливки считается от размера файла.
///
/// Пока он был жёсткими шестьюдесятью секундами, за тридцать дней 155 заливок
/// оборвались на полуслове — 93 из них картинки холста. Шестьдесят секунд на
/// мегабайтную картинку по мобильной сети не хватает, а на трёхсотмегабайтный
/// ролик их не хватает подавно.
void main() {
  group('uploadTimeoutFor', () {
    test('мелочь получает нижний порог, а не пропорцию', () {
      // Голосовое на 40 КБ ушло бы за секунду, но сеть бывает и такая, что
      // рукопожатие занимает полминуты.
      expect(uploadTimeoutFor(40 * 1024), kUploadTimeoutMin);
    });

    test('мегабайтам достаётся время на передачу', () {
      final t = uploadTimeoutFor(6 * 1024 * 1024);
      expect(t, greaterThan(kUploadTimeoutMin));
      expect(t, const Duration(seconds: 60 + 6 * 15));
    });

    test('срок растёт вместе с файлом', () {
      expect(
        uploadTimeoutFor(20 * 1024 * 1024),
        greaterThan(uploadTimeoutFor(5 * 1024 * 1024)),
      );
    });

    test('у потолка есть предел — заливка не висит вечно', () {
      expect(uploadTimeoutFor(300 * 1024 * 1024), kUploadTimeoutMax);
    });

    test('пустой файл не даёт нулевого срока', () {
      expect(uploadTimeoutFor(0), kUploadTimeoutMin);
    });
  });

  group('uploadWorthRetry', () {
    test('обрыв по сроку стоит повторить', () {
      expect(uploadWorthRetry(408), isTrue);
      expect(uploadWorthRetry(null), isTrue);
    });

    test('отказ сервера повторять бессмысленно', () {
      // Ни протухшая сессия, ни запрет доступа, ни слишком большой файл со
      // второй попытки не изменятся.
      expect(uploadWorthRetry(401), isFalse);
      expect(uploadWorthRetry(403), isFalse);
      expect(uploadWorthRetry(400), isFalse);
      expect(uploadWorthRetry(413), isFalse);
    });

    test('сервер прилёг — вторая попытка уместна', () {
      expect(uploadWorthRetry(502), isTrue);
      expect(uploadWorthRetry(503), isTrue);
    });

    test('слишком частые запросы повторяем, но не мгновенно', () {
      expect(uploadWorthRetry(429), isTrue);
    });

    // TOG-41: хранилище Hetzner изредка не отвечает, и PocketBase отдаёт 400
    // «Failed to create record.» без ошибок полей. Повтор проходит.
    test('хранилище не приняло файл — повторяем', () {
      expect(
        uploadWorthRetry(400, response: {
          'status': 400,
          'message': 'Failed to create record.',
          'data': <String, dynamic>{},
        }),
        isTrue,
      );
    });

    test('ошибка поля при 400 — не повторяем', () {
      expect(
        uploadWorthRetry(400, response: {
          'status': 400,
          'message': 'Failed to create record.',
          'data': {
            'file': {'code': 'validation_file_size_limit', 'message': 'Too large'},
          },
        }),
        isFalse,
      );
    });

    test('400 без тела ответа — не повторяем', () {
      expect(uploadWorthRetry(400, response: const {}), isFalse);
    });
  });

  test('загрузка отдаёт правилу повтора тело ответа сервера', () {
    // без тела 400 от хранилища не отличить от ошибки поля, и повтора не будет
    final media = File('lib/services/pb_media_service.dart').readAsStringSync();
    expect(media, contains('uploadWorthRetry(code, response: answer)'));
  });

  test('повторы сервера укладываются в срок приложения для маленького файла', () {
    // Сервер повторяет запись в хранилище сам (pocketbase/pb-cgo/s3retry.go).
    // Если его худший случай длиннее нашего срока, приложение сдаётся первым,
    // шлёт файл ещё раз, и запись от поздней удачной попытки сервера остаётся
    // лишней.
    final go = File('pocketbase/pb-cgo/s3retry.go').readAsStringSync();
    final attempts = int.parse(RegExp(r'attempts:\s+(\d+),').firstMatch(go)!.group(1)!);
    final wait = int.parse(RegExp(r'headerWait:\s+(\d+) \* time\.Second').firstMatch(go)!.group(1)!);
    final pauses = RegExp(r'backoff:\s+\[\]time\.Duration\{([^}]*)\}').firstMatch(go)!.group(1)!;
    var pauseMs = 0;
    for (final item in pauses.split(',')) {
      final part = item.trim();
      if (part.isEmpty) continue;
      final factor = int.tryParse(part.split(' ').first) ?? 1;
      pauseMs += factor * (part.endsWith('Millisecond') ? 1 : 1000);
    }
    final worst = Duration(seconds: attempts * wait, milliseconds: pauseMs);
    expect(worst, lessThan(kUploadTimeoutMin));
  });
}
