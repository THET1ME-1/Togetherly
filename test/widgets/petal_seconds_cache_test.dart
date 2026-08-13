import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/petal_clock.dart';

void main() {
  group('petalSecondKey', () {
    test('внутри одной секунды ключ не меняется', () {
      final a = DateTime(2026, 8, 13, 19, 30, 12, 100);
      final b = DateTime(2026, 8, 13, 19, 30, 12, 900);

      expect(petalSecondKey(a), petalSecondKey(b));
    });

    test('новая секунда — новый ключ', () {
      final a = DateTime(2026, 8, 13, 19, 30, 12, 900);
      final b = DateTime(2026, 8, 13, 19, 30, 13, 0);

      expect(petalSecondKey(a), isNot(petalSecondKey(b)));
    });

    test('соседние минуты не совпадают', () {
      final a = DateTime(2026, 8, 13, 19, 30, 59);
      final b = DateTime(2026, 8, 13, 19, 31, 0);

      expect(petalSecondKey(a), isNot(petalSecondKey(b)));
    });
  });
}
