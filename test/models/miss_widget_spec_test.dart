import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/miss_widget_spec.dart';

/// Виджет «Скучаю»: кегль числа и раскладка плиток.
///
/// На снимке 20.09.2026 «1000» разорвалось на две строки — «100» и «0» под
/// ним. Кегль был прибит гвоздями (28dp), и ужиматься числу было нечем.
void main() {
  group('кегль числа', () {
    test('короткое число берёт весь кегль', () {
      expect(missCountSize(0, base: 30), 30);
      expect(missCountSize(7, base: 30), 30);
      expect(missCountSize(98, base: 30), 30);
    });

    test('трёхзначное ужимается, четырёхзначное ещё сильнее', () {
      final three = missCountSize(198, base: 30);
      final four = missCountSize(1000, base: 30);
      expect(three, lessThan(30));
      expect(four, lessThan(three));
    });

    test('пятизначное не сваливается в нечитаемую мелочь', () {
      expect(missCountSize(99999, base: 30), greaterThanOrEqualTo(16));
    });

    test('кегль растёт вместе с базой большого размера', () {
      expect(missCountSize(1000, base: 44),
          greaterThan(missCountSize(1000, base: 30)));
    });

    test('отрицательного счёта не бывает, но он не ломает расчёт', () {
      expect(missCountSize(-5, base: 30), lessThanOrEqualTo(30));
    });
  });

  group('счёт словами', () {
    test('тысячи сокращаются, чтобы не рвать плитку', () {
      expect(missCountText(999), '999');
      expect(missCountText(1000), '1000');
      expect(missCountText(12345), '12,3K');
      expect(missCountText(1200000), '1,2M');
    });

    test('ноль остаётся нулём, а не пустотой', () {
      expect(missCountText(0), '0');
    });
  });
}
