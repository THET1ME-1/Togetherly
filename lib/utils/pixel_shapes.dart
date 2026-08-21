/// Фигуры для пиксельного холста: линия, прямоугольник, эллипс, треугольник —
/// разложенные по клеткам сетки.
///
/// Зачем отдельно от обычной отрисовки: на пиксельном холсте фигура рисовалась
/// теми же `drawOval` и `drawRect`, что и на гладком, и поверх клеток ложилась
/// плавная кривая с полупрозрачными краями. Выглядело так, будто круг нарисован
/// не в этом редакторе.
///
/// Считаем не «как выглядит», а «какие клетки закрашены»: результат — набор
/// номеров клеток (`y * cols + x`). Такую функцию легко проверить тестами и
/// одинаково использовать и на холсте, и в превью галереи.
library;

import 'dart:math' as math;

enum PixelShape { line, rect, ellipse, triangle }

/// Клетки, которые закрашивает фигура из угла (x0,y0) в угол (x1,y1).
///
/// [filled] — залить фигуру целиком или оставить контур. Клетки за пределами
/// холста отбрасываются: человек может увести палец за край, и фигура должна
/// просто обрезаться, а не портить соседние строки заворотом координат.
Set<int> pixelShapeCells({
  required PixelShape shape,
  required int x0,
  required int y0,
  required int x1,
  required int y1,
  required int cols,
  required int rows,
  required bool filled,
}) {
  final cells = <int>{};
  if (cols < 1 || rows < 1) return cells;

  void put(int x, int y) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) return;
    cells.add(y * cols + x);
  }

  switch (shape) {
    case PixelShape.line:
      _line(x0, y0, x1, y1, put);
    case PixelShape.rect:
      _rect(x0, y0, x1, y1, filled, put);
    case PixelShape.ellipse:
      _spans(_ellipseSpans(x0, y0, x1, y1), filled, put);
    case PixelShape.triangle:
      _spans(_triangleSpans(x0, y0, x1, y1), filled, put);
  }
  return cells;
}

/// Отрезок по Брезенхэму: без него быстрое движение оставляет в линии дыры.
void _line(int x0, int y0, int x1, int y1, void Function(int, int) put) {
  var x = x0, y = y0;
  final dx = (x1 - x0).abs(), sx = x0 < x1 ? 1 : -1;
  final dy = -(y1 - y0).abs(), sy = y0 < y1 ? 1 : -1;
  var err = dx + dy;
  while (true) {
    put(x, y);
    if (x == x1 && y == y1) break;
    final e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y += sy;
    }
  }
}

void _rect(int x0, int y0, int x1, int y1, bool filled,
    void Function(int, int) put) {
  final left = x0 < x1 ? x0 : x1;
  final right = x0 < x1 ? x1 : x0;
  final top = y0 < y1 ? y0 : y1;
  final bottom = y0 < y1 ? y1 : y0;

  if (filled) {
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        put(x, y);
      }
    }
    return;
  }
  for (var x = left; x <= right; x++) {
    put(x, top);
    put(x, bottom);
  }
  for (var y = top; y <= bottom; y++) {
    put(left, y);
    put(right, y);
  }
}

/// Строка фигуры: от какой клетки до какой она тянется.
typedef _Span = ({int y, int left, int right});

/// Контур из строк: у каждой строки берём края, а между соседними строками
/// достраиваем вертикаль. Без этого на пологих участках круга контур
/// рассыпается на отдельные точки — как пунктир.
void _spans(List<_Span> spans, bool filled, void Function(int, int) put) {
  if (spans.isEmpty) return;
  if (filled) {
    for (final s in spans) {
      for (var x = s.left; x <= s.right; x++) {
        put(x, s.y);
      }
    }
    return;
  }

  for (var i = 0; i < spans.length; i++) {
    final s = spans[i];
    // Первая и последняя строки — целиком: это верх и низ фигуры.
    if (i == 0 || i == spans.length - 1) {
      for (var x = s.left; x <= s.right; x++) {
        put(x, s.y);
      }
      continue;
    }
    put(s.left, s.y);
    put(s.right, s.y);

    // Досыпаем ступеньку до соседней строки, чтобы контур был непрерывным.
    final prev = spans[i - 1];
    if ((prev.left - s.left).abs() > 1) {
      final from = prev.left < s.left ? prev.left : s.left;
      final to = prev.left < s.left ? s.left : prev.left;
      for (var x = from; x <= to; x++) {
        put(x, s.y);
      }
    }
    if ((prev.right - s.right).abs() > 1) {
      final from = prev.right < s.right ? prev.right : s.right;
      final to = prev.right < s.right ? s.right : prev.right;
      for (var x = from; x <= to; x++) {
        put(x, s.y);
      }
    }
  }
}

