import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Волнистая фигура M3 Expressive («печенье») для ВЫБРАННОЙ плитки настроения.
///
/// Выбор в M3 показывают формой, а не свечением: невыбранные плитки остаются
/// мягкими квадратами ([RoundedSuperellipseBorder] из SDK), а выбранная
/// перетекает в этот силуэт. Лепестки считаются по косинусу, поэтому край
/// получается ровным на любом размере плитки.
class CookieBorder extends OutlinedBorder {
  /// Сколько лепестков по кругу.
  final int lobes;

  /// Глубина волны в долях радиуса. Больше 0.06 фигура начинает выглядеть
  /// зубчатой, меньше 0.02 — неотличима от круга.
  final double amplitude;

  const CookieBorder({
    super.side = BorderSide.none,
    this.lobes = 8,
    this.amplitude = 0.032,
  });

  static const int _samples = 180;

  Path _path(Rect rect) {
    final center = rect.center;
    final radius = rect.shortestSide / 2;
    final path = Path();
    for (var i = 0; i <= _samples; i++) {
      final a = 2 * math.pi * i / _samples;
      final r = radius * (1 - amplitude + amplitude * math.cos(lobes * a));
      final p = Offset(
        center.dx + math.cos(a) * r,
        center.dy + math.sin(a) * r,
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      side.toPaint(),
    );
  }

  @override
  CookieBorder copyWith({BorderSide? side, int? lobes, double? amplitude}) =>
      CookieBorder(
        side: side ?? this.side,
        lobes: lobes ?? this.lobes,
        amplitude: amplitude ?? this.amplitude,
      );

  @override
  ShapeBorder scale(double t) => CookieBorder(
        side: side.scale(t),
        lobes: lobes,
        amplitude: amplitude,
      );

  @override
  bool operator ==(Object other) =>
      other is CookieBorder &&
      other.side == side &&
      other.lobes == lobes &&
      other.amplitude == amplitude;

  @override
  int get hashCode => Object.hash(side, lobes, amplitude);
}

/// Форма невыбранной плитки: мягкий квадрат (суперэллипс из SDK).
ShapeBorder moodTileShape({required bool selected, required double size}) =>
    selected
        ? const CookieBorder()
        : RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * 0.34),
          );
