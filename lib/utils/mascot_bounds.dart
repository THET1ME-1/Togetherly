import 'dart:ui' show Offset, Size;

/// Держит маскота в пределах экрана.
///
/// Прямой `clamp(half, width - half)` падает с «Invalid argument(s): 65.0», как
/// только экран оказывается у́же двух радиусов — а так бывает не только на
/// узких телефонах: в момент, когда виджет уже смонтирован, а размер ещё не
/// известен, `MediaQuery` отдаёт нули, и нижняя граница становится больше
/// верхней. Падало это на живой сборке.
///
/// В таком случае позицию не трогаем: маскот встанет на место следующим
/// пересчётом, когда размер станет настоящим.
Offset clampMascotPosition(Offset position, Size screen, double half) {
  if (half <= 0) return position;
  if (screen.width <= half * 2 || screen.height <= half * 2) return position;
  return Offset(
    position.dx.clamp(half, screen.width - half),
    position.dy.clamp(half, screen.height - half),
  );
}

/// Тап это был или перетаскивание.
///
/// Жест по маскоту разбирает `onScale*`: распознаватель масштаба забирает
/// касание себе на первом же микродвижении пальца, поэтому `onTap` у
/// `GestureDetector` до арены не доживал — маскот таскался, но не открывал
/// ничего (жалоба 13 августа 2026). Решение простое: короткое касание, за
/// которое палец почти не сдвинулся, считаем тапом сами.
bool mascotGestureIsTap({
  required double travel,
  required Duration held,
  double slop = 12,
  Duration limit = const Duration(milliseconds: 400),
}) =>
    travel <= slop && held < limit;
