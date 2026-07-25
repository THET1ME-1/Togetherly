import 'package:flutter/material.dart';

/// Хелперы для вариативных шрифтов проекта.
///
/// Unbounded и Onest подключены одним начертанием с осями (fvar), а Flutter
/// применяет к таким шрифтам вес только через `fontVariations` — один
/// `fontWeight` их не двигает, и заголовки рисовались обычным начертанием
/// вместо жирного. Поэтому вес задаём в двух местах сразу: `fontWeight` нужен
/// системным фолбэкам, `fontVariations` — самому шрифту.
class AppFonts {
  const AppFonts._();

  static const String display = 'Unbounded';
  static const String body = 'Onest';

  /// Заголовочный стиль: Unbounded нужного веса.
  static TextStyle unbounded({
    required double size,
    double weight = 800,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontWeight: _weightOf(weight),
        fontVariations: [FontVariation('wght', weight)],
      );

  /// Текстовый стиль: Onest нужного веса.
  static TextStyle onest({
    required double size,
    double weight = 400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: body,
        fontSize: size,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontWeight: _weightOf(weight),
        fontVariations: [FontVariation('wght', weight)],
      );

  static FontWeight _weightOf(double w) {
    if (w >= 850) return FontWeight.w900;
    if (w >= 750) return FontWeight.w800;
    if (w >= 650) return FontWeight.w700;
    if (w >= 550) return FontWeight.w600;
    if (w >= 450) return FontWeight.w500;
    if (w >= 350) return FontWeight.w400;
    if (w >= 250) return FontWeight.w300;
    return FontWeight.w200;
  }
}
