import 'dart:ui' show Brightness, Color;

import 'package:flutter/material.dart' show ColorScheme;
import 'package:home_widget/home_widget.dart';

/// Палитра виджетов рабочего стола.
///
/// Виджеты рисуются нативно, до Flutter им не дотянуться, поэтому цвета
/// активной темы кладутся в `HomeWidgetPreferences` обычными строками, а
/// нативная сторона (`WidgetTheme.kt`) их читает. Раньше все разметки держали
/// фиолетовый хардкодом, и виджет не менялся вслед за темой из двадцати
/// доступных.
///
/// Полупрозрачные роли (подписи, треки прогресса) смешиваются здесь же: у
/// RemoteViews нет альфа-композитинга поверх произвольной подложки, нативной
/// стороне нужен готовый непрозрачный цвет.
class WidgetThemeSync {
  const WidgetThemeSync._();

  /// Префикс ключей, чтобы не столкнуться с данными самих виджетов.
  static const prefix = 'wtheme_';

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Непрозрачный результат наложения [fg] с прозрачностью [alpha] на [bg].
  static Color _blend(Color fg, double alpha, Color bg) =>
      Color.lerp(bg, fg, alpha) ?? fg;

  /// Раскладывает [scheme] по ролям, которые нужны разметкам виджетов.
  static Map<String, Color> rolesOf(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;

    return {
      // Заливки
      'primary': scheme.primary,
      'primaryContainer': scheme.primaryContainer,
      'surface': scheme.surface,
      'surfaceContainer': scheme.surfaceContainerHigh,
      'tertiary': scheme.tertiary,
      'tertiaryContainer': scheme.tertiaryContainer,
      'secondaryContainer': scheme.secondaryContainer,

      // Текст и иконки
      'onPrimary': scheme.onPrimary,
      'onPrimarySoft': _blend(scheme.onPrimary, 0.78, scheme.primary),
      'onPrimaryContainer': scheme.onPrimaryContainer,
      'onContainerSoft':
          _blend(scheme.onPrimaryContainer, 0.68, scheme.primaryContainer),
      'onSurface': scheme.onSurface,
      'onSurfaceVariant': scheme.onSurfaceVariant,
      'onTertiary': scheme.onTertiary,
      'onTertiaryContainer': scheme.onTertiaryContainer,
      'outline': scheme.outline,

      // Акцент, читаемый на заливке primary (в макете это #D0BCFF).
      'accentOnPrimary': dark ? scheme.primaryContainer : scheme.inversePrimary,

      // Треки прогресса — подложка под заливкой primary.
      'trackOnContainer': _blend(scheme.primary, 0.26, scheme.primaryContainer),
      'trackOnSurface': _blend(scheme.primary, 0.16, scheme.surface),

      // Блок, приподнятый над заливкой primary: плитки и трек кольца в
      // «Кольце года». Роль отдельная, потому что и primaryContainer, и
      // secondaryContainer на тёмной карточке выглядят наклейкой чужого цвета.
      'blockOnPrimary': _blend(scheme.onPrimary, 0.12, scheme.primary),

      // Кружки аватаров, когда фотографии нет.
      'avatarMine': dark ? scheme.primaryContainer : scheme.inversePrimary,
      'avatarPartner': scheme.tertiaryContainer,
    };
  }

  /// Пишет палитру в хранилище виджетов. Обновление самих виджетов вызывающий
  /// делает сам — палитра пишется вместе с данными, лишний раунд не нужен.
  static Future<void> save(ColorScheme scheme) async {
    for (final entry in rolesOf(scheme).entries) {
      await HomeWidget.saveWidgetData<String>(
        '$prefix${entry.key}',
        _hex(entry.value),
      );
    }
    await HomeWidget.saveWidgetData<String>(
      '${prefix}dark',
      scheme.brightness == Brightness.dark ? '1' : '0',
    );
  }
}
