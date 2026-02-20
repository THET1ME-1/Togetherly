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

  // ── Нижняя навигация ───────────────────────────────────────────────────

  /// Фон активной кнопки навигации
  final Color navActiveBg;

  /// Цвет иконки активного пункта навигации
  final Color navActiveIcon;

  /// Цвет кнопки "Ответить на вопрос" в Daily Reflection
  final Color promptButtonColor;

  const AppTheme({
    required this.index,
    required this.name,
    required this.primary,
    required this.primaryLight,
    required this.bgGradient,
    required this.heroGradient,
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
    required this.navActiveBg,
    required this.navActiveIcon,
    required this.promptButtonColor,
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
    heroShadowBase: Color(0x26FF7E8B), // rgba(255,126,139, 0.15)
    heroShadowExpanded: Color(0x40FF7E8B), // rgba(255,126,139, 0.25)
    heroGlassOpacity: 0.20,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFFEE2B6C), // == primary
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE5E5E5),
    iconDraw: Color(0xFFFF7E8B),
    iconMood: Color(0xFFFF7E8B),
    iconCalendar: Color(0xFFFF7E8B),
    iconPost: Color(0xFFFF7E8B),
    navActiveBg: Color(0xFFF9E4E2),
    navActiveIcon: Color(0xFFFF7E8B),
    promptButtonColor: Color(0xFFFF7E8B),
  );

  // ── 1: Фиолетовая (Lavender) ──────────────────────────────────────────────
  static const purple = AppTheme(
    index: 1,
    name: 'Фиолетовая',
    primary: Color(0xFF9B86BD), // Calming Lavender
    primaryLight: Color(0xFFE6E6FA), // Soft Lavender
    bgGradient: [Color(0xFFE6E6FA), Color(0xFFF0FFF0)], // lavender → mint
    heroGradient: [Color(0xFF6C5B7B), Color(0xFF352F44)], // deep purple
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
    navActiveBg: Color(0xFFEDE7F6),
    navActiveIcon: Color(0xFF9B86BD),
    promptButtonColor: Color(0xFF9B86BD),
  );

  // ── 2: Синяя (Cornflower) ─────────────────────────────────────────────────
  static const blue = AppTheme(
    index: 2,
    name: 'Синяя',
    primary: Color(0xFF6674C5),
    primaryLight: Color(0xFFEEF0FD),
    bgGradient: [Color(0xFFECEEFB), Color(0xFFF5F7FF)],
    heroGradient: [Color(0xFF8B9DCE), Color(0xFF6674C5)],
    heroShadowBase: Color(0x266674C5),
    heroShadowExpanded: Color(0x406674C5),
    heroGlassOpacity: 0.18,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFF3D4F9E),
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFDDE0F4),
    iconDraw: Color(0xFF6674C5),
    iconMood: Color(0xFF6674C5),
    iconCalendar: Color(0xFF6674C5),
    iconPost: Color(0xFF6674C5),
    navActiveBg: Color(0xFFEEF0FD),
    navActiveIcon: Color(0xFF6674C5),
    promptButtonColor: Color(0xFF6674C5),
  );

  // ── 3: Оранжевая (Terracotta) ─────────────────────────────────────────────
  static const orange = AppTheme(
    index: 3,
    name: 'Оранжевая',
    primary: Color(0xFFC8603A),
    primaryLight: Color(0xFFFDF0EB),
    bgGradient: [Color(0xFFFDF2EC), Color(0xFFFFFAF7)],
    heroGradient: [Color(0xFFD4795A), Color(0xFFC8603A)],
    heroShadowBase: Color(0x26C8603A),
    heroShadowExpanded: Color(0x40C8603A),
    heroGlassOpacity: 0.20,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFFC8603A),
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFEDE0D8),
    iconDraw: Color(0xFFC8603A),
    iconMood: Color(0xFFC8603A),
    iconCalendar: Color(0xFFC8603A),
    iconPost: Color(0xFFC8603A),
    navActiveBg: Color(0xFFFDF0EB),
    navActiveIcon: Color(0xFFC8603A),
    promptButtonColor: Color(0xFFC8603A),
  );

  // ── 4: Зелёная (Forest) ───────────────────────────────────────────────────
  static const green = AppTheme(
    index: 4,
    name: 'Зелёная',
    primary: Color(0xFF3A6B35),
    primaryLight: Color(0xFFE8F5E2),
    bgGradient: [Color(0xFFF5F8F2), Color(0xFFFAFFF7)],
    heroGradient: [Color(0xFF4A7B44), Color(0xFF2D5016)],
    heroShadowBase: Color(0x263A6B35),
    heroShadowExpanded: Color(0x403A6B35),
    heroGlassOpacity: 0.18,
    heroToggleBorder: false,
    heroToggleSelectedColor: Color(0xFF1E3A1A),
    cardSurface: Color(0xFFFAFFF9),
    cardBorder: Color(0xFFD8EDD4),
    iconDraw: Color(0xFF3A6B35),
    iconMood: Color(0xFF3A6B35),
    iconCalendar: Color(0xFF3A6B35),
    iconPost: Color(0xFF3A6B35),
    navActiveBg: Color(0xFFE4F2E0),
    navActiveIcon: Color(0xFF3A6B35),
    promptButtonColor: Color(0xFF3A6B35),
  );

  // ── Список всех тем (порядок = индекс) ───────────────────────────────────
  static const List<AppTheme> all = [pink, purple, blue, orange, green];

  /// Найти тему по индексу; при выходе за границы — возвращает [pink]
  static AppTheme byIndex(int index) {
    if (index >= 0 && index < all.length) return all[index];
    return pink;
  }
}
