import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/config/sentry_config.dart';

/// Адрес краш-репортинга ходит только по HTTPS через домен.
///
/// В DSN стоял прямой `http://77.91.95.34:8000`. 25 июля на VPS включили ufw
/// (открыты 22, 80, 443, 8443, 8095), порт 8000 закрылся снаружи — и краши
/// перестали доходить совсем: свежее 1.17.0 в Bugsink нет ничего. Тест держит
/// адрес на домене, чтобы это не повторилось после правки конфига.
void main() {
  test('DSN идёт по HTTPS', () {
    expect(SentryConfig.dsn.startsWith('https://'), isTrue,
        reason: 'HTTP-порт Bugsink закрыт файрволом');
  });

  test('DSN указывает на домен, а не на IP с портом', () {
    final uri = Uri.parse(SentryConfig.dsn);
    expect(uri.host, 'bugsink.togetherly.day');
    expect(uri.hasPort, isFalse, reason: 'нестандартный порт снаружи закрыт');
    expect(RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(uri.host), isFalse);
  });

  test('в DSN есть ключ проекта и его номер', () {
    final uri = Uri.parse(SentryConfig.dsn);
    expect(uri.userInfo.length, 32);
    expect(uri.path, '/1');
  });
}
