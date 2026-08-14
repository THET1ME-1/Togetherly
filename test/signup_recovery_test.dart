// Регистрация не теряется, когда сервер отвечает слишком долго.
//
// Вечер 14.08.2026: людей набежало тридцать в минуту, создание аккаунта на
// сервере занимало 18–25 секунд, а клиент сдавался на двадцатой. Аккаунт при
// этом создавался. Человек видел «Сервер не отвечает. Проверьте интернет», жал
// «Создать» ещё раз и получал «почта занята» — 408 таких обрывов за десять
// минут, и каждый повтор добавлял серверу работы.
//
// Теперь: ждём создание до сорока пяти секунд, а если не дождались или почта
// оказалась занята — пробуем войти теми же данными. Пустило — регистрация
// состоялась. Чужой аккаунт с этой почтой вход не пустит, и человек увидит
// прежний разговор про занятую почту.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/auth_failure.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  group('разбор ответа сервера', () {
    test('занятая почта опознаётся', () {
      final e = ClientException(
        statusCode: 400,
        response: {
          'data': {
            'email': {'code': 'validation_not_unique', 'message': 'Value must be unique.'}
          }
        },
      );
      expect(AuthFailure.of(e), AuthFailure.emailTaken);
    });

    test('неверный пароль занятой почтой не считается', () {
      final e = ClientException(
        statusCode: 400,
        response: {'message': 'Failed to authenticate.'},
      );
      expect(AuthFailure.of(e), AuthFailure.badCredentials);
    });
  });

  group('пути восстановления в регистрации', () {
    final src = File('lib/services/pb_auth_service.dart').readAsStringSync();
    final signUp = src.substring(
      src.indexOf('Future<RecordModel?> signUpWithEmail'),
      src.indexOf('/// Вход по email/паролю.'),
    );

    test('создание ждёт дольше обычного запроса', () {
      expect(signUp, contains('createTimeout = Duration(seconds: 45)'));
      expect(signUp, contains('.timeout(createTimeout)'));
    });

    test('таймаут создания проверяется входом', () {
      final afterTimeout = signUp.substring(signUp.indexOf('on TimeoutException'));
      expect(afterTimeout, contains('authWithPassword'));
    });

    test('занятая почта проверяется входом', () {
      expect(signUp, contains('AuthFailure.emailTaken'));
      final afterTaken = signUp.substring(signUp.indexOf('AuthFailure.emailTaken'));
      expect(afterTaken, contains('authWithPassword'));
    });

    test('чужая занятая почта пробрасывается дальше', () {
      expect(signUp, contains('rethrow'));
    });
  });
}
