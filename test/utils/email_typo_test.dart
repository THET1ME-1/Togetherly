// Опечатка в домене почты при регистрации (19.09.2026).
//
// На проде около 1260 аккаунтов с доменом, которого не существует: gmail.con
// (769), gmai.com (88), icloud.con (79), gnail.com (53)... Письмо для смены
// пароля на такой адрес не уходит никуда, и человек теряет вход, как только
// выйдет из аккаунта. Приложение пропускало любой адрес с собачкой.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/email_typo.dart';

void main() {
  test('самые частые опечатки с прода исправляются', () {
    const cases = {
      'kozabeear@gmail.con': 'kozabeear@gmail.com',
      'vpotapova261012@gmail.con': 'vpotapova261012@gmail.com',
      'a@gmai.com': 'a@gmail.com',
      'a@icloud.con': 'a@icloud.com',
      'a@gnail.com': 'a@gmail.com',
      'a@gamil.com': 'a@gmail.com',
      'a@gmail.co': 'a@gmail.com',
      'a@gmal.com': 'a@gmail.com',
      'a@gmail.ru': 'a@gmail.com',
      'a@mail.tu': 'a@mail.ru',
      'a@yandex.ry': 'a@yandex.ru',
      'a@mail.ry': 'a@mail.ru',
      'a@gmail.vom': 'a@gmail.com',
      'a@iclod.com': 'a@icloud.com',
      'a@gmaill.com': 'a@gmail.com',
      'a@icoud.com': 'a@icloud.com',
      'a@gmail.comm': 'a@gmail.com',
      'a@list.tu': 'a@list.ru',
      'a@gmail.xom': 'a@gmail.com',
    };
    cases.forEach((typed, fixed) {
      expect(emailTypoFix(typed), fixed, reason: typed);
    });
  });

  test('верный адрес не трогаем', () {
    for (final ok in [
      'a@gmail.com',
      'a@icloud.com',
      'a@mail.ru',
      'a@yandex.ru',
      'a@yandex.by',
      'a@yandex.kz',
      'a@yandex.com',
      'a@mail.com',
      'a@outlook.com',
      'a@privaterelay.appleid.com',
      'a@togetherly.day',
      'a@company.co',
    ]) {
      expect(emailTypoFix(ok), isNull, reason: ok);
    }
  });

  test('несуществующий домен верхнего уровня .con чинится у любого сервиса', () {
    expect(emailTypoFix('a@outlook.con'), 'a@outlook.com');
    expect(emailTypoFix('a@company.con'), 'a@company.com');
  });

  test('имя до собачки и регистр сохраняются, пробелы по краям уходят', () {
    expect(emailTypoFix('  Ivan.Petrov@Gmail.Con '), 'Ivan.Petrov@gmail.com');
  });

  test('не адрес — не подсказываем', () {
    for (final bad in ['', 'abc', '@gmail.con', 'a@']) {
      expect(emailTypoFix(bad), isNull, reason: bad);
    }
  });

  test('экран регистрации спрашивает про опечатку до создания аккаунта', () {
    final src = File('lib/screens/setup_screen.dart').readAsStringSync();
    final ask = src.indexOf('emailTypoFix(email)');
    final create = src.indexOf('auth.signUpWithEmail(');
    expect(ask, greaterThan(0), reason: 'проверки нет вовсе');
    expect(ask, lessThan(create), reason: 'спросить надо до регистрации');
  });
}
