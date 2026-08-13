// Отступление после неудачной записи — заплатка от шторма 13 августа 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/upsert_backoff.dart';

void main() {
  group('длительность паузы', () {
    test('без неудач паузы нет', () {
      expect(upsertBackoffFor(0), Duration.zero);
      expect(upsertBackoffFor(-1), Duration.zero);
    });

    test('первая неудача — две секунды, дальше вдвое', () {
      expect(upsertBackoffFor(1), const Duration(seconds: 2));
      expect(upsertBackoffFor(2), const Duration(seconds: 4));
      expect(upsertBackoffFor(3), const Duration(seconds: 8));
      expect(upsertBackoffFor(5), const Duration(seconds: 32));
    });

    test('пауза упирается в пять минут и дальше не растёт', () {
      expect(upsertBackoffFor(20), const Duration(seconds: 256));
      expect(upsertBackoffFor(100).inSeconds, lessThanOrEqualTo(300));
    });
  });

  group('кто сейчас имеет право стучаться', () {
    final t0 = DateTime(2026, 8, 13, 23, 0, 0);

    test('нетронутый ключ пропускается сразу', () {
      final b = UpsertBackoff();
      expect(b.allows('widget_data|me', now: t0), isTrue);
    });

    test('после неудачи ключ молчит, потом снова пробует', () {
      final b = UpsertBackoff();
      b.failed('widget_data|me', now: t0);
      expect(b.allows('widget_data|me', now: t0.add(const Duration(seconds: 1))), isFalse);
      expect(b.allows('widget_data|me', now: t0.add(const Duration(seconds: 3))), isTrue);
    });

    test('неудачи подряд удлиняют тишину', () {
      final b = UpsertBackoff();
      b.failed('k', now: t0);
      b.failed('k', now: t0);
      b.failed('k', now: t0);
      expect(b.failuresOf('k'), 3);
      expect(b.allows('k', now: t0.add(const Duration(seconds: 5))), isFalse);
      expect(b.allows('k', now: t0.add(const Duration(seconds: 9))), isTrue);
    });

    test('удачная запись обнуляет счёт', () {
      final b = UpsertBackoff();
      b.failed('k', now: t0);
      b.failed('k', now: t0);
      b.succeeded('k');
      expect(b.failuresOf('k'), 0);
      expect(b.allows('k', now: t0), isTrue);
    });

    test('паузы одного ключа не мешают другому', () {
      final b = UpsertBackoff();
      b.failed('live_location|me', now: t0);
      expect(b.allows('live_location|me', now: t0), isFalse);
      expect(b.allows('widget_data|me', now: t0), isTrue);
    });

    test('смена аккаунта снимает все паузы', () {
      final b = UpsertBackoff();
      b.failed('k', now: t0);
      b.clear();
      expect(b.allows('k', now: t0), isTrue);
    });
  });
}
