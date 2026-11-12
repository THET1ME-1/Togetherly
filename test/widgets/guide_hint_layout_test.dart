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

  // Обход нижнего меню (12.11.2026): пузырь с текстом в пять строк выше
  // расчётных 96 точек, рос вниз и закрывал соседние кнопки меню, а над
  // облачком садился на кнопку «Понятно» облачком. Над кнопкой пузырь растёт
  // вверх от нижней кромки, и высота текста ему не страшна.
  test('над кнопкой пузырь растёт вверх и не заходит на кнопку', () {
    for (final x in [24.0, 90.0, 160.0, 230.0, 300.0]) {
      final tab = Rect.fromLTWH(x, 700, 48, 48);
      final l = guideHintLayout(target: tab, screen: screen);
      expect(l.bubbleBottom, isNotNull, reason: 'кнопка внизу: пузырь обязан расти вверх');
      expect(l.bubbleBottom!, lessThanOrEqualTo(tab.top), reason: 'пузырь заходит на кнопку $tab');
      // Если пузырь стоит по высоте облачка, он сбоку от него, иначе — над ним.
      final beside = l.bubbleLeft >= l.cloud.right - 14 || l.bubbleLeft + l.bubbleWidth <= l.cloud.left + 14;
      if (!beside) {
        expect(l.bubbleBottom!, lessThanOrEqualTo(l.cloud.top), reason: 'пузырь над облачком лёг на него: $tab');
      }
    }
  });

  test('под кнопкой пузырь растёт вниз, как раньше', () {
    final l = guideHintLayout(target: const Rect.fromLTWH(40, 80, 48, 48), screen: screen);
    expect(l.bubbleBottom, isNull);
  });
}
