import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/couple_stats_service.dart';

void main() {
  group('shiftHoursToLocal', () {
    test('поворачивает сутки на пояс читателя', () {
      final utc = List<int>.filled(24, 0);
      utc[18] = 7; // 18:00 UTC

      final local = shiftHoursToLocal(utc, const Duration(hours: 3));

      expect(local[21], 7);
      expect(local[18], 0);
    });

    test('через полночь часы не теряются', () {
      final utc = List<int>.filled(24, 0);
      utc[23] = 4;

      final local = shiftHoursToLocal(utc, const Duration(hours: 2));

      expect(local[1], 4);
      expect(local.fold<int>(0, (a, b) => a + b), 4);
    });

    test('западный пояс уводит час назад', () {
      final utc = List<int>.filled(24, 0);
      utc[2] = 5;

      final local = shiftHoursToLocal(utc, const Duration(hours: -5));

      expect(local[21], 5);
    });

    test('получасовой пояс округляется до часа', () {
      final utc = List<int>.filled(24, 0);
      utc[10] = 3;

      final local =
          shiftHoursToLocal(utc, const Duration(hours: 5, minutes: 30));

      expect(local[16], 3);
    });

    test('пустая гистограмма остаётся пустой', () {
      expect(shiftHoursToLocal(const [], const Duration(hours: 3)), isEmpty);
    });
  });
}
