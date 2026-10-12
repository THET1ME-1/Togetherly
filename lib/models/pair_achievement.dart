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

/// Уровень достижения. На экране он читается формой под рисунком: чем выше
/// уровень, тем больше зубцов у «печенья» (см. `achievementShape`). Цвета у
/// уровня нет — фигуру красит тема.
enum AchievementTier { bronze, silver, gold, platinum }

/// Достижение ПАРЫ (не пользователя): общее для обоих партнёров, хранится на
/// group-доке (JSON-поле `achievements`), переживает переустановку. Разблокируется
/// автоматически, когда соответствующий счётчик достигает порога.
///
/// Каталог статичен и типобезопасен (по образцу [ProfileIcon]/[DailyTask]).
/// Рисунок достижения живёт в серверном каталоге записью вида `art` с ключом
/// [artKey], а в сборке лежит неподвижный кадр [stillAsset]. У семьи (все
/// достижения одной метрики) общая тема, и рисунок растёт вместе с порогом:
/// серия дней — огонь от спички до костра в короне.
class PairAchievement {
  /// Стабильный id — ключ хранения в `group.achievements`.
  final String id;

  final AchievementMetric metric;

  /// Порог (включительно): достижение разблокируется при `значение >= threshold`.
  final int threshold;

  final AchievementTier tier;

  const PairAchievement({
    required this.id,
    required this.metric,
    required this.threshold,
    required this.tier,
  });

  /// Название и описание живут в словаре: ключ считается из id, поэтому язык
  /// добавляется колонкой в `lib/l10n/dict/achievements.dart`, а не полем тут.
  String get title => trKey('ach_${id}_title');
  String get description => trKey('ach_${id}_desc');

  /// Ключ рисунка в каталоге (`catalog_items`, вид `art`, id `art_ach_<id>`).
  String get artKey => 'ach_$id';

  /// Неподвижный кадр из сборки: его видно, пока каталог не пришёл, и без сети.
  String get stillAsset => 'assets/images/achievements/$id.webp';

  /// Текущее «сырое» значение метрики из снимка счётчиков.
  int currentValue(AchievementStats s) => s.valueOf(metric);

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

  /// Семья — все достижения одной метрики по возрастанию порога.
  static List<PairAchievement> family(AchievementMetric metric) => [
    for (final a in all)
      if (a.metric == metric) a,
  ];

