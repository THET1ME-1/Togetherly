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
}
