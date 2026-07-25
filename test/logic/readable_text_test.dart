import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/readable_text.dart';

void main() {
  group('contrastRatio', () {
    test('чёрный и белый — предел 21', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
    });

    test('одинаковые цвета — 1', () {
      expect(
        contrastRatio(const Color(0xFF7C4DFF), const Color(0xFF7C4DFF)),
        closeTo(1, 0.001),
      );
    });
  });

  group('readableTextOn', () {
    test('тёмно-фиолетовый пузырь — белый текст', () {
      expect(readableTextOn(const Color(0xFF5B3FBF)), const Color(0xFFFFFFFF));
    });

    test('жёлтый пузырь — тёмный текст (раньше выдавал белый)', () {
      expect(readableTextOn(const Color(0xFFFFEB3B)), kDarkBubbleText);
    });

    test('салатовый пузырь — тёмный текст', () {
      expect(readableTextOn(const Color(0xFF8BC34A)), kDarkBubbleText);
    });

    test('пастельно-розовый — тёмный текст', () {
      expect(readableTextOn(const Color(0xFFF8BBD0)), kDarkBubbleText);
    });

    // 4.5 достижимы не на любом фоне: у насыщенного розового #E91E63 предел
    // 4.35 в обе стороны. Требуем лучшее из возможного и порог 3.0 (WCAG AA
    // для крупного текста) — пузырь набран 15px полужирным.
    test('выбранный цвет читаемее альтернативы', () {
      const backgrounds = [
        Color(0xFFFFEB3B),
        Color(0xFF8BC34A),
        Color(0xFF03A9F4),
        Color(0xFFFF5722),
        Color(0xFF9C27B0),
        Color(0xFF795548),
        Color(0xFFE91E63),
        Color(0xFF00BCD4),
      ];
      for (final bg in backgrounds) {
        final picked = readableTextOn(bg);
        final other =
            picked == const Color(0xFFFFFFFF) ? kDarkBubbleText : const Color(0xFFFFFFFF);
        expect(
          contrastRatio(bg, picked),
          greaterThanOrEqualTo(contrastRatio(bg, other)),
          reason: 'фон $bg',
        );
        expect(
          contrastRatio(bg, picked),
          greaterThanOrEqualTo(3.0),
          reason: 'фон $bg',
        );
      }
    });
  });
}
