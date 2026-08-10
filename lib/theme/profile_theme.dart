import 'package:flutter/material.dart';

import 'app_palettes.dart';
import 'app_theme.dart';

/// M3 Expressive-тема для экрана «Профиль» — в духе Kadr.
///
/// Схема выводится из [AppTheme.primary] как seed (вариант `vibrant`), поэтому
/// подстраивается под все 25 тем Togetherly и сама даёт тональные поверхности,
/// контейнеры и контрастный `primary` (белый текст на кнопках читается).
/// Заголовки/числа — Unbounded, текст — Onest. Экран профиля оборачивается в эту
/// тему через `Theme(data: ProfileTheme.themeFor(t), child: ...)`, дальше всё
/// строится стандартными M3-виджетами.
abstract final class ProfileTheme {
  static const String displayFont = 'Unbounded';
  static const String bodyFont = 'Onest';

  /// M3-схема темы. Тёмные темы Togetherly дают тёмную схему.
  ///
  /// Готовую схему берём как есть: `AppTheme.primary` — это уже `scheme.primary`,
  /// то есть производный тон, и повторный `fromSeed` по нему скатывал любой
  /// вариант в «мягкий». Тема вишнёвая, вариант «сочный»: главная `#BB005B`,
  /// а всё, что строилось здесь, — `#8D4A5D`, вдвое бледнее по хроме. Схемы нет
  /// только у статических `AppThemes.*` — им остаётся прежний путь через сид.
  static ColorScheme schemeFor(AppTheme t) =>
      t.scheme ?? schemeOf(t.primary, t.brightness);

  /// Схема из произвольного акцента — ею же пользуются тесты палитр.
  ///
  /// Вариант `tonalSpot`, а не `vibrant`: последний задирал насыщенность на
  /// зелёных, жёлтых и бирюзовых сидах до 0.85–0.93 при 0.26–0.30 у розовой и
  /// фиолетовой. На тёмном фоне это выглядело кислотной кнопкой, и половину
  /// тем справедливо называли некачественными. У розовой и фиолетовой
  /// `tonalSpot` даёт практически тот же результат, что и раньше.
  static ColorScheme schemeOf(Color accent, Brightness brightness) =>
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        dynamicSchemeVariant: variantFor(accent),
      );

  /// Вариант берётся у палитры с этим акцентом; акцент, которого нет в
  /// каталоге (свои цвета из паков), разворачивается спокойным `tonalSpot`.
  static DynamicSchemeVariant variantFor(Color accent) {
    for (final palette in kPalettes) {
      if (palette.accent.toARGB32() == accent.toARGB32()) return palette.variant;
    }
    return DynamicSchemeVariant.tonalSpot;
  }

  static ThemeData themeFor(AppTheme t) => data(schemeFor(t));

  /// ThemeData (шрифты Unbounded/Onest, кнопки-пилюли, карточки) поверх готовой
  /// M3-схемы. Схему передаёт экран, чтобы она совпадала с вариантом приложения.
  static ThemeData data(ColorScheme scheme) => _fromScheme(scheme);

  static ThemeData _fromScheme(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
    );
    final text = _expressiveText(base.textTheme);
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
        indent: 16,
        endIndent: 16,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          fontSize: 13,
          color: scheme.onSurfaceVariant,
        ),
      ),
      // Крупные «таблеточные» кнопки — фирменная черта expressive-стиля.
      //
      // Цвет берётся из `primaryContainer`, а не из `primary`: с 8 августа
      // 2026 у темы два акцента, и `primary` — это НАДПИСЬ (тёмный тон под
      // контраст), а заливка живёт в контейнере. Залитая кнопка — заливка по
      // определению, поэтому «Сохранить» в листах красится цветом темы, а не
      // её тёмным вариантом. Иначе выходило ровно то, на что жаловались:
      // экран тональный и блёклый, хотя тема сочная.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Стандартная пара M3: заливка `primary`, надпись `onPrimary`.
          // Обход через контейнер завели, когда `primary` был тёмным тоном под
          // контраст; у нарисованных руками палитр `primary` — сам цвет темы,
          // и обход больше не нужен. Контейнер вернулся к своей роли: светлая
          // тональная подложка под значки.
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
              fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(
              fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
              fontFamily: bodyFont, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: const SwitchThemeData(),
      // Индикаторы прогресса в облике M3 Expressive: зазор между заполненной
      // частью и треком, точка-стопер на конце, скруглённые торцы. Флаг
      // year2023 по умолчанию true, и без него Flutter рисует вид 2023 года —
      // сплошную полосу без зазора и точки. Требование M3-ДНК, до этого в
      // приложении не стояло, поэтому все полосы (достижения, уровень,
      // магазин подарков, каталог виджетов) выглядели устаревшими.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // Флаг помечен устаревшим самим Flutter: он существует ради перехода и
        // однажды станет false по умолчанию. Пока этого не случилось, ставим
        // руками — иначе полосы рисуются в облике 2023 года.
        // ignore: deprecated_member_use
        year2023: false,
        color: scheme.primary,
        linearTrackColor: scheme.secondaryContainer,
        circularTrackColor: scheme.secondaryContainer,
        stopIndicatorColor: scheme.primary,
      ),
    );
  }

  static TextTheme _expressiveText(TextTheme base) {
    // Unbounded и Onest — вариативные (fvar), поэтому вес задаётся ещё и через
    // fontVariations: без него Flutter рисует одно начертание, и «жирный»
    // заголовок выглядит обычным.
    TextStyle display(TextStyle? s) => (s ?? const TextStyle()).copyWith(
        fontFamily: displayFont,
        fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
        letterSpacing: -0.5);
    TextStyle headline(TextStyle? s) => (s ?? const TextStyle()).copyWith(
        fontFamily: displayFont,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
        letterSpacing: -0.3);
    TextStyle title(TextStyle? s) => (s ?? const TextStyle()).copyWith(
        fontFamily: displayFont,
        fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)]);
    TextStyle body(TextStyle? s) => (s ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
        fontVariations: [
          FontVariation('wght', (s?.fontWeight?.value ?? 400).toDouble()),
        ]);
    return base.copyWith(
      displayLarge: display(base.displayLarge),
      displayMedium: display(base.displayMedium),
      displaySmall: display(base.displaySmall),
      headlineLarge: headline(base.headlineLarge),
      headlineMedium: headline(base.headlineMedium),
      headlineSmall: headline(base.headlineSmall),
      titleLarge: title(base.titleLarge),
      titleMedium: title(base.titleMedium),
      titleSmall: title(base.titleSmall),
      bodyLarge: body(base.bodyLarge),
      bodyMedium: body(base.bodyMedium),
      bodySmall: body(base.bodySmall),
      labelLarge: body(base.labelLarge),
      labelMedium: body(base.labelMedium),
      labelSmall: body(base.labelSmall),
    );
  }
}
