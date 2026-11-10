import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pending_media_policy.dart';
import 'package:love_app/models/upload_timeout.dart';

/// Фото не теряется, когда хранилище не принимает файлы.
///
/// 9–10.11.2026 хранилище отвечало отказом окнами по несколько минут: сервер
/// честно повторял три раза, приложение ещё дважды, и всё укладывалось в то же
/// окно. За сутки около 200 загрузок кончались «Не удалось загрузить», и
/// воспоминание не сохранялось. Теперь такой файл откладывается, как при
/// отсутствии сети, и доезжает сам.
void main() {
  group('откладывать ли заливку', () {
    test('хранилище не приняло файл (400 с пустым data) — откладываем', () {
      expect(
          uploadWorthDeferring(400,
              response: {'message': 'Failed to create record.', 'data': {}}),
          isTrue);
    });

    test('сервер ответил 5xx или не ответил вовсе — откладываем', () {
      for (final code in [500, 502, 503, 504]) {
        expect(uploadWorthDeferring(code), isTrue, reason: '$code');
      }
      expect(uploadWorthDeferring(null), isTrue, reason: 'срок вышел');
    });

    test('отказ по сути не откладываем: повтор ничего не изменит', () {
      expect(uploadWorthDeferring(401), isFalse, reason: 'сессия протухла');
      expect(uploadWorthDeferring(403), isFalse, reason: 'запрет');
      expect(uploadWorthDeferring(413), isFalse, reason: 'слишком большой');
      expect(
          uploadWorthDeferring(400, response: {
            'data': {
              'file': {'code': 'validation_file_size_limit'}
            }
          }),
          isFalse,
          reason: 'ошибка поля');
    });

    test('без входа не откладываем: файл некому будет дозалить', () {
      expect(uploadWorthDeferring(503, loggedIn: false), isFalse);
    });
  });

  group('когда пробовать снова', () {
    test('паузы растут: 2, 4, 8, 16 минут, дальше по полчаса', () {
      expect([for (var a = 0; a < 7; a++) pendingRetryDelay(a).inMinutes],
          [2, 4, 8, 16, 30, 30, 30]);
    });
  });

  group('когда сдаться', () {
    const day = 24 * 60 * 60 * 1000;

    test('свежий файл не бросаем, сколько бы попыток ни сорвалось', () {
      expect(pendingGiveUp(attempts: 50, ageMs: 2 * day), isFalse);
    });

    test('после трёх суток и восьми попыток — бросаем', () {
      expect(pendingGiveUp(attempts: 8, ageMs: 3 * day + 1), isTrue);
    });

    test('старый файл с парой попыток ещё пробуем', () {
      expect(pendingGiveUp(attempts: 2, ageMs: 10 * day), isFalse);
    });

    test('запись прежней сборки без времени живёт по прежнему правилу', () {
      expect(pendingGiveUp(attempts: 8, ageMs: null), isTrue);
      expect(pendingGiveUp(attempts: 7, ageMs: null), isFalse);
    });
  });

  group('подключено', () {
    test('отказ хранилища уводит файл воспоминания в отложенные', () {
      final media = File('lib/services/media_service.dart').readAsStringSync();
      expect(media, contains('outcome.deferrable'));
      final pb = File('lib/services/pb_media_service.dart').readAsStringSync();
      expect(pb, contains('uploadWorthDeferring('));
    });

    test('отложенные файлы пробуются по расписанию, а не только при связи',
        () {
      final cache =
          File('lib/services/offline/media_cache.dart').readAsStringSync();
      expect(cache, contains('pendingRetryDelay('));
      expect(cache, contains('pendingGiveUp('));
    });
  });
}
