import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

/// Волновая полоса прогресса M3 Expressive.
///
/// Волна означает «процесс идёт прямо сейчас»: она поднимается на старте и
/// распрямляется в ровную линию к финишу — ровно как в ролике Material
/// (кадры 2→3). Отсюда правило: полосу вешать на живой процесс (заливка,
/// сжатие, синхронизация), а на статистику вроде «7 достижений из 20» ставить
/// обычный [LinearProgressIndicator] — там ничего не «идёт», и волна врёт.
///
/// Точка-стопер на конце трека и зазор перед ней приходят из темы
/// (`ProgressIndicatorThemeData.year2023 = false`, см. profile_theme.dart).
///
/// https://m3.material.io/components/progress-indicators/overview
class M3WaveProgress extends StatelessWidget {
  /// Доля выполнения 0..1. null — процесс идёт, но доля неизвестна.
  final double? value;

  final Color? color;
  final Color? trackColor;

  /// Высота полосы. 4 — обычная строка, 8–10 — акцентная (заливка видео).
  final double minHeight;

  /// Длина волны в пикселях. Короткая волна на узкой полосе выглядит рябью,
  /// поэтому на широких местах её стоит увеличивать.
  final double wavelength;

  const M3WaveProgress({
    super.key,
    this.value,
    this.color,
    this.trackColor,
    this.minHeight = 4,
    this.wavelength = 24,
  });

  /// Насколько сильно волнить полосу при доле [value].
  ///
  /// Волна нужна в движении и мешает на финише: заполненная полоса обязана
  /// читаться как ровная черта, иначе «готово» выглядит как «ещё идёт».
  /// Поэтому амплитуда держится на максимуме почти всю дорогу и гаснет на
  /// последних процентах — плавно, чтобы не дёрнуться в самом конце.
  static double amplitudeFor(double? value) {
    if (value == null) return 1.0;
    final v = value.clamp(0.0, 1.0);
    const fadeFrom = 0.9;
    if (v < fadeFrom) return 1.0;
    return ((1.0 - v) / (1.0 - fadeFrom)).clamp(0.0, 1.0);
  }

  /// Доля отправленной очереди: было [peak] задач, осталось [active].
  ///
  /// null — очереди не было вовсе (полосу показывать не за что). Если очередь
  /// пополнилась сверх прежнего пика, доля прижимается к нулю, а не уходит в
  /// минус: полоса поедет назад, но не сломается.
  static double? queueFraction({required int active, required int peak}) {
    if (peak <= 0) return null;
    return ((peak - active) / peak).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpressiveLinearProgressIndicator(
      value: value,
      color: color ?? scheme.primary,
      backgroundColor: trackColor ?? scheme.secondaryContainer,
      minHeight: minHeight,
      wavelength: wavelength,
      amplitude: amplitudeFor(value),
      borderRadius: BorderRadius.circular(minHeight),
    );
  }
}
