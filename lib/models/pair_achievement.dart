import 'dart:ui';

import '../dict_strings.dart';

/// Что за счётчик проверяет достижение. Значения-снимки собираются на клиенте из
/// уже доступных источников (см. [PairAchievement.evaluate]).
enum AchievementMetric {
  /// Дни в паре — `connection.daysInLove`.
  daysTogether,

  /// Всего воспоминаний в ленте — `group.memories_count`.
  memories,

  /// Сообщений в чате — `group.messages_count`.
  messages,

  /// Рисунков на общем холсте — `group.drawings_count`.
  drawings,

  /// Дней подряд, когда заходили оба — `group.streak_days`.
  streakDays,
}

/// Визуальный «уровень» достижения — задаёт цвет медали и градиент карточки.
enum AchievementTier { bronze, silver, gold, platinum }

/// Строгая геометрическая фигура уровня.
///
/// Ранг читается по числу граней: бронза — квадрат, серебро — шестиугольник,
/// золото — восьмиугольник, платина — двенадцатиугольник. Мягких «клякс» здесь
/// нет намеренно: отметка о заслуге должна выглядеть чеканной.
class AchievementShape {
  const AchievementShape({
    required this.sides,
    required this.rotation,
    required this.corner,
  });

  /// Число углов.
  final int sides;

  /// Поворот, чтобы фигура стояла на стороне, а не на вершине.
  final double rotation;

  /// Скругление углов долей радиуса.
  final double corner;
}

/// Фигура для уровня. У каждого своя — по ней достижение узнаётся с одного
/// взгляда, даже когда цвет приглушён.
AchievementShape achievementShapeFor(AchievementTier tier) => switch (tier) {
  AchievementTier.bronze => const AchievementShape(
    sides: 4,
    rotation: 0.7853981634,
    corner: 0.28,
  ),
  AchievementTier.silver => const AchievementShape(
    sides: 6,
    rotation: 0.5235987756,
    corner: 0.22,
  ),
  AchievementTier.gold => const AchievementShape(
    sides: 8,
    rotation: 0.3926990817,
    corner: 0.18,
  ),
  AchievementTier.platinum => const AchievementShape(
    sides: 12,
    rotation: 0.2617993878,
    corner: 0.14,
  ),
};

/// Достижение ПАРЫ (не пользователя): общее для обоих партнёров, хранится на
/// group-доке (JSON-поле `achievements`), переживает переустановку. Разблокируется
/// автоматически, когда соответствующий счётчик достигает порога.
///
/// Каталог статичен и типобезопасен (по образцу [ProfileIcon]/[DailyTask]); RU/EN
/// встроены в модель. Иконка — эмодзи (без ассетов): «красиво» достигается
/// градиентом уровня + анимацией разблокировки, а не растровыми бейджами.
class PairAchievement {
  /// Стабильный id — ключ хранения в `group.achievements`.
  final String id;

  final AchievementMetric metric;

  /// Порог (включительно): достижение разблокируется при `значение >= threshold`.
  final int threshold;

  final AchievementTier tier;

  final String emoji;

  const PairAchievement({
    required this.id,
    required this.metric,
    required this.threshold,
    required this.tier,
    required this.emoji,
  });

  /// Название и описание живут в словаре: ключ считается из id, поэтому язык
  /// добавляется колонкой в `lib/l10n/dict/achievements.dart`, а не полем тут.
  String get title => trKey('ach_${id}_title');
  String get description => trKey('ach_${id}_desc');

  /// Цвет медали/акцента уровня.
  Color get tierColor {
    switch (tier) {
      case AchievementTier.bronze:
        return const Color(0xFFCD7F32);
      case AchievementTier.silver:
        return const Color(0xFF9AA6B2);
      case AchievementTier.gold:
        return const Color(0xFFE8B923);
      case AchievementTier.platinum:
        return const Color(0xFF6EC1E4);
    }
  }

  /// Мягкий градиент карточки уровня (для разблокированного состояния).
  List<Color> get tierGradient {
    switch (tier) {
      case AchievementTier.bronze:
        return const [Color(0xFFE7A977), Color(0xFFB86B3A)];
      case AchievementTier.silver:
        return const [Color(0xFFCBD3DC), Color(0xFF98A2AE)];
      case AchievementTier.gold:
        return const [Color(0xFFF6D365), Color(0xFFE0A422)];
      case AchievementTier.platinum:
        return const [Color(0xFF9BE3F2), Color(0xFF5EA9D6)];
    }
  }

