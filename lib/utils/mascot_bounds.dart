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
///
/// [top] и [bottom] — полосы, куда маскоту нельзя: строка состояния сверху,
/// нижняя панель с безопасным полем снизу. Под панелью маскота не взять,
/// касание забирает она (TOG-15, обращение 411).
Offset clampMascotPosition(
  Offset position,
  Size screen,
  double half, {
  double top = 0,
  double bottom = 0,
}) {
  if (half <= 0) return position;
  final minY = top + half;
  final maxY = screen.height - bottom - half;
  if (screen.width <= half * 2 || maxY <= minY) return position;
  return Offset(
    position.dx.clamp(half, screen.width - half),
    position.dy.clamp(minY, maxY),
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
