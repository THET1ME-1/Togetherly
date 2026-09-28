import 'dart:math' as math;
import 'dart:ui';

/// Вид пузырей в чате (макет «Сообщения в стиле Overrule», 28.09.2026:
/// выбраны «Наклейка» с дрожью и «Пиксель»). Хранится локально: это вкус
/// каждого, а не решение пары, партнёр видит чат в своём виде.
enum ChatLook {
  /// Наш: кривые углы, наклон, мордочки, хвостик.
  cozy,

  /// Обычный: пузыри Material 3 без украшений.
  material,

  /// Наклейка в манере значков: контур тушью с нахлёстом, штриховка по
  /// краю, белая кайма. Контур дрожит тремя кадрами.
  sticker,

  /// Пиксель: ступенчатые углы и пиксельный хвостик, как маскоты.
  pixel,
}

/// Разбор сохранённого значения. Прежние `cozy` и `material` читаются как
/// раньше, незнакомое — наш вид.
ChatLook chatLookFromName(String? name) {
  for (final v in ChatLook.values) {
    if (v.name == name) return v;
  }
  return ChatLook.cozy;
}

/// Сколько кадров у дрожи контура и как часто они сменяются.
const int kStickerFrames = 3;
const Duration kStickerFrameStep = Duration(milliseconds: 125);

/// Кадр дрожи в момент [elapsed].
int stickerFrameAt(Duration elapsed) =>
    (elapsed.inMilliseconds ~/ kStickerFrameStep.inMilliseconds) %
    kStickerFrames;

/// Генератор тех же чисел, что `rnd()` мастерской значков: один сид — одни и
/// те же точки, поэтому пузырь не меняет форму от перерисовки.
class HandRandom {
  HandRandom(int seed) : _s = (seed.abs() % 2147483646) + 1;
  int _s;
  double next() {
    _s = (_s * 16807) % 2147483647;
    return _s / 2147483647;
  }
}

/// Точки скруглённого прямоугольника «от руки» внутри [rect]: углы по четыре
/// точки, стороны через ~38 px, каждая точка сдвинута не больше [wobble].
List<Offset> handRoundRect(
  Rect rect,
  double radius,
  HandRandom rnd, {
  double wobble = 0.9,
}) {
  final w = rect.width, h = rect.height;
  final r = math.min(radius, math.min(w, h) / 2);
  final pts = <Offset>[];
  void corner(double cx, double cy, double a0) {
    for (var i = 0; i <= 3; i++) {
      final a = a0 + i / 3 * math.pi / 2;
      pts.add(Offset(cx + math.cos(a) * r, cy + math.sin(a) * r));
    }
  }

  void edge(Offset a, Offset b) {
    final n = math.max(1, ((b - a).distance / 38).round());
    for (var i = 1; i < n; i++) {
      pts.add(Offset.lerp(a, b, i / n)!);
    }
  }

  corner(w - r, r, -math.pi / 2);
  edge(Offset(w, r), Offset(w, h - r));
  corner(w - r, h - r, 0);
  edge(Offset(w - r, h), Offset(r, h));
  corner(r, h - r, math.pi / 2);
  edge(Offset(0, h - r), Offset(0, r));
  corner(r, r, math.pi);
  edge(Offset(r, 0), Offset(w - r, 0));
  return [
    for (final p in pts)
      Offset(
        rect.left + p.dx + (rnd.next() - .5) * 2 * wobble,
        rect.top + p.dy + (rnd.next() - .5) * 2 * wobble,
      ),
  ];
}

/// Гладкая кривая через точки (Catmull-Rom → кубические Безье), как `cr()`.
Path handCurve(List<Offset> pts, {required bool closed}) {
  final n = pts.length;
  Offset p(int i) => closed ? pts[(i % n + n) % n] : pts[i.clamp(0, n - 1)];
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  final last = closed ? n : n - 1;
  for (var i = 0; i < last; i++) {
    final p0 = p(i - 1), p1 = p(i), p2 = p(i + 1), p3 = p(i + 2);
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  if (closed) path.close();
  return path;
}

/// Контур маркером: проходит круг и заходит на старт с нахлёстом.
Path handContour(List<Offset> pts, HandRandom rnd) {
  final a = pts[0], b = pts[1];
  final ov = Offset(
    a.dx + (b.dx - a.dx) * .45 + (rnd.next() - .5) * 1.6,
    a.dy + (b.dy - a.dy) * .45 + (rnd.next() - .5) * 1.6,
  );
  return handCurve([...pts, a, ov], closed: false);
}

/// Ступенчатый прямоугольник «Пикселя»: углы срезаны ступенькой [step].
Path pixelRect(Rect r, double step) => Path()
  ..moveTo(r.left, r.top + step)
  ..lineTo(r.left + step, r.top + step)
  ..lineTo(r.left + step, r.top)
  ..lineTo(r.right - step, r.top)
  ..lineTo(r.right - step, r.top + step)
  ..lineTo(r.right, r.top + step)
  ..lineTo(r.right, r.bottom - step)
  ..lineTo(r.right - step, r.bottom - step)
  ..lineTo(r.right - step, r.bottom)
  ..lineTo(r.left + step, r.bottom)
  ..lineTo(r.left + step, r.bottom - step)
  ..lineTo(r.left, r.bottom - step)
  ..close();