  /// Текущее «сырое» значение метрики из снимка счётчиков.
  int currentValue(AchievementStats s) {
    switch (metric) {
      case AchievementMetric.daysTogether:
        return s.daysTogether;
      case AchievementMetric.memories:
        return s.memories;
      case AchievementMetric.messages:
        return s.messages;
      case AchievementMetric.drawings:
        return s.drawings;
      case AchievementMetric.streakDays:
        return s.streakDays;
    }
  }

  bool isUnlockedBy(AchievementStats s) => currentValue(s) >= threshold;

  /// Прогресс к разблокировке 0..1 (для карточки «ещё не открыто»).
  double progress(AchievementStats s) {
    if (threshold <= 0) return 1;
    final p = currentValue(s) / threshold;
    return p.clamp(0.0, 1.0);
  }

  static PairAchievement? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Разблокированные данным снимком, но ещё не отмеченные в [alreadyUnlocked].
  /// Порядок — как в каталоге (стабильно для показа серии разблокировок).
  static List<PairAchievement> newlyUnlocked(
    AchievementStats stats,
    Set<String> alreadyUnlocked,
  ) => all
      .where((a) => !alreadyUnlocked.contains(a.id) && a.isUnlockedBy(stats))
      .toList();

  /// Полный каталог, сгруппирован по темам (дни вместе → воспоминания → чат →
  /// активность), внутри — по возрастанию порога.
  static const List<PairAchievement> all = <PairAchievement>[
    // ── Дни вместе ────────────────────────────────────────────────────────
    PairAchievement(
      id: 'together_7',
      metric: AchievementMetric.daysTogether,
      threshold: 7,
      tier: AchievementTier.bronze,
      emoji: '🌱',
    ),
    PairAchievement(
      id: 'together_30',
      metric: AchievementMetric.daysTogether,
      threshold: 30,
      tier: AchievementTier.bronze,
      emoji: '🌸',
    ),
    PairAchievement(
      id: 'together_100',
      metric: AchievementMetric.daysTogether,
      threshold: 100,
      tier: AchievementTier.silver,
      emoji: '💯',
    ),
    PairAchievement(
      id: 'together_182',
      metric: AchievementMetric.daysTogether,
      threshold: 182,
      tier: AchievementTier.silver,
      emoji: '🌗',
    ),
    PairAchievement(
      id: 'together_365',
      metric: AchievementMetric.daysTogether,
      threshold: 365,
      tier: AchievementTier.gold,
      emoji: '🎂',
    ),
    PairAchievement(
      id: 'together_500',
      metric: AchievementMetric.daysTogether,
      threshold: 500,
      tier: AchievementTier.gold,
      emoji: '🌄',
    ),
    PairAchievement(
      id: 'together_730',
      metric: AchievementMetric.daysTogether,
      threshold: 730,
      tier: AchievementTier.platinum,
      emoji: '💞',
    ),
    PairAchievement(
      id: 'together_1000',
      metric: AchievementMetric.daysTogether,
      threshold: 1000,
      tier: AchievementTier.platinum,
      emoji: '🏔',
    ),
    PairAchievement(
      id: 'together_1095',
      metric: AchievementMetric.daysTogether,
      threshold: 1095,
      tier: AchievementTier.platinum,
      emoji: '🌠',
    ),
    PairAchievement(
      id: 'together_1825',
      metric: AchievementMetric.daysTogether,
      threshold: 1825,
      tier: AchievementTier.platinum,
      emoji: '🗻',
    ),

    // ── Воспоминания ──────────────────────────────────────────────────────
    PairAchievement(
      id: 'memories_1',
      metric: AchievementMetric.memories,
      threshold: 1,
      tier: AchievementTier.bronze,
      emoji: '📸',
    ),
    PairAchievement(
      id: 'memories_10',
      metric: AchievementMetric.memories,
      threshold: 10,
      tier: AchievementTier.bronze,
      emoji: '🗂️',
    ),
    PairAchievement(
      id: 'memories_25',
      metric: AchievementMetric.memories,
      threshold: 25,
      tier: AchievementTier.bronze,
      emoji: '📷',
    ),
    PairAchievement(
      id: 'memories_50',
      metric: AchievementMetric.memories,
      threshold: 50,
      tier: AchievementTier.silver,
      emoji: '📚',
    ),
    PairAchievement(
      id: 'memories_100',
      metric: AchievementMetric.memories,
      threshold: 100,
      tier: AchievementTier.gold,
      emoji: '🏛️',
    ),

    PairAchievement(
      id: 'memories_250',
      metric: AchievementMetric.memories,
      threshold: 250,
      tier: AchievementTier.gold,
      emoji: '🖼',
    ),
    PairAchievement(
      id: 'memories_500',
      metric: AchievementMetric.memories,
      threshold: 500,
      tier: AchievementTier.gold,
      emoji: '📚',
    ),
    PairAchievement(
      id: 'memories_1000',
      metric: AchievementMetric.memories,
      threshold: 1000,
      tier: AchievementTier.platinum,
      emoji: '🏛',
    ),
    // ── Чат ───────────────────────────────────────────────────────────────
    PairAchievement(
      id: 'messages_1',
      metric: AchievementMetric.messages,
      threshold: 1,
      tier: AchievementTier.bronze,
      emoji: '💬',
    ),
    PairAchievement(
      id: 'messages_10',
      metric: AchievementMetric.messages,
      threshold: 10,
      tier: AchievementTier.bronze,
      emoji: '💭',
    ),
    PairAchievement(
      id: 'messages_25',
      metric: AchievementMetric.messages,
      threshold: 25,
      tier: AchievementTier.bronze,
      emoji: '💌',
    ),
    PairAchievement(
      id: 'messages_100',
      metric: AchievementMetric.messages,
      threshold: 100,
      tier: AchievementTier.silver,
      emoji: '🗨️',
    ),
    PairAchievement(
      id: 'messages_500',
      metric: AchievementMetric.messages,
      threshold: 500,
      tier: AchievementTier.silver,
      emoji: '💬',
    ),
    PairAchievement(
      id: 'messages_1000',
      metric: AchievementMetric.messages,
      threshold: 1000,
      tier: AchievementTier.gold,
      emoji: '💌',
    ),

    PairAchievement(
      id: 'messages_5000',
      metric: AchievementMetric.messages,
      threshold: 5000,
      tier: AchievementTier.gold,
      emoji: '📨',
    ),
    PairAchievement(
      id: 'messages_10000',
      metric: AchievementMetric.messages,
      threshold: 10000,
      tier: AchievementTier.platinum,
      emoji: '📮',
    ),
    PairAchievement(
      id: 'messages_50000',
      metric: AchievementMetric.messages,
      threshold: 50000,
      tier: AchievementTier.platinum,
      emoji: '🗼',
    ),
    // ── Активность ────────────────────────────────────────────────────────
    PairAchievement(
      id: 'drawings_1',
      metric: AchievementMetric.drawings,
      threshold: 1,
      tier: AchievementTier.bronze,
      emoji: '🎨',
    ),
    PairAchievement(
      id: 'drawings_5',
      metric: AchievementMetric.drawings,
      threshold: 5,
      tier: AchievementTier.bronze,
      emoji: '🖌',
    ),
    PairAchievement(
      id: 'drawings_10',
      metric: AchievementMetric.drawings,
      threshold: 10,
      tier: AchievementTier.silver,
      emoji: '🎨',
    ),
    PairAchievement(
      id: 'drawings_50',
      metric: AchievementMetric.drawings,
      threshold: 50,
      tier: AchievementTier.gold,
      emoji: '🖼',
    ),
    PairAchievement(
      id: 'drawings_100',
      metric: AchievementMetric.drawings,
      threshold: 100,
      tier: AchievementTier.platinum,
      emoji: '🏆',
    ),
    PairAchievement(
      id: 'streak_7',
      metric: AchievementMetric.streakDays,
      threshold: 7,
      tier: AchievementTier.bronze,
      emoji: '🔥',
    ),
    PairAchievement(
      id: 'streak_14',
      metric: AchievementMetric.streakDays,
      threshold: 14,
      tier: AchievementTier.bronze,
      emoji: '🔥',
    ),
    PairAchievement(
      id: 'streak_30',
      metric: AchievementMetric.streakDays,
      threshold: 30,
      tier: AchievementTier.gold,
      emoji: '⚡',
    ),
    PairAchievement(
      id: 'streak_60',
      metric: AchievementMetric.streakDays,
      threshold: 60,
      tier: AchievementTier.gold,
      emoji: '🌟',
    ),
    PairAchievement(
      id: 'streak_100',
      metric: AchievementMetric.streakDays,
      threshold: 100,
      tier: AchievementTier.gold,
      emoji: '⚡️',
    ),
    PairAchievement(
      id: 'streak_365',
      metric: AchievementMetric.streakDays,
      threshold: 365,
      tier: AchievementTier.platinum,
      emoji: '👑',
    ),
  ];
}

/// Снимок счётчиков пары для оценки достижений.
class AchievementStats {
  final int daysTogether;
  final int memories;
  final int messages;
  final int drawings;
  final int streakDays;

  const AchievementStats({
    this.daysTogether = 0,
    this.memories = 0,
    this.messages = 0,
    this.drawings = 0,
    this.streakDays = 0,
  });
}
