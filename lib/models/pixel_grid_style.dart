/// Как рисовать пиксельную сетку при данном размере клетки.
///
/// Раньше рисовальщик просто выходил, если клетка меньше шести логических
/// пикселей. На iPhone холст 64×80 даёт клетку около 4,4 dp, и клеток не было
/// видно вовсе: кнопка сетки нажималась, подпись «64 × 80 · клетка 25 px» стояла,
/// а линий нет (жалоба 17.08.2026). Отсекались ровно те форматы, где сетка нужнее
/// всего — по мелкой клетке без направляющих не попасть пальцем.
///
/// Совсем убрать порог нельзя: при клетке в пару точек линии сливаются в серое
/// полотно и мешают больше, чем помогают. Поэтому порог опущен до 2,5 dp, а
/// тонкие клетки рисуются волосяной линией и слабее по тону.
class PixelGridStyle {
  const PixelGridStyle({
    required this.visible,
    required this.strokeWidth,
    required this.opacity,
  });

  final bool visible;
  final double strokeWidth;

  /// Прозрачность линии, 0…1.
  final double opacity;
}

/// Минимальная клетка, на которой сетка ещё читается.
const double kPixelGridMinCell = 2.5;

PixelGridStyle pixelGridStyle(double cellPx) {
  if (!cellPx.isFinite || cellPx < kPixelGridMinCell) {
    return const PixelGridStyle(visible: false, strokeWidth: 0, opacity: 0);
  }
  if (cellPx >= 6) {
    return const PixelGridStyle(visible: true, strokeWidth: 1, opacity: 0.08);
  }
  // Между 2,5 и 6: линия тоньше пикселя (волосяная) и бледнее, чтобы плотная
  // решётка читалась направляющими, а не заливкой.
  return const PixelGridStyle(visible: true, strokeWidth: 0.5, opacity: 0.06);
}
