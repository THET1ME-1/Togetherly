import 'package:flutter/material.dart';

/// Описание одной темы приложения.
///
/// Чтобы добавить новую тему — создай [AppTheme] и добавь в [AppThemes.all].
/// Все цвета задаются в одном месте, без `if (isPurple)` по всему коду.
class AppTheme {
  /// Уникальный id (совпадает с индексом в [AppThemes.all])
  final int index;

  /// Отображаемое название
  final String name;

  // ── Основные акцентные цвета ─────────────────────────────────────────────

  /// Главный акцентный цвет (кнопки, иконки, бейджи, рамки)
  final Color primary;

  /// Светлый вариант primary (фоны чипов, контейнеров)
  final Color primaryLight;

  // ── Фон страницы ─────────────────────────────────────────────────────────

  /// Цвета градиента фона [сверху, снизу]
  final List<Color> bgGradient;

  // ── Hero-карточка (ExpandableTimerCard) ──────────────────────────────────

  /// Цвета градиента карточки [начало, конец]
  final List<Color> heroGradient;

  /// Радиус скругления карточки
  final double heroRadius;

  /// Цвет тени в свёрнутом состоянии
  final Color heroShadowBase;

  /// Цвет тени в развёрнутом состоянии
  final Color heroShadowExpanded;

  /// Прозрачность стеклянных элементов внутри карточки (стрелка, тоггл)
  final double heroGlassOpacity;

  /// Показывать ли белую рамку на переключателе Days/Months/Time
  final bool heroToggleBorder;

  /// Цвет текста активного пункта тоггла
  final Color heroToggleSelectedColor;

  // ── Поверхности обычных карточек ─────────────────────────────────────────

  /// Фон карточек (Connect Prompt, Memory Lane и т.д.)
  final Color cardSurface;

  /// Цвет рамки карточек
  final Color cardBorder;

  // ── Иконки кнопок быстрых действий ───────────────────────────────────────

  final Color iconDraw;
  final Color iconMood;
  final Color iconCalendar;
  final Color iconPost;

  const AppTheme({
    required this.index,
    required this.name,
    required this.primary,
    required this.primaryLight,
    required this.bgGradient,
    required this.heroGradient,
    required this.heroRadius,
    required this.heroShadowBase,
    required this.heroShadowExpanded,
    required this.heroGlassOpacity,
    required this.heroToggleBorder,
    required this.heroToggleSelectedColor,
    required this.cardSurface,
    required this.cardBorder,
    required this.iconDraw,
    required this.iconMood,
    required this.iconCalendar,
    required this.iconPost,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Все доступные темы
// Чтобы добавить новую — создай AppTheme ниже и добавь в [all].
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppThemes {
  // ── 0: Розовая ────────────────────────────────────────────────────────────
  static const pink = AppTheme(
    index: 0,
    name: 'Розовая',
    primary: Color(0xFFEE2B6C),
    primaryLight: Color(0xFFFEEAF1),
    bgGradient: [Color(0xFFF7F3F0), Color(0xFFFFFFFF)],
    heroGradient: [Color(0xFFFFB4B0), Color(0xFFFF8E9E)],
    heroRadius: 32,
    heroShadowBase: Color(0x26FF7E8B), // rgba(255,126,139, 0.15)
    heroShadowExpanded: Color(0x40FF7E8B), // rgba(255,126,139, 0.25)
    heroGlassOpacity: 0.20,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFFEE2B6C), // == primary
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE5E5E5),
    iconDraw: Color(0xFFFFB7B7),
    iconMood: Color(0xFFFBBF24),
    iconCalendar: Color(0xFF60A5FA),
    iconPost: Color(0xFF34D399),
  );

  // ── 1: Фиолетовая (Lavender) ──────────────────────────────────────────────
  static const purple = AppTheme(
    index: 1,
    name: 'Фиолетовая',
    primary: Color(0xFF9B86BD), // Calming Lavender
    primaryLight: Color(0xFFE6E6FA), // Soft Lavender
    bgGradient: [Color(0xFFE6E6FA), Color(0xFFF0FFF0)], // lavender → mint
    heroGradient: [Color(0xFF6C5B7B), Color(0xFF352F44)], // deep purple
    heroRadius: 48,
    heroShadowBase: Color(0x0D000000), // black 5%
    heroShadowExpanded: Color(0x1A9B86BD), // lavender 10%
    heroGlassOpacity: 0.15,
    heroToggleBorder: false,
    heroToggleSelectedColor: Color(0xFF352F44), // глубокий фиолетовый
    cardSurface: Color(0xFFFDFDFF),
    cardBorder: Color(0xFFDDDDEE),
    iconDraw: Color(0xFF9B86BD),
    iconMood: Color(0xFF9B86BD),
    iconCalendar: Color(0xFF9B86BD),
    iconPost: Color(0xFF9B86BD),
  );

  // ── Список всех тем (порядок = индекс) ───────────────────────────────────
  static const List<AppTheme> all = [pink, purple];

  /// Найти тему по индексу; при выходе за границы — возвращает [pink]
  static AppTheme byIndex(int index) {
    if (index >= 0 && index < all.length) return all[index];
    return pink;
  }
}
