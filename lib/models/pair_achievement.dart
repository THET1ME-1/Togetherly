import 'dart:ui';

import '../services/locale_service.dart';

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
      AchievementTier.bronze =>
        const AchievementShape(sides: 4, rotation: 0.7853981634, corner: 0.28),
      AchievementTier.silver =>
        const AchievementShape(sides: 6, rotation: 0.5235987756, corner: 0.22),
      AchievementTier.gold =>
        const AchievementShape(sides: 8, rotation: 0.3926990817, corner: 0.18),
      AchievementTier.platinum =>
        const AchievementShape(sides: 12, rotation: 0.2617993878, corner: 0.14),
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
  final String _titleRu;
  final String _titleEn;
  final String _descRu;
  final String _descEn;

  const PairAchievement({
    required this.id,
    required this.metric,
    required this.threshold,
    required this.tier,
    required this.emoji,
    required String titleRu,
    required String titleEn,
    required String descRu,
    required String descEn,
  })  : _titleRu = titleRu,
        _titleEn = titleEn,
        _descRu = descRu,
        _descEn = descEn;

  bool get _ru => LocaleService.instance.isRussian;
  String get title => _ru ? _titleRu : _titleEn;
  String get description => _ru ? _descRu : _descEn;

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
  ) =>
      all
          .where((a) =>
              !alreadyUnlocked.contains(a.id) && a.isUnlockedBy(stats))
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
      titleRu: 'Неделя вместе',
      titleEn: 'One week together',
      descRu: '7 дней в паре',
      descEn: '7 days as a couple',
    ),
    PairAchievement(
      id: 'together_30',
      metric: AchievementMetric.daysTogether,
      threshold: 30,
      tier: AchievementTier.bronze,
      emoji: '🌸',
      titleRu: 'Месяц вместе',
      titleEn: 'One month together',
      descRu: '30 дней в паре',
      descEn: '30 days as a couple',
    ),
    PairAchievement(
      id: 'together_100',
      metric: AchievementMetric.daysTogether,
      threshold: 100,
      tier: AchievementTier.silver,
      emoji: '💯',
      titleRu: '100 дней вместе',
      titleEn: '100 days together',
      descRu: 'Три с лишним месяца рядом',
      descEn: 'Over three months side by side',
    ),
    PairAchievement(
      id: 'together_182',
      metric: AchievementMetric.daysTogether,
      threshold: 182,
      tier: AchievementTier.silver,
      emoji: '🌗',
      titleRu: 'Полгода вместе',
      titleEn: 'Half a year together',
      descRu: '182 дня в паре',
      descEn: '182 days as a couple',
    ),
    PairAchievement(
      id: 'together_365',
      metric: AchievementMetric.daysTogether,
      threshold: 365,
      tier: AchievementTier.gold,
      emoji: '🎂',
      titleRu: 'Год вместе',
      titleEn: 'One year together',
      descRu: 'Целый год любви',
      descEn: 'A whole year of love',
    ),
    PairAchievement(
      id: 'together_500',
      metric: AchievementMetric.daysTogether,
      threshold: 500,
      tier: AchievementTier.gold,
      emoji: '🌄',
      titleRu: 'Пятьсот дней',
      titleEn: 'Five hundred days',
      descRu: '500 дней в паре',
      descEn: '500 days as a couple',
    ),
    PairAchievement(
      id: 'together_730',
      metric: AchievementMetric.daysTogether,
      threshold: 730,
      tier: AchievementTier.platinum,
      emoji: '💞',
      titleRu: 'Два года вместе',
      titleEn: 'Two years together',
      descRu: '730 дней рядом',
      descEn: '730 days side by side',
    ),
    PairAchievement(
      id: 'together_1000',
      metric: AchievementMetric.daysTogether,
      threshold: 1000,
      tier: AchievementTier.platinum,
      emoji: '🏔',
      titleRu: 'Тысяча дней',
      titleEn: 'A thousand days',
      descRu: '1000 дней в паре',
      descEn: '1000 days as a couple',
    ),
    PairAchievement(
      id: 'together_1095',
      metric: AchievementMetric.daysTogether,
      threshold: 1095,
      tier: AchievementTier.platinum,
      emoji: '🌠',
      titleRu: 'Три года',
      titleEn: 'Three years',
      descRu: 'Три года вместе',
      descEn: 'Three years together',
    ),
    PairAchievement(
      id: 'together_1825',
      metric: AchievementMetric.daysTogether,
      threshold: 1825,
      tier: AchievementTier.platinum,
      emoji: '🗻',
      titleRu: 'Пять лет',
      titleEn: 'Five years',
      descRu: 'Пять лет вместе',
      descEn: 'Five years together',
    ),

    // ── Воспоминания ──────────────────────────────────────────────────────
    PairAchievement(
      id: 'memories_1',
      metric: AchievementMetric.memories,
      threshold: 1,
      tier: AchievementTier.bronze,
      emoji: '📸',
      titleRu: 'Первое воспоминание',
      titleEn: 'First memory',
      descRu: 'Начало вашей ленты',
      descEn: 'The start of your feed',
    ),
    PairAchievement(
      id: 'memories_10',
      metric: AchievementMetric.memories,
      threshold: 10,
      tier: AchievementTier.bronze,
      emoji: '🗂️',
      titleRu: '10 воспоминаний',
      titleEn: '10 memories',
      descRu: 'Лента набирает обороты',
      descEn: 'Your feed is growing',
    ),
    PairAchievement(
      id: 'memories_25',
      metric: AchievementMetric.memories,
      threshold: 25,
      tier: AchievementTier.bronze,
      emoji: '📷',
      titleRu: 'Двадцать пять кадров',
      titleEn: 'Twenty five shots',
      descRu: '25 воспоминаний в ленте',
      descEn: '25 memories in the feed',
    ),
    PairAchievement(
      id: 'memories_50',
      metric: AchievementMetric.memories,
      threshold: 50,
      tier: AchievementTier.silver,
      emoji: '📚',
      titleRu: '50 воспоминаний',
      titleEn: '50 memories',
      descRu: 'Целая коллекция моментов',
      descEn: 'A whole collection of moments',
    ),
    PairAchievement(
      id: 'memories_100',
      metric: AchievementMetric.memories,
      threshold: 100,
      tier: AchievementTier.gold,
      emoji: '🏛️',
      titleRu: '100 воспоминаний',
      titleEn: '100 memories',
      descRu: 'Ваш маленький музей',
      descEn: 'Your little museum',
    ),

    PairAchievement(
      id: 'memories_250',
      metric: AchievementMetric.memories,
      threshold: 250,
      tier: AchievementTier.gold,
      emoji: '🖼',
      titleRu: 'Двести пятьдесят кадров',
      titleEn: '250 shots',
      descRu: '250 воспоминаний',
      descEn: '250 memories',
    ),
    PairAchievement(
      id: 'memories_500',
      metric: AchievementMetric.memories,
      threshold: 500,
      tier: AchievementTier.gold,
      emoji: '📚',
      titleRu: 'Полтысячи моментов',
      titleEn: 'Half a thousand moments',
      descRu: '500 воспоминаний',
      descEn: '500 memories',
    ),
    PairAchievement(
      id: 'memories_1000',
      metric: AchievementMetric.memories,
      threshold: 1000,
      tier: AchievementTier.platinum,
      emoji: '🏛',
      titleRu: 'Тысяча воспоминаний',
      titleEn: 'A thousand memories',
      descRu: '1000 моментов в ленте',
      descEn: '1000 moments in the feed',
    ),
    // ── Чат ───────────────────────────────────────────────────────────────
    PairAchievement(
      id: 'messages_1',
      metric: AchievementMetric.messages,
      threshold: 1,
      tier: AchievementTier.bronze,
      emoji: '💬',
      titleRu: 'Первое сообщение',
      titleEn: 'First message',
      descRu: 'Разговор начался',
      descEn: 'The conversation begins',
    ),
    PairAchievement(
      id: 'messages_10',
      metric: AchievementMetric.messages,
      threshold: 10,
      tier: AchievementTier.bronze,
      emoji: '💭',
      titleRu: 'Первый разговор',
      titleEn: 'First conversation',
      descRu: '10 сообщений в чате',
      descEn: '10 chat messages',
    ),
    PairAchievement(
      id: 'messages_25',
      metric: AchievementMetric.messages,
      threshold: 25,
      tier: AchievementTier.bronze,
      emoji: '💌',
      titleRu: 'Двадцать пять сообщений',
      titleEn: 'Twenty five messages',
      descRu: 'Переписка завязалась',
      descEn: 'The conversation took off',
    ),
    PairAchievement(
      id: 'messages_100',
      metric: AchievementMetric.messages,
      threshold: 100,
      tier: AchievementTier.silver,
      emoji: '🗨️',
      titleRu: '100 сообщений',
      titleEn: '100 messages',
      descRu: 'Вам есть о чём поговорить',
      descEn: "You've got plenty to talk about",
    ),
    PairAchievement(
      id: 'messages_500',
      metric: AchievementMetric.messages,
      threshold: 500,
      tier: AchievementTier.silver,
      emoji: '💬',
      titleRu: 'Пятьсот сообщений',
      titleEn: 'Five hundred messages',
      descRu: '500 сообщений в чате',
      descEn: '500 chat messages',
    ),
    PairAchievement(
      id: 'messages_1000',
      metric: AchievementMetric.messages,
      threshold: 1000,
      tier: AchievementTier.gold,
      emoji: '💌',
      titleRu: '1000 сообщений',
      titleEn: '1000 messages',
      descRu: 'Болтушки года',
      descEn: 'Chatterboxes of the year',
    ),

    PairAchievement(
      id: 'messages_5000',
      metric: AchievementMetric.messages,
      threshold: 5000,
      tier: AchievementTier.gold,
      emoji: '📨',
      titleRu: 'Пять тысяч',
      titleEn: 'Five thousand',
      descRu: '5000 сообщений',
      descEn: '5000 messages',
    ),
    PairAchievement(
      id: 'messages_10000',
      metric: AchievementMetric.messages,
      threshold: 10000,
      tier: AchievementTier.platinum,
      emoji: '📮',
      titleRu: 'Десять тысяч',
      titleEn: 'Ten thousand',
      descRu: '10 000 сообщений',
      descEn: '10,000 messages',
    ),
    PairAchievement(
      id: 'messages_50000',
      metric: AchievementMetric.messages,
      threshold: 50000,
      tier: AchievementTier.platinum,
      emoji: '🗼',
      titleRu: 'Полсотни тысяч',
      titleEn: 'Fifty thousand',
      descRu: '50 000 сообщений',
      descEn: '50,000 messages',
    ),
    // ── Активность ────────────────────────────────────────────────────────
    PairAchievement(
      id: 'drawings_1',
      metric: AchievementMetric.drawings,
      threshold: 1,
      tier: AchievementTier.bronze,
      emoji: '🎨',
      titleRu: 'Первый рисунок',
      titleEn: 'First drawing',
      descRu: 'Творчество на двоих',
      descEn: 'Creativity for two',
    ),
    PairAchievement(
      id: 'drawings_5',
      metric: AchievementMetric.drawings,
      threshold: 5,
      tier: AchievementTier.bronze,
      emoji: '🖌',
      titleRu: 'Пять холстов',
      titleEn: 'Five canvases',
      descRu: '5 рисунков вдвоём',
      descEn: '5 drawings together',
    ),
    PairAchievement(
      id: 'drawings_10',
      metric: AchievementMetric.drawings,
      threshold: 10,
      tier: AchievementTier.silver,
      emoji: '🎨',
      titleRu: 'Десять рисунков',
      titleEn: 'Ten drawings',
      descRu: '10 рисунков вдвоём',
      descEn: '10 drawings together',
    ),
    PairAchievement(
      id: 'drawings_50',
      metric: AchievementMetric.drawings,
      threshold: 50,
      tier: AchievementTier.gold,
      emoji: '🖼',
      titleRu: 'Полсотни рисунков',
      titleEn: 'Fifty drawings',
      descRu: '50 рисунков вдвоём',
      descEn: '50 drawings together',
    ),
    PairAchievement(
      id: 'drawings_100',
      metric: AchievementMetric.drawings,
      threshold: 100,
      tier: AchievementTier.platinum,
      emoji: '🏆',
      titleRu: 'Сто рисунков',
      titleEn: 'A hundred drawings',
      descRu: '100 рисунков вдвоём',
      descEn: '100 drawings together',
    ),
    PairAchievement(
      id: 'streak_7',
      metric: AchievementMetric.streakDays,
      threshold: 7,
      tier: AchievementTier.bronze,
      emoji: '🔥',
      titleRu: 'Неделя подряд',
      titleEn: '7-day streak',
      descRu: '7 дней заходите оба',
      descEn: 'Both of you showed up 7 days in a row',
    ),
    PairAchievement(
      id: 'streak_14',
      metric: AchievementMetric.streakDays,
      threshold: 14,
      tier: AchievementTier.bronze,
      emoji: '🔥',
      titleRu: 'Две недели подряд',
      titleEn: 'Two weeks in a row',
      descRu: '14 дней подряд вдвоём',
      descEn: '14 days in a row',
    ),
    PairAchievement(
      id: 'streak_30',
      metric: AchievementMetric.streakDays,
      threshold: 30,
      tier: AchievementTier.gold,
      emoji: '⚡',
      titleRu: 'Месяц подряд',
      titleEn: '30-day streak',
      descRu: '30 дней вы оба на связи',
      descEn: 'Both of you stayed connected 30 days',
    ),
    PairAchievement(
      id: 'streak_60',
      metric: AchievementMetric.streakDays,
      threshold: 60,
      tier: AchievementTier.gold,
      emoji: '🌟',
      titleRu: 'Два месяца подряд',
      titleEn: 'Two months in a row',
      descRu: '60 дней подряд вдвоём',
      descEn: '60 days in a row',
    ),
    PairAchievement(
      id: 'streak_100',
      metric: AchievementMetric.streakDays,
      threshold: 100,
      tier: AchievementTier.gold,
      emoji: '⚡️',
      titleRu: 'Сто дней подряд',
      titleEn: 'A hundred days in a row',
      descRu: '100 дней подряд вдвоём',
      descEn: '100 days in a row',
    ),
    PairAchievement(
      id: 'streak_365',
      metric: AchievementMetric.streakDays,
      threshold: 365,
      tier: AchievementTier.platinum,
      emoji: '👑',
      titleRu: 'Год без пропусков',
      titleEn: 'A year without a miss',
      descRu: '365 дней подряд вдвоём',
      descEn: '365 days in a row',
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
