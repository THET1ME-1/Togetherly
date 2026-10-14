// Сроки капсулы времени: быстрые кнопки «Месяц», «Полгода», «Год», какая из
// них выбрана, и сколько дней осталось до открытия.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/capsule_schedule.dart';

void main() {
  final now = DateTime(2026, 10, 14, 15, 30);

  group('дата быстрого срока', () {
    test('тот же день через месяц, полгода и год, в девять утра', () {
      expect(capsulePresetDate(now, CapsulePreset.month), DateTime(2026, 11, 14, 9));
      expect(capsulePresetDate(now, CapsulePreset.halfYear), DateTime(2027, 4, 14, 9));
      expect(capsulePresetDate(now, CapsulePreset.year), DateTime(2027, 10, 14, 9));
    });

    test('числа, которого нет в месяце, прижимается к последнему дню', () {
      // 31 февраля DateTime превращал в 3 марта: капсула «через полгода»
      // открывалась на три дня позже.
      expect(capsulePresetDate(DateTime(2026, 8, 31, 10), CapsulePreset.halfYear),
          DateTime(2027, 2, 28, 9));
      expect(capsulePresetDate(DateTime(2027, 8, 31, 10), CapsulePreset.halfYear),
          DateTime(2028, 2, 29, 9));
      expect(capsulePresetDate(DateTime(2027, 1, 31, 10), CapsulePreset.month),
          DateTime(2027, 2, 28, 9));
    });
  });

  group('какой срок выбран', () {
    test('дата быстрого срока узнаётся', () {
      for (final p in CapsulePreset.values) {
        expect(capsulePresetOf(capsulePresetDate(now, p), now), p);
      }
    });

    test('дата с барабанов — ни один из быстрых', () {
      expect(capsulePresetOf(DateTime(2027, 2, 14, 9), now), isNull);
    });
  });

  group('доля прошедшего срока', () {
    final sealed = DateTime(2026, 7, 12, 20);
    final opens = DateTime(2027, 2, 14, 9);

    test('от запечатывания до открытия по времени', () {
      expect(capsuleElapsedShare(sealed, opens, DateTime(2026, 10, 14, 12)),
          closeTo(0.43, 0.01));
    });

    test('за краями срока — ровно 0 и 1', () {
      expect(capsuleElapsedShare(sealed, opens, DateTime(2026, 7, 1)), 0);
      expect(capsuleElapsedShare(sealed, opens, DateTime(2027, 3, 1)), 1);
    });

    test('открытие не позже запечатывания — срок вышел', () {
      expect(capsuleElapsedShare(opens, sealed, now), 1);
    });
  });

  group('дней до открытия', () {
    test('считаются по календарю', () {
      expect(capsuleDaysLeft(DateTime(2027, 4, 14, 9), now), 182);
    });

    test('завтра утром — один день, хотя до девяти меньше суток', () {
      expect(capsuleDaysLeft(DateTime(2026, 10, 15, 9), DateTime(2026, 10, 14, 22)), 1);
    });

    test('в день открытия и после — ноль, не минус', () {
      expect(capsuleDaysLeft(DateTime(2026, 10, 14, 9), now), 0);
      expect(capsuleDaysLeft(DateTime(2026, 10, 1, 9), now), 0);
    });
  });
}
