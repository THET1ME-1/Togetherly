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

  /// URL изображения фона из Firebase Storage (если задан — используется вместо градиента)
  final String? bgImageUrl;

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

  /// Цвет фона лепестков таймера (PetalTimerDial)
  final Color timerDialBackground;

  const AppTheme({
    required this.index,
    required this.name,
    required this.primary,
    required this.primaryLight,
    required this.bgGradient,
    this.bgImageUrl,
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
    required this.timerDialBackground,
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
    bgGradient: [Color(0xFFFFE8DC), Color(0xFFFFE8DC), Color(0xFFFFF0EA)],
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
    timerDialBackground: Color(0xFFFEDADE),
    bgImageUrl:
        'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fpink-background.webp?alt=media',
  );

  // ── 1: Фиолетовая (Lavender) ──────────────────────────────────────────────
  static const purple = AppTheme(
    index: 1,
    name: 'Фиолетовая',
    primary: Color(0xFF9B86BD), // Calming Lavender
    primaryLight: Color(0xFFE6E6FA), // Soft Lavender
    bgGradient: [
      Color(0xFFE6E6FA),
      Color(0xFFF3F0FF),
    ], // lavender → soft lavender
    heroGradient: [Color(0xFF6C5B7B), Color(0xFF352F44)], // deep purple
    heroShadowBase: Color(0x0D000000), // black 5%
    heroShadowExpanded: Color(0x1A9B86BD), // lavender 10%
    heroGlassOpacity: 0.22,
    heroToggleBorder: true,
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
    timerDialBackground: Color(0xFFDBCEEC),
    bgImageUrl:
        'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fpurple-background.webp?alt=media',
  );

  // ── 2: Голубая (Dusty Sky) ────────────────────────────────────────────────
  static const blue = AppTheme(
    index: 2,
    name: 'Голубая',
    primary: Color(0xFF7898BF), // пыльно-голубой с тёплым оттенком
    primaryLight: Color(0xFFEAF2FA),
    bgGradient: [Color(0xFFEBF2F9), Color(0xFFF5F9FE)],
    bgImageUrl:
        'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fblue-background.webp?alt=media',
    heroGradient: [Color(0xFFA8C6DE), Color(0xFF7898BF)],
    heroShadowBase: Color(0x267898BF),
    heroShadowExpanded: Color(0x407898BF),
    heroGlassOpacity: 0.18,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFF4D7099),
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFD6E6F4),
    iconDraw: Color(0xFF7898BF),
    iconMood: Color(0xFF7898BF),
    iconCalendar: Color(0xFF7898BF),
    iconPost: Color(0xFF7898BF),
    navActiveBg: Color(0xFFE6F0FA),
    navActiveIcon: Color(0xFF7898BF),
    promptButtonColor: Color(0xFF7898BF),
    timerDialBackground: Color(0xFFC1D6EB),
  );

  // ── 3: Персиковая (Soft Peach) ─────────────────────────────────────────────
  static const orange = AppTheme(
    index: 3,
    name: 'Персиковая',
    primary: Color(0xFFCF7E5E), // мягкий тёплый терракот
    primaryLight: Color(0xFFFDF3EE),
    bgGradient: [Color(0xFFFEF4EE), Color(0xFFFFFBF8)],
    heroGradient: [Color(0xFFE5AA8E), Color(0xFFCF7E5E)],
    heroShadowBase: Color(0x26CF7E5E),
    heroShadowExpanded: Color(0x40CF7E5E),
    heroGlassOpacity: 0.20,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFFCF7E5E),
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFEDE4DC),
    iconDraw: Color(0xFFCF7E5E),
    iconMood: Color(0xFFCF7E5E),
    iconCalendar: Color(0xFFCF7E5E),
    iconPost: Color(0xFFCF7E5E),
    navActiveBg: Color(0xFFFDF2EB),
    navActiveIcon: Color(0xFFCF7E5E),
    promptButtonColor: Color(0xFFCF7E5E),
    timerDialBackground: Color(0xFFF1CBB6),
    bgImageUrl:
        'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fpersic-background.webp?alt=media',
  );

  // ── 4: Шалфейная (Warm Sage) ─────────────────────────────────────────────
  static const green = AppTheme(
    index: 4,
    name: 'Шалфейная',
    primary: Color(0xFF7EA876), // тёплый мягкий шалфей
    primaryLight: Color(0xFFEBF5E6),
    bgGradient: [Color(0xFFF2F8EF), Color(0xFFFAFDF8)],
    heroGradient: [Color(0xFFA8C9A2), Color(0xFF7EA876)],
    heroShadowBase: Color(0x267EA876),
    heroShadowExpanded: Color(0x407EA876),
    heroGlassOpacity: 0.22,
    heroToggleBorder: true,
    heroToggleSelectedColor: Color(0xFF4E7649),
    cardSurface: Color(0xFFFBFDF9),
    cardBorder: Color(0xFFD4ECCE),
    iconDraw: Color(0xFF7EA876),
    iconMood: Color(0xFF7EA876),
    iconCalendar: Color(0xFF7EA876),
    iconPost: Color(0xFF7EA876),
    navActiveBg: Color(0xFFE5F3E1),
    navActiveIcon: Color(0xFF7EA876),
    promptButtonColor: Color(0xFF7EA876),
    timerDialBackground: Color(0xFFCEDDC6),
    bgImageUrl:
        'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fgreen-background.webp?alt=media',
  );

  // ── Список всех тем (порядок = индекс) ───────────────────────────────────
  static const List<AppTheme> all = [pink, purple, blue, orange, green];

  /// Найти тему по индексу; при выходе за границы — возвращает [pink]
  static AppTheme byIndex(int index) {
    if (index >= 0 && index < all.length) return all[index];
    return pink;
  }
}