/// Эллипс считаем построчно по уравнению, а не алгоритмом средней точки:
/// строки получаются сплошными (заливка без дыр), а верх и низ — зеркальными.
List<_Span> _ellipseSpans(int x0, int y0, int x1, int y1) {
  final left = x0 < x1 ? x0 : x1;
  final right = x0 < x1 ? x1 : x0;
  final top = y0 < y1 ? y0 : y1;
  final bottom = y0 < y1 ? y1 : y0;

  final w = right - left + 1;
  final h = bottom - top + 1;
  if (w <= 0 || h <= 0) return const [];
  if (w <= 2 || h <= 2) {
    // Совсем крошечная фигура — просто прямоугольник, иначе от неё остаётся
    // одна клетка и человек не понимает, нарисовалось ли что-нибудь.
    return [
      for (var y = top; y <= bottom; y++) (y: y, left: left, right: right),
    ];
  }

  // Центр берём по серединам крайних клеток, а не по их краям: иначе верхняя
  // половина круга считается от одной точки, нижняя от другой, и низ выходит
  // уже верха — на глаз это «круг с приплюснутым дном».
  final cx = (left + right + 1) / 2.0;
  final cy = (top + bottom + 1) / 2.0;
  final rx = w / 2.0;
  final ry = h / 2.0;

  final spans = <_Span>[];
  for (var y = top; y <= bottom; y++) {
    // Берём центр клетки: так верхняя и нижняя половины считаются одинаково.
    final dy = (y + 0.5 - cy) / ry;
    final under = 1.0 - dy * dy;
    if (under < 0) continue;
    final dx = rx * math.sqrt(under);
    final l = (cx - dx).round();
    final r = (cx + dx).round() - 1;
    spans.add((y: y, left: l, right: r < l ? l : r));
  }
  return spans;
}

/// Треугольник с вершиной сверху по центру и основанием снизу — та же форма,
/// что рисует гладкий инструмент, чтобы переключение режима не удивляло.
List<_Span> _triangleSpans(int x0, int y0, int x1, int y1) {
  final left = x0 < x1 ? x0 : x1;
  final right = x0 < x1 ? x1 : x0;
  final top = y0 < y1 ? y0 : y1;
  final bottom = y0 < y1 ? y1 : y0;

  final h = bottom - top;
  if (h <= 0) {
    return [(y: top, left: left, right: right)];
  }
  final apex = (left + right) / 2.0;

  final spans = <_Span>[];
  for (var y = top; y <= bottom; y++) {
    final t = (y - top) / h; // 0 — вершина, 1 — основание
    final l = (apex - (apex - left) * t).round();
    final r = (apex + (right - apex) * t).round();
    spans.add((y: y, left: l, right: r < l ? l : r));
  }
  return spans;
}

/// Размер кисти в КЛЕТКАХ по толщине, выбранной ползунком.
///
/// На пиксельном холсте ползунок толщины не делал ничего: штрих всегда красил
/// ровно одну клетку, сколько его ни двигай. Теперь он выбирает квадрат кисти —
/// то, чем в пиксель-арте и рисуют. Ступеней пять: больше на холсте 32×40
/// бессмысленно, кисть 6×6 закрывает шестую часть ширины.
int pixelBrushCells(double strokeWidth) {
  if (strokeWidth < 8) return 1;
  if (strokeWidth < 16) return 2;
  if (strokeWidth < 24) return 3;
  if (strokeWidth < 32) return 4;
  return 5;
}
