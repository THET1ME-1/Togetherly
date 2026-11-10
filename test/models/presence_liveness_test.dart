// Присутствие: канал вместо записи в базу, но старые сборки не теряются.
import 'dart:io';
import 'dart:ui' show AppLifecycleState;

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

  // Обращение 624 (10.11.2026): партнёр спал, а в приложении «появился в сети и
  // сразу пропал». Тихий пуш будит закрытое приложение на iPhone целиком, главный
  // экран строится в фоне и до этой правки сразу слал «я жив» с таймером раз
  // в 20 с: партнёр видел «в сети», пока iOS не усыпит процесс.
  group('«я жив» только с экрана', () {
    test('приложение на экране — шлём', () {
      expect(PresenceLiveness.shouldBeat(AppLifecycleState.resumed), isTrue);
    });

    test('разбужено в фоне или свёрнуто — молчим', () {
      for (final s in [
        null,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(PresenceLiveness.shouldBeat(s), isFalse, reason: '$s');
      }
    });

    test('запуск присутствия спрашивает состояние приложения', () {
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      final start = src.substring(src.indexOf('void start('), src.indexOf('void stop('));
      expect(start, contains('shouldBeat('),
          reason: 'start() не должен слать «я жив», пока приложение не на экране');
    });
  });
}
