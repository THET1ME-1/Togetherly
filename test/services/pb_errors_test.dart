// Как читать отказы PocketBase: «уже есть» — не провал.
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/services/pb_errors.dart';

ClientException _err(int code, Map<String, dynamic> response) =>
    ClientException(statusCode: code, response: response);

void main() {
  group('запись уже существует', () {
    test('конфликт по первичному ключу', () {
      final e = _err(400, {
        'data': {
          'id': {'code': 'validation_not_unique', 'message': 'Value must be unique.'}
        }
      });
      expect(alreadyExists(e), isTrue);
    });

    test('конфликт по составному индексу', () {
      final e = _err(400, {
        'data': {
          'group_id': {'message': 'Value must be unique.'},
          'user_uid': {'message': 'Value must be unique.'},
        }
      });
      expect(alreadyExists(e), isTrue);
    });

    test('другая ошибка проверки — это настоящий отказ', () {
      final e = _err(400, {
        'data': {
          'coins': {'message': 'cannot be blank'}
        }
      });
      expect(alreadyExists(e), isFalse);
    });

    test('отказ по правам и обрыв связи сюда не относятся', () {
      expect(alreadyExists(_err(403, const {})), isFalse);
      expect(alreadyExists(_err(0, const {})), isFalse);
      expect(alreadyExists(null), isFalse);
      expect(alreadyExists(Exception('что-то своё')), isFalse);
    });
  });

  group('остальные ответы', () {
    test('404 — не найдено или спрятано правилами', () {
      expect(notFound(_err(404, const {})), isTrue);
      expect(notFound(_err(400, const {})), isFalse);
    });

    test('429 — сервер просит подождать', () {
      expect(tooManyRequests(_err(429, const {})), isTrue);
      expect(tooManyRequests(_err(500, const {})), isFalse);
    });

    test('нулевой код — ответа не было вовсе', () {
      expect(noAnswer(_err(0, const {})), isTrue);
      expect(noAnswer(_err(502, const {})), isFalse);
    });
  });
}
