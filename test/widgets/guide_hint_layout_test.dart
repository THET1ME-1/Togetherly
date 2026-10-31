import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/guide_hint_layout.dart';

/// Облачко-гид прилетает к кнопке, о которой подсказка, смотрит на неё, а
/// рядом пузырь с текстом. Облачко не должно закрывать саму кнопку, ни оно,
/// ни пузырь не должны вылезать за экран, и смотрит облачко туда, где кнопка.
void main() {
  const screen = Size(360, 760);

  void inside(GuideHintLayout l) {
    final screenRect = Offset.zero & screen;
    expect(screenRect.contains(l.cloud.topLeft) && screenRect.contains(l.cloud.bottomRight), isTrue, reason: 'облачко за экраном: ${l.cloud}');
    expect(l.bubbleLeft, greaterThanOrEqualTo(8));
    expect(l.bubbleLeft + l.bubbleWidth, lessThanOrEqualTo(screen.width - 8));
  }

  test('кнопка внизу справа — облачко над ней слева и смотрит вниз вправо', () {
    const fab = Rect.fromLTWH(292, 690, 56, 56);
    final l = guideHintLayout(target: fab, screen: screen);
    inside(l);
    expect(l.cloud.overlaps(fab), isFalse);
    expect(l.cloud.bottom, lessThanOrEqualTo(fab.top));
    expect(l.art, 'hint_down_right');
  });

  test('счётчик наверху — облачко под ним и смотрит вверх', () {
    const counter = Rect.fromLTWH(120, 40, 132, 32);
    final l = guideHintLayout(target: counter, screen: screen);
    inside(l);
    expect(l.cloud.overlaps(counter), isFalse);
    expect(l.cloud.top, greaterThanOrEqualTo(counter.bottom));
    expect(l.art, startsWith('hint_up'));
  });

  test('кнопка внизу слева — облачко смотрит вниз влево', () {
    const btn = Rect.fromLTWH(12, 600, 68, 76);
    final l = guideHintLayout(target: btn, screen: screen);
    inside(l);
    expect(l.cloud.overlaps(btn), isFalse);
    expect(l.art, anyOf('hint_down_left', 'hint_down'));
  });

  test('пузырь не налезает на облачко', () {
    for (final t in const [Rect.fromLTWH(292, 690, 56, 56), Rect.fromLTWH(120, 40, 132, 32), Rect.fromLTWH(240, 440, 68, 76)]) {
      final l = guideHintLayout(target: t, screen: screen);
      final bubble = Rect.fromLTWH(l.bubbleLeft, l.bubbleTop, l.bubbleWidth, 80);
      expect(bubble.overlaps(l.cloud.deflate(14)), isFalse, reason: 'цель $t');
    }
  });
}
