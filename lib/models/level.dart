import 'package:flutter/material.dart';
import '../dict_strings.dart';

/// Чистая модель уровней/рангов ПАРЫ. Level и Rank выводятся из общего XP и
/// нигде не хранятся — кривую/ранги/цвета можно менять без миграции данных.
///
/// XP — один групповой счётчик (растёт как memoriesCount, дуал-райт). Здесь
/// только математика и справочники; накопление XP — в LevelService.

/// Шаг кривой: XP, нужный чтобы из уровня L шагнуть в L+1, = kXpStep·L.
/// Накопительно до уровня L: kXpStep·L·(L−1)/2.
const int kXpStep = 100;

/// Накопленный XP, нужный чтобы ДОСТИЧЬ [level] (level 1 = 0).
int xpForLevel(int level) {
  if (level <= 1) return 0;
  return kXpStep * level * (level - 1) ~/ 2;
}

/// Текущий уровень по накопленному [xp].
int levelForXp(int xp) {
  if (xp <= 0) return 1;
  var level = 1;
  while (xpForLevel(level + 1) <= xp) {
    level++;
  }
  return level;
}

/// Снимок прогресса для UI (полоска опыта, номер уровня, ранг).
class LevelProgress {
  final int xp;
  final int level;

  /// XP, набранный ВНУТРИ текущего уровня.
  final int xpIntoLevel;

  /// XP на весь шаг текущий→следующий уровень.
  final int xpForNext;

  final Rank rank;

  const LevelProgress({
    required this.xp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNext,
    required this.rank,
  });

  /// 0..1 — заполнение полоски до следующего уровня.
  double get progress =>
      xpForNext <= 0 ? 1.0 : (xpIntoLevel / xpForNext).clamp(0.0, 1.0);

  factory LevelProgress.fromXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    final level = levelForXp(safeXp);
    final base = xpForLevel(level);
    final next = xpForLevel(level + 1);
    return LevelProgress(
      xp: safeXp,
      level: level,
      xpIntoLevel: safeXp - base,
      xpForNext: next - base,
      rank: Rank.forLevel(level),
    );
  }
}

/// Ранг — группа уровней с именем и цветом бордера. Позже добавим [frameAsset]
/// (рисованная рамка) — UI отрисует её вместо цветного кольца.
class Rank {
  final int minLevel;
  final Color color;
  final String? frameAsset;

  const Rank({required this.minLevel, required this.color, this.frameAsset});

  /// Название ранга живёт в словаре: ключ считается из порога уровня, поэтому
  /// новый язык добавляется колонкой в `lib/l10n/dict/ranks.dart`.
  String get name => trKey('rank_$minLevel');

  /// Ранги по возрастанию minLevel. Добавить ранг = одна строка.
  static const List<Rank> all = [
    Rank(minLevel: 1, color: Color(0xFF9CA3AF)),
    Rank(minLevel: 3, color: Color(0xFF22C55E)),
    Rank(minLevel: 6, color: Color(0xFFEC4899)),
    Rank(minLevel: 10, color: Color(0xFFA855F7)),
    Rank(minLevel: 15, color: Color(0xFF3B82F6)),
    Rank(minLevel: 20, color: Color(0xFFF59E0B)),
  ];

  static Rank forLevel(int level) {
    var result = all.first;
    for (final r in all) {
      if (level >= r.minLevel) {
        result = r;
      } else {
        break;
      }
    }
    return result;
  }
}

/// Тип требования для разблокировки элемента каталога.
/// `premium` — покупается за монеты, `money` — за деньги через lava.top
/// (монетами такой элемент не продаётся вовсе: цена в нём валютная).
enum UnlockType { free, level, premium, money }

/// Вид элемента каталога в ключе владения (`owned_features`). Маскот и пак
/// настроений могут носить одинаковый id, поэтому вид обязателен.
const String kMascotFeatureKind = 'mascot';

/// Вид для паков настроений. Ключ владения выглядит как `mood_pack:kawaii`,
/// а серверный роут покупки по нему находит запись каталога и берёт цену
/// оттуда же — клиентскому числу он не верит.
const String kMoodPackFeatureKind = 'mood_pack';

/// УНИВЕРСАЛЬНОЕ требование разблокировки — на любом элементе каталога
/// (маскот, пак настроений, в будущем темы/рамки). Один механизм для всего.
class Unlock {
  final UnlockType type;

