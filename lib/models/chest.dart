import 'avatar_frame.dart';
import 'gift.dart';
import 'pair_jar.dart';
import 'profile_icon.dart';
import 'season_chest.dart';

export 'season_chest.dart';

/// Что лежит в сундуке недели и с какими шансами.
///
/// Таблицу разыгрывает сервер (`pocketbase/pb_hooks/chest.pb.js`) и отдаёт её
/// же роутом `/api/chest/state`, поэтому проценты на экране совпадают с
/// розыгрышем. Здесь — разбор ответа и запасная копия таблицы на случай, когда
/// сервер ещё не ответил.
enum ChestPrizeKind { coins, gift, plus, frame, badge, plusTrial }

enum ChestTier { common, rare, legendary }

class ChestPrize {
  const ChestPrize({required this.key, required this.kind, required this.weight, required this.tier, this.amount = 0});

  /// `coins5`, ключ подарка из [GiftCatalog.chest], `plus` или id рамки и
  /// значка в каталоге (`frame_cat`, `badge_kitty`).
  final String key;
  final ChestPrizeKind kind;

  /// Монет в призе; у подарка и Плюса ноль.
  final int amount;

  /// Вес в десятых долях процента: сумма по таблице — 1000.
  final int weight;
  final ChestTier tier;

  Gift? get gift => kind == ChestPrizeKind.gift ? GiftCatalog.byKey(key) : null;

  /// Ключ рамки аватарки (`cat` из `frame_cat`); у прочих призов null.
  String? get frameKey => kind == ChestPrizeKind.frame && key.startsWith('frame_') ? key.substring(6) : null;

  AvatarFrame? get frame => AvatarFrame.byKey(frameKey);

  /// Значок-жилец из сундука; у прочих призов null.
  ProfileIcon? get badge => kind == ChestPrizeKind.badge ? ProfileIcon.byCatalogId(key) : null;

  static ChestPrize? fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind']) {
      'coins' => ChestPrizeKind.coins,
      'gift' => ChestPrizeKind.gift,
      'plus' => ChestPrizeKind.plus,
      'frame' => ChestPrizeKind.frame,
      'badge' => ChestPrizeKind.badge,
      'plus_trial' => ChestPrizeKind.plusTrial,
      _ => null,
    };
    final key = (j['key'] ?? '').toString();
    if (kind == null || key.isEmpty) return null;
    // Подарок, которого эта сборка не знает, показать нечем — строку пропускаем.
    if (kind == ChestPrizeKind.gift && GiftCatalog.byKey(key) == null) {
      return null;
    }
    final tier = switch (j['tier']) {
      'rare' => ChestTier.rare,
      'legendary' => ChestTier.legendary,
      _ => ChestTier.common,
    };
    return ChestPrize(
      key: key,
      kind: kind,
      amount: (j['amount'] as num?)?.toInt() ?? 0,
      weight: (j['weight'] as num?)?.toInt() ?? 0,
      tier: tier,
    );
  }
}

class ChestState {
  const ChestState({
    required this.left,
    required this.perDay,
    required this.odds,
    this.untilRare,
    this.jar,
    this.today = const [],
    this.seasons = const [],
    this.noAd = false,
  });

  /// Сезонные сундуки, что идут сейчас (только в ответе обычного сундука).
  final List<SeasonChest> seasons;

  /// Сервер видит человека там, где реклама недоступна (Украина): сундук
  /// открывается без ролика, а Плюс в таком открытии не разыгрывается.
  /// Страну решает сервер по адресу запроса, не приложение.
  final bool noAd;

  final int left;
  final int perDay;
  final List<ChestPrize> odds;

  /// Что выпало сегодня, по порядку открытий. Приз разыгрывается, как только
  /// ролик засчитан; ушёл с экрана до анимации — здесь видно, что он был.
  /// Пусто — ничего не открывали или сервер постарше.
  final List<ChestPrize> today;

  /// То же состояние с другим остатком и ещё одним призом дня — после
  /// удачного открытия, без лишнего запроса.
  ChestState afterOpen({required int left, int? untilRare, PairJar? jar, ChestPrize? prize}) => ChestState(
    left: left,
    perDay: perDay,
    odds: odds,
    untilRare: untilRare ?? this.untilRare,
    jar: jar,
    today: [...today, ?prize],
    seasons: seasons,
    noAd: noAd,
  );

  /// Через сколько открытий редкий приз гарантирован (1 — следующее). null —
  /// сервер постарше, гарантии не знает.
  final int? untilRare;

  /// Копилка пары; null — сервер постарше или пары нет.
  final PairJar? jar;

