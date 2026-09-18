import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Почта без учёта регистра при входе и сбросе пароля (18.09.2026).
///
/// Живьём это проверяется пробой на сервере; здесь стережём проводку: без
/// хука вход с «Anna@…» снова отвечает «неверный пароль», а без своего
/// маршрута «Забыли пароль» снова молча не шлёт письмо.
void main() {
  final hook = File('pocketbase/pb_hooks/email_case.pb.js').readAsStringSync();

  test('Вход ищет почту без учёта регистра, только когда точный поиск промахнулся', () {
    expect(hook, contains('onRecordAuthWithPasswordRequest('));
    expect(hook, contains('if (!e.record)'));
    expect(hook, contains('lower(email) = lower({:e}) LIMIT 2'));
    expect(hook, contains('rows.length === 1'),
        reason: 'двойники по регистру не должны угадываться');
  });

  test('Свой маршрут сброса отвечает 204 и не выдаёт, есть ли адрес', () {
    expect(hook, contains('routerAdd("POST", "/api/auth/password-reset"'));
    expect(hook, contains('\$mails.sendRecordPasswordReset(\$app, record)'));
    expect(hook, isNot(contains('e.json(404')));
  });

  test('Приложение просит сброс через свой маршрут', () {
    final auth = File('lib/services/pb_auth_service.dart').readAsStringSync();
    expect(auth, contains("'/api/auth/password-reset'"));
  });
}