  /// Требуемый уровень (для [UnlockType.level]).
  final int requiredLevel;

  /// Цена в монетах для [UnlockType.premium].
  ///
  /// Приходит из каталога, а не живёт списком в коде: в этом весь смысл —
  /// платный персонаж заводится одной записью и продаётся сразу, без новой
  /// сборки. Настоящую цену при покупке всё равно берёт сервер из той же
  /// записи, клиентскому числу тут никто не верит.
  final int price;

  /// Открыт ли элемент владельцам Togetherly+. Решается в каталоге: по
  /// умолчанию Плюс платные элементы НЕ открывает, иначе каждый новый
  /// персонаж доставался бы подписчикам даром без всякого решения.
  final bool plusIncluded;

  /// Валюта цены для [UnlockType.money] (`USD`, `EUR`, `RUB`). У остальных
  /// видов не используется: там цена в монетах.
  final String currency;

  const Unlock.free()
    : type = UnlockType.free,
      requiredLevel = 0,
      price = 0,
      plusIncluded = false,
      currency = '';
  const Unlock.level(this.requiredLevel)
    : type = UnlockType.level,
      price = 0,
      plusIncluded = false,
      currency = '';
  const Unlock.premium({this.price = 0, this.plusIncluded = false})
    : type = UnlockType.premium,
      requiredLevel = 0,
      currency = '';

  /// Покупка за деньги: [price] — сумма в [currency], а не в монетах.
  const Unlock.money({this.price = 0, this.currency = 'USD'})
    : type = UnlockType.money,
      requiredLevel = 0,
      plusIncluded = false;

  /// Разобрать поле `unlock` из манифеста каталога. null/неизвестное → free.
  factory Unlock.fromJson(Map<String, dynamic>? json) {
    switch (json?['type']) {
      case 'level':
        return Unlock.level((json!['level'] as num?)?.toInt() ?? 1);
      case 'premium':
        final raw = json!['price'];
        final price = raw is num ? raw.toInt() : 0;
        return Unlock.premium(
          price: price > 0 ? price : 0,
          plusIncluded: json['plus'] == true,
        );
      case 'money':
        final raw = json!['price'];
        final price = raw is num ? raw.toInt() : 0;
        return Unlock.money(
          price: price > 0 ? price : 0,
          currency: (json['currency'] as String? ?? 'USD').toUpperCase(),
        );
      default:
        return const Unlock.free();
    }
  }

  bool get isFree => type == UnlockType.free;
  bool get isPremium => type == UnlockType.premium;

  /// Продаётся за деньги (lava.top), а не за монеты.
  bool get isMoney => type == UnlockType.money;

  /// Можно ли элемент купить прямо сейчас. Цену в каталог положить забыли —
  /// показывать «купить за 0» нельзя, и отдавать даром тоже.
  bool get isForSale => (isPremium || isMoney) && price > 0;

  /// Цена как её видит человек: «150» для монет, «5 $» для денег.
  String get priceLabel {
    if (!isMoney) return '$price';
    const signs = {'USD': '\$', 'EUR': '€', 'RUB': '₽'};
    final sign = signs[currency] ?? currency;
    return sign == '\$' ? '$price\$' : '$price $sign';
  }

  /// Ключ владения в общем `owned_features`.
  ///
  /// Вид обязателен: маскот и пак настроений могут носить одинаковый id, и
  /// без приставки покупка одного открывала бы другой.
  static String featureKey(String kind, String id) => '$kind:$id';

  /// Открыт ли элемент при текущем [level] пары, факте покупки [owned] и
  /// действующем Togetherly+ ([plus]).
  bool isUnlocked({
    required int level,
    required bool owned,
    bool plus = false,
  }) {
    switch (type) {
      case UnlockType.free:
        return true;
      case UnlockType.level:
        return level >= requiredLevel;
      case UnlockType.premium:
        // Купленное остаётся у человека навсегда — в том числе когда Плюс
        // кончился. Отбирать оплаченное нельзя.
        return owned || (plusIncluded && plus);
      case UnlockType.money:
        // Плюс сюда не входит: за такой элемент платят отдельно, деньгами.
        return owned;
    }
  }
}
