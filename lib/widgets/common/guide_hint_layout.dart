import 'dart:math' as math;
import 'dart:ui';

/// Где на экране встают облачко-гид и пузырь подсказки.
///
/// Облачко садится над кнопкой, если она в нижней половине экрана, и под ней
/// — если в верхней; по горизонтали чуть в сторону середины, чтобы смотреть
/// на кнопку наискосок, а не закрывать её. Пузырь встаёт сбоку от облачка, со
/// стороны середины экрана. Анимация облачка выбирается по тому, где кнопка.
class GuideHintLayout {
  const GuideHintLayout({required this.cloud, required this.bubbleLeft, required this.bubbleTop, required this.bubbleWidth, required this.art, this.bubbleBottom});

  final Rect cloud;
  final double bubbleLeft;
  final double bubbleTop;
  final double bubbleWidth;

  /// Облачко над кнопкой: пузырь растёт вверх от этой кромки, а не вниз от
  /// [bubbleTop]. Высоту пузыря задаёт текст, и длинный, растущий вниз,
  /// ложился на кнопку и её соседей. null — пузырь растёт вниз.
  final double? bubbleBottom;

  /// Имя анимации облачка: `hint_down_right`, `hint_up_left`…
  final String art;
}

/// Сторона холста облачка в подсказке.
const double guideHintCloud = 104;

/// Высота пузыря, под которую оставляется место, когда сбоку не помещается.
const double guideHintBubbleHeight = 96;

/// [below] ставит облачко под кнопкой (true) или над ней (false) явно, когда
/// экран знает, где у него пусто: на экране приглашения под «Ввести код»
/// свободно, а над ней лежит сам код, и пузырь закрывал бы его.
GuideHintLayout guideHintLayout({required Rect target, required Size screen, bool? below}) {
  const c = guideHintCloud, gap = 8.0, edge = 8.0;
  final tx = target.center.dx, ty = target.center.dy;
  below ??= ty < screen.height / 2;
  final top = below ? target.bottom + gap : target.top - gap - c;
  final right = tx > screen.width / 2;
  final left = (right ? tx - c * 0.95 : tx - c * 0.05).clamp(edge, screen.width - edge - c);
  final cloud = Rect.fromLTWH(left, top, c, c);

  final width = math.min(220.0, screen.width - c - 3 * edge);
  final cloudOnRight = cloud.center.dx >= screen.width / 2;
  var bLeft = cloudOnRight ? cloud.left - width - 2 : cloud.right + 2;
  var bTop = cloud.top + 10;
  bLeft = bLeft.clamp(edge, screen.width - edge - width);
  // Сбоку не поместилось — пузырь встаёт над облачком (или под ним у верхних
  // кнопок), лишь бы не закрывать ни облачко, ни кнопку.
  final bubble = Rect.fromLTWH(bLeft, bTop, width, guideHintBubbleHeight);
  final overCloud = bubble.overlaps(cloud.deflate(14));
  if (overCloud) {
    bTop = below ? cloud.bottom + 4 : cloud.top - guideHintBubbleHeight - 4;
  }
  // Над кнопкой пузырь растёт вверх: сбоку от облачка — от его нижней кромки,
  // над облачком — от верхней.
  final double? bBottom = below ? null : (overCloud ? cloud.top - 4 : cloud.bottom);

  final dx = tx - cloud.center.dx, dy = ty - cloud.center.dy;
  final String art;
  if (dy > 0) {
    art = dx.abs() < c * 0.25 ? 'hint_down' : (dx > 0 ? 'hint_down_right' : 'hint_down_left');
  } else {
    art = dx >= 0 ? 'hint_up_right' : 'hint_up_left';
  }
  return GuideHintLayout(cloud: cloud, bubbleLeft: bLeft, bubbleTop: bTop, bubbleWidth: width, art: art, bubbleBottom: bBottom);
}
