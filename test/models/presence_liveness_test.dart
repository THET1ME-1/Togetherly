// Присутствие: канал вместо записи в базу, но старые сборки не теряются.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/presence_liveness.dart';

void main() {
  const now = 1786650000000; // произвольный момент, важна только разница
  int ago(Duration d) => now - d.inMilliseconds;

  group('кто в сети', () {
    test('свежий удар по каналу — в сети', () {
      expect(
        PresenceLiveness.isOnline(channelBeatMs: ago(const Duration(seconds: 5)), nowMs: now),
        isTrue,
      );
    });

    test('один пропущенный удар не гасит точку', () {
      expect(
        PresenceLiveness.isOnline(channelBeatMs: ago(const Duration(seconds: 30)), nowMs: now),
        isTrue,
      );
    });

    test('минута тишины — офлайн', () {
      expect(
        PresenceLiveness.isOnline(channelBeatMs: ago(const Duration(minutes: 1)), nowMs: now),
        isFalse,
      );
    });

    test('партнёр на старой сборке виден по отметке в базе', () {
      expect(
        PresenceLiveness.isOnline(storedSeenMs: ago(const Duration(seconds: 10)), nowMs: now),
        isTrue,
      );
    });

    test('берётся тот источник, что свежее', () {
      expect(
        PresenceLiveness.isOnline(
          channelBeatMs: ago(const Duration(minutes: 10)),
          storedSeenMs: ago(const Duration(seconds: 8)),
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('без признаков жизни — офлайн', () {
      expect(PresenceLiveness.isOnline(nowMs: now), isFalse);
    });

    test('отметка из будущего не считается за живую', () {
      expect(
        PresenceLiveness.isOnline(channelBeatMs: now + 600000, nowMs: now),
        isFalse,
        reason: 'часы телефона могут убежать вперёд — доверять такому нельзя',
      );
    });
  });

  group('когда видели в последний раз', () {
    test('берётся самый свежий из источников', () {
      expect(
        PresenceLiveness.lastSeenMs(
          channelBeatMs: ago(const Duration(minutes: 2)),
          storedSeenMs: ago(const Duration(minutes: 9)),
        ),
        ago(const Duration(minutes: 2)),
      );
    });

    test('нет ни одного — нечего показывать', () {
      expect(PresenceLiveness.lastSeenMs(), isNull);
    });
  });

  group('как часто пишем в базу', () {
    test('первый раз пишем сразу', () {
      expect(PresenceLiveness.shouldWriteLastSeen(nowMs: now), isTrue);
    });

    test('минуту спустя — рано', () {
      expect(
        PresenceLiveness.shouldWriteLastSeen(
            writtenAtMs: ago(const Duration(minutes: 1)), nowMs: now),
        isFalse,
      );
    });

    test('через пять минут — пора', () {
      expect(
        PresenceLiveness.shouldWriteLastSeen(
            writtenAtMs: ago(const Duration(minutes: 5)), nowMs: now),
        isTrue,
      );
    });

    test('пишем в двадцать пять раз реже прежнего heartbeat', () {
      final ratio = PresenceLiveness.lastSeenWrite.inSeconds / 12;
      expect(ratio, greaterThanOrEqualTo(25));
    });
  });
}
