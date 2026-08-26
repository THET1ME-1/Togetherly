import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/services/crash_noise.dart';

/// Панель крашей полезна, пока в ней мало шума. По данным Bugsink за июль
/// обрывы SSE (9674 события), сетевые сбои и мёртвые ссылки Firebase (130)
/// давали больше половины всех отчётов и топили настоящие падения.
void main() {
  group('шум не едет в Bugsink', () {
    test('обрыв SSE-подписки PocketBase', () {
      expect(
        isCrashNoise('ClientException: {url: https://togetherly.duckdns.org'
            '/api/realtime, isAbort: false, statusCode: 400}'),
        isTrue,
      );
    });

    test('нет сети у человека', () {
      expect(isCrashNoise('SocketException: Failed host lookup'), isTrue);
      expect(isCrashNoise('OS Error: Network is unreachable, errno = 101'),
          isTrue);
      expect(isCrashNoise('OS Error: Bad file descriptor, errno = 9'), isTrue);
    });

    test('запрет Android на старт фонового сервиса', () {
      expect(
        isCrashNoise('ForegroundServiceStartNotAllowedException: '
            'startForeground() not allowed'),
        isTrue,
      );
    });

    test('ссылка на выключенный Firebase Storage', () {
      expect(
        isCrashNoise('HttpException: Invalid statusCode: 402, '
            'uri = https://firebasestorage.googleapis.com/v0/b/x/o/y.jpg'),
        isTrue,
      );
    });
  });

  group('настоящие ошибки доезжают', () {
    test('падение по null', () {
      expect(isCrashNoise('Null check operator used on a null value'), isFalse);
    });

    test('ответ сервера с ошибкой на обычном роуте', () {
      expect(
        isCrashNoise('ClientException: {url: https://togetherly.duckdns.org'
            '/api/collections/memories/records, statusCode: 400}'),
        isFalse,
      );
    });

    test('402 не от Firebase глушить нельзя', () {
      expect(
        isCrashNoise('HttpException: Invalid statusCode: 402, '
            'uri = https://togetherly.duckdns.org/api/coins/buy'),
        isFalse,
      );
    });
  });

  group('фоновые ошибки помечаются нефатальными', () {
    test('отказ прав и незагрузившийся шрифт', () {
      expect(isBenignBackgroundError('permission-denied'), isTrue);
      expect(isBenignBackgroundError('Failed to load font Rubik'), isTrue);
    });

    test('обычное падение остаётся фатальным', () {
      expect(isBenignBackgroundError('RangeError: index out of range'), isFalse);
    });
  });

  group('штатный отказ роута — не ошибка', () {
    test('не хватает монет', () {
      // PocketBase SDK бросает исключение на любой не-2xx, поэтому «монет не
      // хватает» приезжает в панель наравне с падениями: 71 такое событие с
      // конца июня, 23 человека просто не смогли купить иконку.
      expect(
        isCrashNoise(ClientException(
          statusCode: 402,
          response: const {'error': 'insufficient', 'coins': 5},
          url: Uri.parse('https://togetherly.day/api/coins/purchase-icon'),
        )),
        isTrue,
      );
    });

    test('уже куплено — тоже штатный ответ', () {
      expect(
        isCrashNoise(ClientException(
          statusCode: 409,
          response: const {'error': 'alreadyOwned'},
          url: Uri.parse('https://togetherly.day/api/coins/purchase-feature'),
        )),
        isTrue,
      );
    });

    test('а вот отказ сервера остаётся ошибкой', () {
      expect(
        isCrashNoise(ClientException(
          statusCode: 500,
          response: const {'error': 'tx failed'},
          url: Uri.parse('https://togetherly.day/api/coins/purchase-icon'),
        )),
        isFalse,
      );
    });
  });

  group('Шум роутов монет', () {
    test('обрыв связи и отмена запроса в панель не идут', () {
      expect(
        isCoinsRouteNoise(
          'ClientException: {url: https://togetherly.day/api/coins/daily-bonus, '
          'isAbort: true, statusCode: 0, response: {}}',
        ),
        isTrue,
      );
    });

    test('окно перезапуска сервера — не баг приложения', () {
      for (final code in [502, 503, 504]) {
        expect(
          isCoinsRouteNoise(
            'ClientException: {url: https://togetherly.day/api/coins/daily-bonus, '
            'isAbort: false, statusCode: $code, response: {}}',
          ),
          isTrue,
          reason: 'код $code — это перезапуск или прокси, а не поломка клиента',
        );
      }
    });

    test('протухшая сессия чинится повтором, а не отчётом', () {
      expect(
        isCoinsRouteNoise(
          'ClientException: {url: https://togetherly.day/api/coins/daily-bonus, '
          'statusCode: 401, response: {code: 401, message: The request requires '
          'valid record authorization token.}}',
        ),
        isTrue,
      );
    });

    test('серверная ошибка транзакции доезжает до панели', () {
      expect(
        isCoinsRouteNoise(
          'ClientException: {url: https://togetherly.day/api/coins/daily-bonus, '
          'statusCode: 500, response: {error: tx failed, ok: false}}',
        ),
        isFalse,
        reason: 'tx failed — настоящая поломка экономики, её надо видеть',
      );
    });

    test('отказ по правилу (400) тоже виден', () {
      expect(
        isCoinsRouteNoise(
          'ClientException: {url: https://togetherly.day/api/coins/ad-grant, '
          'statusCode: 400, response: {error: bad kind}}',
        ),
        isFalse,
      );
    });
  });
}
