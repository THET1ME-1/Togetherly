import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/waiting_state.dart';

void main() {
  group('залипшее ожидание', () {
    test('пустое место — ждём', () {
      expect(waitingIsActive(flag: true, partners: 0), isTrue);
    });

    test('партнёр уже вошёл — ждать больше некого', () {
      // Он входит обычным кодом приглашения, и флаг ожидания на сервере
      // остаётся поднятым. Экран показывал «Ждём человека» поверх живой пары,
      // а «Больше не жду» отбивалось сервером: место-то занято.
      expect(waitingIsActive(flag: true, partners: 1), isFalse);
    });

    test('без флага не ждём никогда', () {
      expect(waitingIsActive(flag: false, partners: 0), isFalse);
    });
  });
}
