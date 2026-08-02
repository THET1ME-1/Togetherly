import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_sync.dart';

/// Совместный просмотр: кто задаёт время и когда за ним догонять.
///
/// Отзыв из Play (2 августа, 1.21.1): «примерно каждые 5-10 секунд
/// перематывает видео на пару секунд, 2-3 раза так». Причина — обоюдный
/// heartbeat: оба слали свою позицию и оба друг за другом прыгали назад на
/// величину сетевой задержки.
void main() {
  group('leadsSync', () {
    test('ведущий один и тот же у обеих сторон', () {
      expect(leadsSync(me: 'aaa', peer: 'bbb'), isTrue);
      expect(leadsSync(me: 'bbb', peer: 'aaa'), isFalse);
    });

    test('без партнёра ведущим остаётся сам', () {
      expect(leadsSync(me: 'aaa', peer: ''), isTrue);
    });

    test('одинаковые идентификаторы никого не выбирают ведущим дважды', () {
      // Своё же эхо не должно превращать клиента в ведомого.
      expect(leadsSync(me: 'aaa', peer: 'aaa'), isTrue);
    });
  });

  group('catchUpTarget', () {
    const drift = Duration(milliseconds: 1500);

    test('расхождение в пределах допуска не двигает плеер', () {
      expect(
        catchUpTarget(
          mine: const Duration(seconds: 30),
          theirs: const Duration(milliseconds: 30800),
          playing: true,
          drift: drift,
        ),
        isNull,
      );
    });

    test('отстал — догоняем с запасом на дорогу сообщения', () {
      // Пока «сейчас 40» летело, ведущий ушёл дальше; прыжок ровно в 40
      // оставил бы нас позади и вызвал новый прыжок через три секунды.
      final target = catchUpTarget(
        mine: const Duration(seconds: 30),
        theirs: const Duration(seconds: 40),
        playing: true,
        drift: drift,
      );
      expect(target, isNotNull);
      expect(target!.inMilliseconds, greaterThan(40000));
      expect(target.inMilliseconds, lessThan(41000));
    });

    test('на паузе поправку не добавляем', () {
      expect(
        catchUpTarget(
          mine: const Duration(seconds: 30),
          theirs: const Duration(seconds: 40),
          playing: false,
          drift: drift,
        ),
        const Duration(seconds: 40),
      );
    });

    test('убежал вперёд — тоже возвращаемся к ведущему', () {
      final target = catchUpTarget(
        mine: const Duration(seconds: 50),
        theirs: const Duration(seconds: 40),
        playing: true,
        drift: drift,
      );
      expect(target, isNotNull);
      expect(target!.inSeconds, 40);
    });

    test('отрицательное время не отдаём', () {
      expect(
        catchUpTarget(
          mine: const Duration(seconds: 10),
          theirs: const Duration(milliseconds: -500),
          playing: false,
          drift: drift,
        ),
        Duration.zero,
      );
    });
  });
}
