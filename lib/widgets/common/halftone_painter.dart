import 'package:flutter/rendering.dart';

/// Одна точка растра: где, какого радиуса и насколько прозрачная.
class HalftoneDot {
  final Offset center;
  final double radius;
  final double alpha;
  const HalftoneDot(this.center, this.radius, this.alpha);
}

/// Точки растра для прямоугольника [size]: растут слева направо, как
/// полиграфический растр.
///
/// Узор главной кнопки листа «Добавить воспоминание» (макет «Узор кнопки»,
/// выбран 19.09.2026). Левая треть пустая — там подпись, и её контраст
/// остаётся тем же, что у ровной заливки. Ряды через один сдвинуты на
/// полшага, шаг 11, самые крупные точки — 3,3.
///
/// В тёмной теме точки тише (0,143 против 0,22): подпись там почти чёрная, и
/// с той же прозрачностью растр спорил бы с текстом.
List<HalftoneDot> halftoneDots(Size size, {required bool dark}) {
  const step = 11.0, maxRadius = 3.3, start = 0.34;
  final w = size.width;
  if (w <= 0) return const [];
  final base = (dark ? 0.13 : 0.2) * 1.1;
  final dots = <HalftoneDot>[];
  var row = 0;
  for (var y = 5.0; y < size.height + step; y += step, row++) {
    for (var x = (row.isOdd ? step / 2 : 0.0) + 4; x < w + step; x += step) {
      final k = (x / w - start) / (1 - start);
      if (k <= 0) continue;
      final r = (k < 1 ? k : 1) * maxRadius;
      if (r < 0.35) continue;
      // Та же маска, что в макете: к левому краю узор гаснет до трети.
      final t = x / w;
      final fade = t <= 0.22
          ? 0.35
          : t >= 0.55
              ? 1.0
              : 0.35 + (t - 0.22) / (0.55 - 0.22) * 0.65;
      dots.add(HalftoneDot(Offset(x, y), r, base * fade));
    }
  }
  return dots;
}

/// Рисует [halftoneDots] цветом [color] (подписью кнопки): узор
/// перекрашивается вместе с темой без отдельной настройки.
class HalftonePainter extends CustomPainter {
  const HalftonePainter({required this.color, required this.dark});

  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    for (final d in halftoneDots(size, dark: dark)) {
      paint.color = color.withValues(alpha: color.a * d.alpha);
      canvas.drawCircle(d.center, d.radius, paint);
    }
  }

  @override
  bool shouldRepaint(HalftonePainter old) =>
      old.color != color || old.dark != dark;
}
