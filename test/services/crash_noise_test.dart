import 'package:flutter_test/flutter_test.dart';
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
}
