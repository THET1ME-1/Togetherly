import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/login_methods.dart';
import 'package:love_app/models/partner_reset.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  group('способы входа', () {
    test('ответ сервера разбирается', () {
      final m = LoginMethods.fromJson({
        'password': true,
        'providers': ['google', 'google', 'apple'],
        'email': 'dima@gmail.com',
      });
      expect(m.password, isTrue);
      expect(m.providers, {'google', 'apple'});
      expect(m.email, 'dima@gmail.com');
      expect(m.count, 3);
    });

    test('кривой ответ не роняет экран', () {
      final m = LoginMethods.fromJson({'password': 'да', 'providers': 'google'});
      expect(m.password, isFalse);
      expect(m.providers, isEmpty);
    });

    test('на Android Apple не предлагаем, на iPhone предлагаем', () {
      const m = LoginMethods(password: true, providers: {});
      expect(m.tiles(ios: false), ['google', 'yandex']);
      expect(m.tiles(ios: true), ['google', 'yandex', 'apple']);
    });

    test('Apple, привязанный на iPhone, виден и на Android', () {
      const m = LoginMethods(password: false, providers: {'apple'});
      expect(m.tiles(ios: false), ['google', 'yandex', 'apple']);
    });

    test('счёт «из скольких» — пароль плюс плитки', () {
      const m = LoginMethods(password: true, providers: {'google'});
      expect(m.total(ios: false), 3);
      expect(m.total(ios: true), 4);
      expect(m.count, 2);
    });

    test('последний способ отвязать нельзя', () {
      const onlyGoogle = LoginMethods(password: false, providers: {'google'});
      expect(onlyGoogle.canUnlink('google'), isFalse);
      const withPassword = LoginMethods(password: true, providers: {'google'});
      expect(withPassword.canUnlink('google'), isTrue);
      const two = LoginMethods(password: false, providers: {'google', 'yandex'});
      expect(two.canUnlink('yandex'), isTrue);
      expect(two.canUnlink('apple'), isFalse);
    });

    test('один способ — аккаунт под угрозой', () {
      expect(const LoginMethods(password: true, providers: {}).atRisk, isTrue);
      expect(const LoginMethods(password: true, providers: {'google'}).atRisk, isFalse);
    });
  });

  group('код через партнёра', () {
    test('код делится на две тройки', () {
      expect(formatResetCode('482913'), '482 913');
      expect(formatResetCode('12'), '12');
    });

    test('запрос у партнёра разбирается и считает остаток', () {
      final at = DateTime.utc(2026, 11, 5, 12, 40);
      final p = PendingReset.fromJson({
        'uid': 'u1',
        'name': 'Дима',
        'gender': 'male',
        'code': '482913',
        'at': at.millisecondsSinceEpoch,
        'expiresAt': at.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      })!;
      expect(p.name, 'Дима');
      expect(p.female, isFalse);
      expect(p.left(at.add(const Duration(minutes: 3))), const Duration(minutes: 7));
      expect(p.left(at.add(const Duration(minutes: 11))), Duration.zero);
    });

    test('пустой запрос — ничего не показываем', () {
      expect(PendingReset.fromJson(null), isNull);
      expect(PendingReset.fromJson({'code': ''}), isNull);
      expect(PendingReset.fromJson({'code': '12345'}), isNull);
    });

    test('причина отказа сервера по коду ответа', () {
      ClientException err(int status, Map<String, dynamic> body) =>
          ClientException(statusCode: status, response: body);
      expect(partnerResetFailureOf(err(400, {'code': 'wrong', 'left': 3})),
          PartnerResetFailure.wrong);
      expect(triesLeftOf(err(400, {'code': 'wrong', 'left': 3})), 3);
      expect(partnerResetFailureOf(err(410, {'code': 'expired'})),
          PartnerResetFailure.expired);
      expect(partnerResetFailureOf(err(429, {'code': 'gap'})),
          PartnerResetFailure.gap);
      expect(partnerResetFailureOf(err(429, {'code': 'locked'})),
          PartnerResetFailure.locked);
      expect(partnerResetFailureOf(err(0, {})), PartnerResetFailure.network);
      expect(partnerResetFailureOf(StateError('x')), PartnerResetFailure.unknown);
    });
  });
}
