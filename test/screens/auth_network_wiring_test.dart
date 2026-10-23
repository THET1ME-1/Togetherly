// TOG-16: вход, регистрация и сброс пароля при обрыве связи спрашивают
// проверку сети и показывают её ответ: нет интернета или наш сервер закрыт в
// этой сети (совет про VPN). Сама проверка и тексты под тестами в
// server_reach_test.dart и network_failure_text_test.dart; здесь — что экраны
// их зовут. Поломка тихая: без подключения люди снова читают «проверьте
// интернет» при работающем интернете.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Тело метода от его объявления до следующего объявления того же отступа.
String _method(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature не найден');
  final next = src.indexOf(RegExp(r'\n  (Future<|void |String |bool )'), start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}

void main() {
  final login = _read('lib/screens/login_screen.dart');
  final setup = _read('lib/screens/setup_screen.dart');

  test('вход по почте и через сервисы при обрыве проверяет сеть', () {
    final text = _method(login, 'Future<String> _authErrorText(');
    expect(text, contains('.isNetwork'));
    expect(text, contains('ServerReach.instance.check()'));
    expect(text, contains('networkFailureText('));
    expect(_method(login, 'Future<void> _signInWithEmail('),
        contains('_authErrorText(e)'));
    expect(_method(login, 'Future<void> _oauthSignIn('),
        contains('_authErrorText(e)'));
  });

  test('сброс пароля при обрыве не винит адрес', () {
    final text = _method(login, 'Future<void> _sendPasswordReset(');
    expect(text, contains('.isNetwork'));
    expect(text, contains('ServerReach.instance.check()'));
  });

  test('регистрация и вход через сервисы на экране профиля проверяют сеть', () {
    final text = _method(setup, 'Future<String> _authErrorText(');
    expect(text, contains('.isNetwork'));
    expect(text, contains('ServerReach.instance.check()'));
    expect(_method(setup, 'Future<void> _completeSetup('),
        contains('_authErrorText(e)'));
  });

  test('«проверьте интернет» на этих экранах больше не звучит', () {
    expect(login, isNot(contains('serverNotResponding')));
    expect(setup, isNot(contains('serverNotResponding')));
  });
}