  /// Ближайшая цель семьи: первое достижение, до которого счётчик не дошёл.
  /// null — семья собрана целиком.
  static PairAchievement? nextGoal(
    AchievementMetric metric,
    AchievementStats stats,
  ) {
    for (final a in family(metric)) {
      if (!a.isUnlockedBy(stats)) return a;
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
    // ── Дни вместе: сад ───────────────────────────────────────────────────
    PairAchievement(
      id: 'together_7',
      metric: AchievementMetric.daysTogether,
      threshold: 7,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'together_30',
      metric: AchievementMetric.daysTogether,
      threshold: 30,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'together_100',
      metric: AchievementMetric.daysTogether,
      threshold: 100,
      tier: AchievementTier.silver,
    ),
    PairAchievement(
      id: 'together_182',
      metric: AchievementMetric.daysTogether,
      threshold: 182,
      tier: AchievementTier.silver,
    ),
    PairAchievement(
      id: 'together_365',
      metric: AchievementMetric.daysTogether,
      threshold: 365,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'together_500',
      metric: AchievementMetric.daysTogether,
      threshold: 500,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'together_730',
      metric: AchievementMetric.daysTogether,
      threshold: 730,
      tier: AchievementTier.platinum,
    ),
    PairAchievement(
      id: 'together_1000',
      metric: AchievementMetric.daysTogether,
      threshold: 1000,
      tier: AchievementTier.platinum,
    ),
    PairAchievement(
      id: 'together_1095',
      metric: AchievementMetric.daysTogether,
      threshold: 1095,
      tier: AchievementTier.platinum,
    ),
    PairAchievement(
      id: 'together_1825',
      metric: AchievementMetric.daysTogether,
      threshold: 1825,
      tier: AchievementTier.platinum,
    ),

    // ── Воспоминания: карточки ────────────────────────────────────────────
    PairAchievement(
      id: 'memories_1',
      metric: AchievementMetric.memories,
      threshold: 1,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'memories_10',
      metric: AchievementMetric.memories,
      threshold: 10,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'memories_25',
      metric: AchievementMetric.memories,
      threshold: 25,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'memories_50',
      metric: AchievementMetric.memories,
      threshold: 50,
      tier: AchievementTier.silver,
    ),
    PairAchievement(
      id: 'memories_100',
      metric: AchievementMetric.memories,
      threshold: 100,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'memories_250',
      metric: AchievementMetric.memories,
      threshold: 250,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'memories_500',
      metric: AchievementMetric.memories,
      threshold: 500,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'memories_1000',
      metric: AchievementMetric.memories,
      threshold: 1000,
      tier: AchievementTier.platinum,
    ),

    // ── Переписка: почта ──────────────────────────────────────────────────
    PairAchievement(
      id: 'messages_1',
      metric: AchievementMetric.messages,
      threshold: 1,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'messages_10',
      metric: AchievementMetric.messages,
      threshold: 10,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'messages_25',
      metric: AchievementMetric.messages,
      threshold: 25,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'messages_100',
      metric: AchievementMetric.messages,
      threshold: 100,
      tier: AchievementTier.silver,
    ),
    PairAchievement(
      id: 'messages_500',
      metric: AchievementMetric.messages,
      threshold: 500,
      tier: AchievementTier.silver,
    ),
    PairAchievement(
      id: 'messages_1000',
      metric: AchievementMetric.messages,
      threshold: 1000,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'messages_5000',
      metric: AchievementMetric.messages,
      threshold: 5000,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'messages_10000',
      metric: AchievementMetric.messages,
      threshold: 10000,
      tier: AchievementTier.platinum,
    ),
    PairAchievement(
      id: 'messages_50000',
      metric: AchievementMetric.messages,
      threshold: 50000,
      tier: AchievementTier.platinum,
    ),

    // ── Рисунки: мастерская ───────────────────────────────────────────────
    PairAchievement(
      id: 'drawings_1',
      metric: AchievementMetric.drawings,
      threshold: 1,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'drawings_5',
      metric: AchievementMetric.drawings,
      threshold: 5,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'drawings_10',
      metric: AchievementMetric.drawings,
      threshold: 10,
      tier: AchievementTier.silver,
    ),
    PairAchievement(
      id: 'drawings_50',
      metric: AchievementMetric.drawings,
      threshold: 50,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'drawings_100',
      metric: AchievementMetric.drawings,
      threshold: 100,
      tier: AchievementTier.platinum,
    ),

    // ── Серия дней: огонь ─────────────────────────────────────────────────
    PairAchievement(
      id: 'streak_7',
      metric: AchievementMetric.streakDays,
      threshold: 7,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'streak_14',
      metric: AchievementMetric.streakDays,
      threshold: 14,
      tier: AchievementTier.bronze,
    ),
    PairAchievement(
      id: 'streak_30',
      metric: AchievementMetric.streakDays,
      threshold: 30,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'streak_60',
      metric: AchievementMetric.streakDays,
      threshold: 60,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'streak_100',
      metric: AchievementMetric.streakDays,
      threshold: 100,
      tier: AchievementTier.gold,
    ),
    PairAchievement(
      id: 'streak_365',
      metric: AchievementMetric.streakDays,
      threshold: 365,
      tier: AchievementTier.platinum,
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

  /// Значение счётчика, который проверяет [metric].
  int valueOf(AchievementMetric metric) => switch (metric) {
    AchievementMetric.daysTogether => daysTogether,
    AchievementMetric.memories => memories,
    AchievementMetric.messages => messages,
    AchievementMetric.drawings => drawings,
    AchievementMetric.streakDays => streakDays,
  };
}
