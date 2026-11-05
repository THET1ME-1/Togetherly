import 'package:flutter/material.dart';

/// Цвет текста на заливке: [want], если он читается (контраст от 4,5), иначе
/// [fallback].
///
/// Экран входа живёт в теме гостя, где `onPrimaryContainer` совпадает с
/// `primary` (#FF7E8B на #FEEAF1, контраст около 2,3): розовая надпись на
/// бледно-розовой плитке «Через партнёра» почти не читалась. Остальные темы
/// дают нормальную пару, и там цвет остаётся тематическим.
Color inkOn(Color bg, Color want, Color fallback) {
  final a = want.computeLuminance();
  final b = bg.computeLuminance();
  final ratio = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
  return ratio >= 4.5 ? want : fallback;
}
