import 'dart:ui' show Brightness, Color;

import 'package:flutter/material.dart' show ColorScheme;
import 'package:home_widget/home_widget.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../models/year_ring_spec.dart';
import '../utils/readable_text.dart';

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

  /// Контраст основной надписи на заливке (крупный жирный текст, WCAG 3:1)
  /// и вторичной — с долей фона, по светлому углу градиента «Кольца года».
  static const double minFillContrast = 3.0;
  static const double minSoftContrast = 2.6;

  /// Доля цвета надписи во вторичной подписи (`onPrimarySoft`).
  static const double softShare = 0.86;

  static bool _readable(Color fill, Color on) {
    final corner = YearRingSpec.lightOf(fill);
    final soft = Color.alphaBlend(
      on.withValues(alpha: YearRingSpec.softAlpha),
      corner,
    );
    return contrastRatio(on, fill) >= minFillContrast &&
        contrastRatio(soft, corner) >= minSoftContrast &&
        contrastRatio(_blend(on, softShare, fill), fill) >= minSoftContrast;
  }

  /// Заливка виджета, на которой читается [on].
  ///
  /// Замер 14.09.2026 по всем темам: у 28 светлых сочетаний подписи на
  /// `primary` давали меньше 3:1 (Лимонная 1,97, Розовая 2,00) — на «Кольце
  /// года» текст сливался с фоном. Цвет надписи задан правилом «на цвете
  /// белым», поэтому двигается тон самой заливки: темнее под светлую надпись,
  /// светлее под тёмную. Оттенок и насыщенность те же, так что виджет остаётся
  /// в цвете темы, а читаемые темы не меняются вовсе. Стережёт
  /// `test/services/widget_theme_all_palettes_test.dart`.
  static Color readableFill(Color fill, Color on) {
    if (_readable(fill, on)) return fill;
    final hct = Hct.fromInt(fill.toARGB32());
    final darker = on.computeLuminance() > fill.computeLuminance();
    var tone = hct.tone;
    var out = fill;
    while (darker ? tone > 2 : tone < 98) {
      tone += darker ? -1 : 1;
      out = Color(Hct.from(hct.hue, hct.chroma, tone).toInt());
      if (_readable(out, on)) break;
    }
    return out;
  }

  /// Раскладывает [scheme] по ролям, которые нужны разметкам виджетов.
  static Map<String, Color> rolesOf(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final fill = readableFill(scheme.primary, scheme.onPrimary);

    return {
      // Заливки
      'primary': fill,
      'primaryContainer': scheme.primaryContainer,
      'surface': scheme.surface,
      'surfaceContainer': scheme.surfaceContainerHigh,
      'tertiary': scheme.tertiary,
      'tertiaryContainer': scheme.tertiaryContainer,
      'secondaryContainer': scheme.secondaryContainer,

      // Текст и иконки
      'onPrimary': scheme.onPrimary,
      'onPrimarySoft': _blend(scheme.onPrimary, softShare, fill),
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
      'trackOnContainer': _blend(fill, 0.26, scheme.primaryContainer),
      'trackOnSurface': _blend(fill, 0.16, scheme.surface),

      // Блок, приподнятый над заливкой primary: плитки и трек кольца в
      // «Кольце года». Роль отдельная, потому что и primaryContainer, и
      // secondaryContainer на тёмной карточке выглядят наклейкой чужого цвета.
      'blockOnPrimary': _blend(scheme.onPrimary, 0.12, fill),

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
