/// Копилка пары: капли от роликов обоих, десять — каждому по открытию
/// сундука без рекламы (`pocketbase/pb_hooks/pair_jar.js`).
///
/// Сервер отдаёт её в `/api/chest/state` (поле `jar`) и в ответе награды за
/// ролик `/api/coins/ad-reward` — там же `added` и `filled`.
class PairJar {
  const PairJar({
    this.size = 10,
    this.drops = const [],
    this.bonus = 0,
    this.capped = false,
    this.added = false,
    this.filled = false,
  });

  final int size;

  /// Капли по порядку: `true` — моя, `false` — партнёра.
  final List<bool> drops;

  /// Сколько открытий сундука из копилки ждёт меня.
  final int bonus;

  /// На сегодня копилок набрано две, капли не падают до завтра.
  final bool capped;

  /// Капля упала этим роликом.
  final bool added;

  /// Этим роликом копилка наполнилась: обоим по открытию, счёт с нуля.
  final bool filled;

  int get count => drops.length;
  int get mine => drops.where((d) => d).length;
  int get partner => count - mine;

  static PairJar? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final size = (raw['size'] as num?)?.toInt() ?? 10;
    final drops = <bool>[
      if (raw['drops'] is List)
        for (final d in raw['drops'] as List) d == 1,
    ];
    return PairJar(
      size: size < 1 ? 10 : size,
      drops: drops.length > size ? drops.sublist(0, size) : drops,
      bonus: ((raw['bonus'] as num?)?.toInt() ?? 0).clamp(0, 99),
      capped: raw['capped'] == true,
      added: raw['added'] == true,
      filled: raw['filled'] == true,
    );
  }

  PairJar withBonus(int value) => PairJar(size: size, drops: drops, bonus: value < 0 ? 0 : value, capped: capped);
}
