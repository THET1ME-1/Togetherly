import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/watch_room_load.dart';

/// Код комнаты обязан догрузиться сам.
///
/// Жалоба со снимком 16.08.2026 («нет кода»): на экране совместного просмотра в
/// строке «Партнёр смотрит в браузере?» стоит многоточие. Это индикатор
/// загрузки, которая не закончилась: код спрашивался ровно один раз при
/// открытии экрана. Сорвался запрос, не поднялась ещё сессия, не доехал id
/// пары — и человек остаётся с многоточием, а кнопка копирования мёртвая.
void main() {
  group('когда пробовать снова', () {
    test('код получен — повторять незачем', () {
      expect(watchRoomShouldRetry(code: 'wvkxekzy', attempt: 0), isFalse);
    });

    test('пусто — пробуем ещё', () {
      expect(watchRoomShouldRetry(code: '', attempt: 0), isTrue);
      expect(watchRoomShouldRetry(code: '', attempt: 2), isTrue);
    });

    test('после последней попытки сдаёмся и показываем прочерк', () {
      expect(
        watchRoomShouldRetry(code: '', attempt: watchRoomMaxAttempts),
        isFalse,
        reason: 'бесконечный круг запросов — то, чем клиент валил сервер в августе',
      );
    });
  });

  group('пауза перед повтором', () {
    test('растёт с каждой неудачей', () {
      final first = watchRoomRetryDelay(0);
      final second = watchRoomRetryDelay(1);
      final third = watchRoomRetryDelay(2);
      expect(first.inMilliseconds, greaterThan(0));
      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
    });

    test('первая пауза короткая — человек смотрит на экран', () {
      expect(watchRoomRetryDelay(0).inSeconds, lessThanOrEqualTo(2));
    });

    test('и не разрастается без края', () {
      expect(watchRoomRetryDelay(99).inSeconds, lessThanOrEqualTo(30));
    });
  });
}
