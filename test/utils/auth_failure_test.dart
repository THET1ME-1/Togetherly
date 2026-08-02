// Экраны входа и регистрации разбирали ошибку поиском подстрок в
// `e.toString()`, и всё незнакомое валилось в ветку «показать исключение».
// Человек с ломаным TLS видел в приложении дословно:
//   ClientException: {url: …, statusCode: 0, response: {}, originalError:
//   HandshakeException: Handshake error in client (OS Error:
//   WRONG_VERSION_NUMBER(tls_record.cc:127))}
// Это письмо в поддержку от 2 августа. Ни понять, ни починить по такому
// тексту нельзя, а причина у него понятная: соединение ломают по дороге.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/auth_failure.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  group('AuthFailure.of — что пошло не так', () {
    test('сломанный TLS по дороге', () {
      final e = ClientException(
        statusCode: 0,
        originalError: const HandshakeException(
          'Handshake error in client (OS Error: '
          'WRONG_VERSION_NUMBER(tls_record.cc:127))',
        ),
      );
      expect(AuthFailure.of(e), AuthFailure.blockedConnection);
    });

    test('обрыв связи без TLS — обычное «нет сети»', () {
      final e = ClientException(
        statusCode: 0,
        originalError: const SocketException('Connection refused'),
      );
      expect(AuthFailure.of(e), AuthFailure.noConnection);
    });

    test('запрос не дождался ответа', () {
      expect(AuthFailure.of(TimeoutException('20s')), AuthFailure.timeout);
    });

    test('такая почта уже занята', () {
      final e = ClientException(statusCode: 400, response: const {
        'data': {
          'email': {'code': 'validation_not_unique'}
        }
      });
      expect(AuthFailure.of(e), AuthFailure.emailTaken);
    });

    test('слишком часто', () {
      expect(AuthFailure.of(ClientException(statusCode: 429)),
          AuthFailure.tooManyAttempts);
    });

    test('сервер прилёг', () {
      expect(AuthFailure.of(ClientException(statusCode: 502)),
          AuthFailure.serverDown);
    });

    test('остальные 400 — про пароль, а не про сеть', () {
      expect(AuthFailure.of(ClientException(statusCode: 400)),
          AuthFailure.badCredentials);
    });

    test('незнакомое остаётся незнакомым', () {
      expect(AuthFailure.of(StateError('что-то своё')), AuthFailure.unknown);
    });

    test('TLS распознаётся и когда обёртки нет', () {
      // PocketBase не всегда заворачивает исходное исключение.
      expect(
        AuthFailure.of(const HandshakeException('WRONG_VERSION_NUMBER')),
        AuthFailure.blockedConnection,
      );
    });
  });
}
