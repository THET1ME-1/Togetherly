import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/fcm_service.dart';

void main() {
  group('socketServiceNeeded', () {
    test('пуши работают — фоновый сервис не поднимаем', () {
      // Ради этого всё и затевалось: у человека пропадает строка
      // «Togetherly на связи» из шторки.
      expect(
        socketServiceNeeded(hasGoogleServices: true, hasToken: true),
        isFalse,
      );
    });

    test('прошивка без сервисов Google — остаётся прежний путь', () {
      expect(
        socketServiceNeeded(hasGoogleServices: false, hasToken: false),
        isTrue,
      );
    });

    test('сервисы есть, а токена нет — тоже прежний путь', () {
      // Токен не пришёл (нет сети на первом запуске, отказ регистрации):
      // остаться без уведомлений хуже, чем со строкой в шторке.
      expect(
        socketServiceNeeded(hasGoogleServices: true, hasToken: false),
        isTrue,
      );
    });

    test('токен без сервисов Google не считается доставкой', () {
      // Пережиток прошлой установки в prefs не должен выключать сервис.
      expect(
        socketServiceNeeded(hasGoogleServices: false, hasToken: true),
        isTrue,
      );
    });
  });

  group('вердикт FCM приходит позже пары', () {
    // Скриншот 19.08.2026: «Togetherly на связи» висит в шторке у человека, у
    // которого fcm_token в базе ЕСТЬ. Причина — гонка: пара поднимается из
    // локального кэша мгновенно, а токен FCM едет через натив и сеть Google
    // секунды. `start()` спрашивал `ready` раньше ответа и каждый запуск
    // поднимал сервис заново.
    test('settled завершается, даже когда токена не будет', () async {
      // В тесте платформа не Android: `start()` выходит сразу, и ждущая
      // сторона обязана разблокироваться, иначе доставка не поднимется вовсе.
      await FcmService.instance.start();
      await FcmService.instance.settled.timeout(const Duration(seconds: 2));
    });

    test('вердикт можно ждать сколько угодно раз', () async {
      await FcmService.instance.settled.timeout(const Duration(seconds: 2));
      await FcmService.instance.settled.timeout(const Duration(seconds: 2));
    });
  });

  group('сервис, поднятый системой после перезагрузки', () {
    // `autoRunOnBoot` возвращает сервис к жизни без всякого решения: телефон
    // перезагрузили — строка в шторке снова тут, хотя пуши работают.
    test('гасим себя, когда прошлый запуск отметил живые пуши', () {
      expect(bootedServiceShouldStop(true), isTrue);
    });

    test('отметки нет — работаем, как работали', () {
      expect(bootedServiceShouldStop(false), isFalse);
      expect(bootedServiceShouldStop(null), isFalse);
    });
  });

  group('порядок в самом сервисе', () {
    final source =
        File('lib/services/push_background_service.dart').readAsStringSync();

    test('решение принимается после вердикта FCM, а не до', () {
      final from = source.indexOf('Future<void> start({');
      final to = source.indexOf('Future<void> stop()');
      expect(from, greaterThan(-1), reason: 'старт сервиса на месте');
      expect(to, greaterThan(from), reason: 'остановка идёт следом');
      final body = source.substring(from, to);
      final wait = body.indexOf('FcmService.instance.settled');
      final decide = body.indexOf('socketServiceNeeded(');
      expect(wait, greaterThan(-1), reason: 'вердикта ждём');
      expect(decide, greaterThan(wait),
          reason: 'спрашиваем готовность только после вердикта');
    });

    test('оживать после перезагрузки решает тот же вердикт', () {
      expect(source, contains('autoRunOnBoot: autoRunOnBoot'));
      expect(source, contains('bootedServiceShouldStop('),
          reason: 'изолят гасит себя, когда пуши работают');
    });
  });
}
