import 'dart:ui';

/// Подбор читаемого цвета текста на произвольном фоне.
///
/// Пузыри чата красит сам автор, и на жёлтом, салатовом или пастельном фоне
/// белый текст пропадал: старое правило смотрело на яркость с порогом 0.55 и
/// отдавало белый всему, что темнее. Теперь считаем настоящий контраст по
/// WCAG 2.1 и берём тот вариант, где он выше.

/// Тёмный вариант текста — чёрный с лёгкой синевой (M3 `onSurface` светлой
/// схемы). Чистый чёрный на цветном пузыре выглядит грязно.
const Color kDarkBubbleText = Color(0xFF16161A);

/// Контраст двух цветов по WCAG 2.1: от 1 (одинаковые) до 21 (чёрный/белый).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Белый или тёмный — что читаемее на [background].
Color readableTextOn(Color background) =>
    contrastRatio(background, const Color(0xFFFFFFFF)) >=
            contrastRatio(background, kDarkBubbleText)
        ? const Color(0xFFFFFFFF)
        : kDarkBubbleText;
