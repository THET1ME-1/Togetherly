import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cycle_consent.dart';

/// Данные цикла — особая категория и по закону Молдовы № 133/2011, и по GDPR:
/// на них нужно отдельное явное согласие, а не общее «принимаю политику».
/// Здесь проверяется, когда его спрашивать и что значит отзыв.
void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  group('CycleConsent', () {
    test('без записи согласие спрашивают', () {
      expect(const CycleConsent.absent().granted, isFalse);
      expect(const CycleConsent.absent().needsAsking, isTrue);
    });

    test('данное согласие больше не спрашивают', () {
      final c = CycleConsent.granted(at: now, version: kCycleConsentVersion);
      expect(c.granted, isTrue);
      expect(c.needsAsking, isFalse);
    });

    test('отозванное согласие закрывает раздел и спрашивает снова', () {
      final c = CycleConsent.granted(at: now, version: kCycleConsentVersion)
          .withdrawn(at: now.add(const Duration(days: 1)));
      expect(c.granted, isFalse);
      expect(c.needsAsking, isTrue);
      expect(c.withdrawnAt, isNotNull);
    });

    test('согласие на старую редакцию просят заново', () {
      // Изменили формулировку — старое согласие уже не про этот текст.
      final c = CycleConsent.granted(at: now, version: kCycleConsentVersion - 1);
      expect(c.granted, isFalse);
      expect(c.needsAsking, isTrue);
    });

    test('переживает круг через хранилище', () {
      final c = CycleConsent.granted(at: now, version: kCycleConsentVersion);
      final back = CycleConsent.fromMap(c.toMap());
      expect(back.granted, isTrue);
      expect(back.grantedAt, now);
      expect(back.version, kCycleConsentVersion);
    });

    test('мусор в хранилище читается как отсутствие согласия', () {
      expect(CycleConsent.fromMap(const {}).needsAsking, isTrue);
      expect(CycleConsent.fromMap(const {'granted_at': 'не дата'}).granted,
          isFalse);
    });
  });
}
