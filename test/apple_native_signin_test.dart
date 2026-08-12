import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож входа через Apple.
///
/// Через браузер вход отказывал у каждой второй попытки: системный браузер не
/// мог загрузить `appleid.apple.com` — 77 обрывов против 33 удачных входов на 57
/// разных телефонах за сутки, при одной ошибке в журнале сервера за те же сутки.
/// Поэтому на iPhone вход берёт системный диалог, а браузер остаётся запасным
/// путём: у части людей он всё-таки работает, и отбирать его нельзя.
///
/// Проверить это на устройстве нам нечем — айфона нет ни у автора, ни у второго
/// разработчика. Значит хотя бы звенья цепочки должны быть на месте: пропавшее
/// звено ломает вход молча.
void main() {
  test('на iPhone сперва системный диалог, потом браузер', () {
    final source = File('lib/services/pb_auth_service.dart').readAsStringSync();

    expect(source, contains('SignInWithApple.getAppleIDCredential'),
        reason: 'системный диалог — основной путь');
    expect(source, contains('/api/apple/native'),
        reason: 'токен Apple меняется на сессию через свой маршрут');
    expect(source, contains("signInWithOAuth2('apple')"),
        reason: 'браузер обязан остаться запасным путём');

    // Отмена — это не сбой: второй раз ничего показывать не нужно.
    expect(source, contains('AuthorizationErrorCode.canceled'));

    // Nonce привязывает токен к попытке входа.
    expect(source, contains('sha256'));
  });

  test('сервер проверяет токен и узнаёт прежние аккаунты', () {
    final hook =
        File('pocketbase/pb_hooks/apple_native.pb.js').readAsStringSync();

    expect(hook, contains('/apple/verify'),
        reason: 'подпись проверяет релей: RS256 в JSVM нет');
    expect(hook, contains('nonce'));
    expect(hook, contains('_externalAuths'),
        reason: 'по sub находим тех, кто раньше входил через браузер');
    expect(hook, contains('recordAuthResponse'),
        reason: 'ответ должен быть той же формы, что у обычного входа');
  });

  test('релей умеет проверять токен Apple', () {
    final relay = File('pocketbase/apns/apns_relay.py').readAsStringSync();

    expect(relay, contains('appleid.apple.com/auth/keys'),
        reason: 'подпись сверяется по ключам Apple');
    expect(relay, contains('RS256'));
    expect(relay, contains('APPLE_AUDIENCES'),
        reason: 'нативный вход приходит с bundle id, веб — с Services ID');
  });
}
