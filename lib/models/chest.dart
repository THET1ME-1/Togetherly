import 'gift.dart';

/// Что лежит в сундуке недели и с какими шансами.
///
/// Таблицу разыгрывает сервер (`pocketbase/pb_hooks/chest.pb.js`) и отдаёт её
/// же роутом `/api/chest/state`, поэтому проценты на экране совпадают с
/// розыгрышем. Здесь — разбор ответа и запасная копия таблицы на случай, когда
/// сервер ещё не ответил.
enum ChestPrizeKind { coins, gift, plus }

enum ChestTier { common, rare, legendary }

class ChestPrize {
  const ChestPrize({required this.key, required this.kind, required this.weight, required this.tier, this.amount = 0});

  /// `coins5`, ключ подарка из [GiftCatalog.chest] или `plus`.
  final String key;
  final ChestPrizeKind kind;

  /// Монет в призе; у подарка и Плюса ноль.
  final int amount;

  /// Вес в десятых долях процента: сумма по таблице — 1000.
  final int weight;
  final ChestTier tier;

  Gift? get gift => kind == ChestPrizeKind.gift ? GiftCatalog.byKey(key) : null;

  static ChestPrize? fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind']) {
      'coins' => ChestPrizeKind.coins,
      'gift' => ChestPrizeKind.gift,
      'plus' => ChestPrizeKind.plus,
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
  const ChestState({required this.left, required this.perDay, required this.odds});

  final int left;
  final int perDay;
  final List<ChestPrize> odds;

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
    return ChestState(left: ((j['left'] as num?)?.toInt() ?? perDay).clamp(0, perDay), perDay: perDay, odds: odds);
  }
}

/// Запасная таблица — зеркало `ODDS` в `chest.pb.js`. [withPlus] = false —
/// Плюса нет (iPhone или уже куплен), его доля уходит в «5 монет».
List<ChestPrize> fallbackChestOdds({required bool withPlus}) => [
  ChestPrize(
    key: 'coins5',
    kind: ChestPrizeKind.coins,
    amount: 5,
    weight: withPlus ? 350 : 400,
    tier: ChestTier.common,
  ),
  const ChestPrize(key: 'coins10', kind: ChestPrizeKind.coins, amount: 10, weight: 200, tier: ChestTier.common),
  const ChestPrize(key: 'cookieheart', kind: ChestPrizeKind.gift, weight: 50, tier: ChestTier.common),
  const ChestPrize(key: 'teddy', kind: ChestPrizeKind.gift, weight: 40, tier: ChestTier.common),
  const ChestPrize(key: 'potion', kind: ChestPrizeKind.gift, weight: 40, tier: ChestTier.common),
  const ChestPrize(key: 'coins25', kind: ChestPrizeKind.coins, amount: 25, weight: 80, tier: ChestTier.rare),
  const ChestPrize(key: 'throne', kind: ChestPrizeKind.gift, weight: 30, tier: ChestTier.rare),
  const ChestPrize(key: 'champagne', kind: ChestPrizeKind.gift, weight: 30, tier: ChestTier.rare),
  const ChestPrize(key: 'snowglobe', kind: ChestPrizeKind.gift, weight: 30, tier: ChestTier.rare),
  const ChestPrize(key: 'rose', kind: ChestPrizeKind.gift, weight: 25, tier: ChestTier.rare),
  const ChestPrize(key: 'perfume', kind: ChestPrizeKind.gift, weight: 25, tier: ChestTier.rare),
  const ChestPrize(key: 'record', kind: ChestPrizeKind.gift, weight: 25, tier: ChestTier.rare),
  const ChestPrize(key: 'locket', kind: ChestPrizeKind.gift, weight: 15, tier: ChestTier.legendary),
  const ChestPrize(key: 'rings', kind: ChestPrizeKind.gift, weight: 10, tier: ChestTier.legendary),
  if (withPlus) const ChestPrize(key: 'plus', kind: ChestPrizeKind.plus, weight: 50, tier: ChestTier.legendary),
];

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