  static ChestState? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['ok'] != true) return null;
    final raw = j['odds'];
    final odds = <ChestPrize>[
      if (raw is List)
        for (final r in raw)
          if (r is Map) ?ChestPrize.fromJson(Map<String, dynamic>.from(r)),
    ];
    if (odds.isEmpty) return null;
    final perDay = (j['perDay'] as num?)?.toInt() ?? 3;
    return ChestState(
      left: ((j['left'] as num?)?.toInt() ?? perDay).clamp(0, perDay),
      perDay: perDay,
      odds: odds,
      untilRare: (j['untilRare'] as num?)?.toInt(),
      jar: PairJar.fromJson(j['jar']),
      today: [
        if (j['today'] case final List won)
          for (final r in won)
            if (r is Map) ?ChestPrize.fromJson(Map<String, dynamic>.from(r)),
      ],
      seasons: SeasonChest.listFromJson(j['seasons']),
      noAd: j['noAd'] == true,
    );
  }
}

/// Пул редкости в десятых долях процента — зеркало `TIER_POOL` в
/// `chest.pb.js`. Пул делится поровну между всеми предметами редкости
/// (подарки сундука, рамки и значки из каталога), поэтому подарок, рамка и
/// значок одной редкости выпадают одинаково.
const Map<String, int> kChestTierPools = {'common': 252, 'rare': 144, 'legendary': 36};

/// Сколько открытий подряд без редкого приза до гарантии — зеркало `PITY`.
const int kChestPity = 10;

/// Вес одного предмета в запасной таблице: пул, делённый на число предметов
/// редкости в каталоге на 28.09.2026 (обычных 12, редких 16, легендарных 9).
/// Настоящий вес считает сервер по живому каталогу.
const Map<ChestTier, int> _fallbackItemWeight = {ChestTier.common: 21, ChestTier.rare: 9, ChestTier.legendary: 4};

/// Запасная таблица, пока сервер не ответил: монеты, Плюс и подарки сундука
/// (рамок и значков без каталога показать нечем). Всё, что не разложено, —
/// «5 монет», сумма всегда 1000. [withPlus] = false — Плюса нет (iPhone или
/// уже куплен), его доля тоже уходит в «5 монет».
List<ChestPrize> fallbackChestOdds({required bool withPlus}) {
  const tiers = {
    'cookieheart': ChestTier.common,
    'teddy': ChestTier.common,
    'potion': ChestTier.common,
    'throne': ChestTier.rare,
    'champagne': ChestTier.rare,
    'snowglobe': ChestTier.rare,
    'rose': ChestTier.rare,
    'perfume': ChestTier.rare,
    'record': ChestTier.rare,
    'locket': ChestTier.legendary,
    'rings': ChestTier.legendary,
  };
  final gifts = [
    for (final e in tiers.entries)
      ChestPrize(key: e.key, kind: ChestPrizeKind.gift, weight: _fallbackItemWeight[e.value]!, tier: e.value),
  ];
  final rest = [
    const ChestPrize(key: 'coins10', kind: ChestPrizeKind.coins, amount: 10, weight: 180, tier: ChestTier.common),
    const ChestPrize(key: 'coins25', kind: ChestPrizeKind.coins, amount: 25, weight: 75, tier: ChestTier.rare),
    if (withPlus) const ChestPrize(key: 'plus', kind: ChestPrizeKind.plus, weight: 1, tier: ChestTier.legendary),
    if (withPlus)
      const ChestPrize(key: 'plus7', kind: ChestPrizeKind.plusTrial, amount: 7, weight: 10, tier: ChestTier.legendary),
  ];
  final used = [...gifts, ...rest].fold<int>(0, (t, p) => t + p.weight);
  return [
    ChestPrize(key: 'coins5', kind: ChestPrizeKind.coins, amount: 5, weight: 1000 - used, tier: ChestTier.common),
    rest[0],
    ...gifts.where((g) => g.tier == ChestTier.common),
    rest[1],
    ...gifts.where((g) => g.tier == ChestTier.rare),
    ...gifts.where((g) => g.tier == ChestTier.legendary),
    if (withPlus) ...[rest[2], rest[3]],
  ];
}

/// Доля приза от всей таблицы строкой: «35%», «2,5%». Десятичный знак — по
/// языку ([decimal]), ноль после запятой не пишется.
String chestPercent(ChestPrize p, List<ChestPrize> all, {String decimal = ','}) {
  final total = all.fold<int>(0, (t, e) => t + e.weight);
  if (total <= 0) return '0%';
  final tenths = (p.weight * 1000 / total).round();
  final whole = tenths ~/ 10, frac = tenths % 10;
  return frac == 0 ? '$whole%' : '$whole$decimal$frac%';
}

