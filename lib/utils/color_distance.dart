import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Насколько два цвета различимы глазом: ΔE (CIE76) в пространстве Lab.
///
/// Для поверхностей это честнее WCAG-контраста: розовая фигура на розовом
/// листе может совпадать по яркости и всё равно быть видна оттенком. Ноль —
/// один цвет, около 2 — предел заметного, 10 и выше — ясно видно.
double deltaE(Color a, Color b) {
  final p = _lab(a), q = _lab(b);
  final dl = p[0] - q[0], da = p[1] - q[1], db = p[2] - q[2];
  return math.sqrt(dl * dl + da * da + db * db);
}

List<double> _lab(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}