/// Таблица по ярусам в порядке «обычные → редкие → легендарные», внутри яруса
/// — как пришло с сервера. Пустой ярус не попадает.
List<(ChestTier, List<ChestPrize>)> chestTiers(List<ChestPrize> odds) => [
  for (final t in ChestTier.values)
    if (odds.where((p) => p.tier == t).toList() case final list when list.isNotEmpty) (t, list),
];

/// Разделы списка шансов на экране сундука. Togetherly+ стоит отдельно в
/// самом верху (`null` вместо яруса — «Главный приз»): это самое ценное в
/// сундуке, им сундук и привлекает (решение заказчика 27.09.2026). Дальше —
/// ярусы по [chestTiers] уже без него. Нет Плюса в таблице — нет и раздела.
List<(ChestTier?, List<ChestPrize>)> chestSections(List<ChestPrize> odds) {
  bool isPlus(ChestPrize p) => p.kind == ChestPrizeKind.plus || p.kind == ChestPrizeKind.plusTrial;
  final top = odds.where(isPlus).toList();
  return [if (top.isNotEmpty) (null, top), ...chestTiers(odds.where((p) => !isPlus(p)).toList())];
}

/// Где стоит приз в кадрах открытия сундука: `[x, y, сторона]` в долях
/// картинки, `null` — приз ещё внутри. Снято с той же формулы, что
/// `chestOpen` на макете (подъём, размер, покачивание, горло сундука), при
/// запекании `chest_open` (`togetherly-badges-hand/bake_chest.py`). Кадр —
/// [kChestFrameMs]. Перезапекли открытие — перенести дорожку сюда же.
const int kChestFrameMs = 60;

/// С какого кадра по макету показывается название выигрыша (2,0 с).
const int kChestWonFrame = 2000 ~/ kChestFrameMs;

const List<List<double>?> kChestPrizeTrack = [
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  [0.42764, 0.41863, 0.14471],
  [0.41453, 0.38864, 0.17093],
  [0.39848, 0.35192, 0.20304],
  [0.38036, 0.3106, 0.23928],
  [0.36107, 0.26689, 0.27787],
  [0.34148, 0.22297, 0.31705],
  [0.32248, 0.18101, 0.35505],
  [0.30495, 0.14307, 0.3901],
  [0.28978, 0.11116, 0.42045],
  [0.27785, 0.08714, 0.44431],
  [0.27004, 0.07278, 0.45992],
  [0.26724, 0.06971, 0.46552],
  [0.26724, 0.07279, 0.46552],
  [0.26724, 0.07576, 0.46552],
  [0.26724, 0.07853, 0.46552],
  [0.26724, 0.081, 0.46552],
  [0.26724, 0.0831, 0.46552],
  [0.26724, 0.08476, 0.46552],
  [0.26724, 0.08592, 0.46552],
  [0.26724, 0.08655, 0.46552],
  [0.26724, 0.08662, 0.46552],
  [0.26724, 0.08614, 0.46552],
  [0.26724, 0.08512, 0.46552],
  [0.26724, 0.08359, 0.46552],
  [0.26724, 0.0816, 0.46552],
  [0.26724, 0.07922, 0.46552],
  [0.26724, 0.07652, 0.46552],
  [0.26724, 0.07359, 0.46552],
  [0.26724, 0.07053, 0.46552],
  [0.26724, 0.06743, 0.46552],
  [0.26724, 0.0644, 0.46552],
  [0.26724, 0.06153, 0.46552],
  [0.26724, 0.05891, 0.46552],
  [0.26724, 0.05663, 0.46552],
  [0.26724, 0.05477, 0.46552],
  [0.26724, 0.05338, 0.46552],
  [0.26724, 0.0525, 0.46552],
  [0.26724, 0.05218, 0.46552],
  [0.26724, 0.05241, 0.46552],
];

/// Последнее положение приза над открытым сундуком — так он лежит на
/// карточке «Поделиться».
final List<double> kChestPrizeRest = kChestPrizeTrack.lastWhere((s) => s != null)!;

/// Ярус приза на карточке «Поделиться»: ключ строки и выделять ли его
/// заливкой. Плюс — «Главный приз», как в списке шансов; легендарное тоже
/// выделено — им и хвастаются.
(String, bool) chestShareTier(ChestPrize p) {
  if (p.kind == ChestPrizeKind.plus || p.kind == ChestPrizeKind.plusTrial) return ('chestTierTop', true);
  return switch (p.tier) {
    ChestTier.legendary => ('chestShareLegendary', true),
    ChestTier.rare => ('chestShareRare', false),
    ChestTier.common => ('chestShareCommon', false),
  };
}
