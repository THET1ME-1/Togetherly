import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/services/chest_service.dart';

import '../helpers/badge_catalog.dart';

/// Строки таблицы `ODDS` из хука: `[ключ, вид, монет, вес, ярус]`. Таблица
/// продублирована в обоих роутах — сверяются обе.
List<List<String>> serverOdds(String src) {
  final blocks = RegExp(r'const ODDS = \[(.*?)\];', dotAll: true).allMatches(src).toList();
  expect(blocks.length, 2, reason: 'в chest.pb.js две копии ODDS — в state и в open');
  final tables = [
    for (final b in blocks)
      [
        for (final r in RegExp(r'\["(\w+)", "(\w+)", (\d+), (\d+), "(\w+)"\]').allMatches(b.group(1)!))
          [r.group(1)!, r.group(2)!, r.group(3)!, r.group(4)!, r.group(5)!],
      ],
  ];
  expect(tables[0], tables[1], reason: 'копии ODDS в state и open разошлись');
  return tables[0];
}

void main() {
  final src = File('pocketbase/pb_hooks/chest.pb.js').readAsStringSync();

  /// Подарки сундука из хука: `["ключ", "ярус"]`, обе копии одинаковы.
  List<List<String>> serverGifts() {
    final blocks = RegExp(r'const GIFTS = \[(.*?)\];', dotAll: true).allMatches(src).toList();
    expect(blocks.length, 2, reason: 'GIFTS продублирована в state и open');
    final tables = [
      for (final b in blocks)
        [
          for (final r in RegExp(r'\["(\w+)", "(\w+)"\]').allMatches(b.group(1)!)) [r.group(1)!, r.group(2)!],
        ],
    ];
    expect(tables[0], tables[1], reason: 'копии GIFTS разошлись');
    return tables[0];
  }

  test('монеты и Плюс в запасной таблице — те же строки, что на сервере', () {
    final client = {for (final p in fallbackChestOdds(withPlus: true)) p.key: p};
    for (final r in serverOdds(src)) {
      if (r[0] == 'coins5') continue; // «5 монет» забирает всё, что не разложено
      final p = client[r[0]];
      expect(p, isNotNull, reason: '${r[0]} нет в запасной таблице');
      final kind = p!.kind == ChestPrizeKind.plusTrial ? 'plus_trial' : p.kind.name;
      expect([kind, '${p.amount}', '${p.weight}', p.tier.name], [r[1], r[2], r[3], r[4]]);
    }
  });

  test('подарки сундука: те же ключи и ярусы, что на сервере', () {
    final client = {
      for (final p in fallbackChestOdds(withPlus: true).where((p) => p.kind == ChestPrizeKind.gift)) p.key: p.tier.name,
    };
    expect(client, {for (final g in serverGifts()) g[0]: g[1]});
  });

  test('пулы редкости совпадают с сервером в обоих роутах', () {
    final blocks = RegExp(r'const TIER_POOL = \{([^}]*)\}').allMatches(src).toList();
    expect(blocks.length, 2, reason: 'TIER_POOL продублирована в state и open');
    for (final b in blocks) {
      final m = {
        for (final r in RegExp(r'(\w+): (\d+)').allMatches(b.group(1)!)) r.group(1)!: int.parse(r.group(2)!),
      };
      expect(m, kChestTierPools);
    }
  });

  test('одинаковая редкость — одинаковый шанс, и редкое реже обычного', () {
    final odds = fallbackChestOdds(withPlus: true).where((p) => p.kind == ChestPrizeKind.gift);
    final byTier = <ChestTier, Set<int>>{};
    for (final p in odds) {
      (byTier[p.tier] ??= {}).add(p.weight);
    }
    for (final w in byTier.values) {
      expect(w.length, 1, reason: 'внутри яруса веса разные: $w');
    }
    expect(byTier[ChestTier.common]!.first, greaterThan(byTier[ChestTier.rare]!.first));
    expect(byTier[ChestTier.rare]!.first, greaterThan(byTier[ChestTier.legendary]!.first));
  });

  test('гарантия редкого приза совпадает с сервером', () {
    final pity = RegExp(r'const PITY = (\d+);').allMatches(src).map((m) => int.parse(m.group(1)!)).toSet();
    expect(pity, {kChestPity});
    final st = ChestState.fromJson({
      'ok': true,
      'left': 3,
      'untilRare': 4,
      'odds': [
        {'key': 'coins5', 'kind': 'coins', 'amount': 5, 'weight': 1000, 'tier': 'common'},
      ],
    });
    expect(st?.untilRare, 4);
  });

  test('неделя Плюса: свой вид приза и срок в ответе открытия', () {
    final res = parseChestOpen({
      'ok': true,
      'prize': {'key': 'plus7', 'kind': 'plus_trial', 'amount': 7},
      'plusTrialUntil': 1790000000000,
      'untilRare': 10,
    });
    expect(res.prize?.kind, ChestPrizeKind.plusTrial);
    expect(res.plusTrialUntil, 1790000000000);
    expect(res.untilRare, 10);
    // В списке шансов неделя стоит рядом с Плюсом навсегда, в «Главном призе».
    final top = chestSections(fallbackChestOdds(withPlus: true)).first;
    expect(top.$1, isNull);
    expect(top.$2.map((p) => p.key), ['plus', 'plus7']);
  });

  test('значок из ответа сервера находится по id записи каталога', () {
    installTestBadges();
    final p = ChestPrize.fromJson({'key': 'badge_lucky', 'kind': 'badge', 'amount': 0, 'weight': 8, 'tier': 'rare'});
    expect(p?.kind, ChestPrizeKind.badge);
    expect(p?.badge?.id, 'Lucky');
    final res = parseChestOpen({
      'ok': true,
      'prize': {'key': 'badge_lucky', 'kind': 'badge', 'amount': 0},
      'ownedIcons': ['Lucky'],
    });
    expect(res.ownedIcons, ['Lucky']);
  });

  test('рамка из ответа сервера: ключ каталога и ключ рамки', () {
    final p = ChestPrize.fromJson({'key': 'frame_cat', 'kind': 'frame', 'amount': 0, 'weight': 5, 'tier': 'legendary'});
    expect(p?.kind, ChestPrizeKind.frame);
    expect(p?.frameKey, 'cat');
    final res = parseChestOpen({
      'ok': true,
      'prize': {'key': 'frame_cat', 'kind': 'frame', 'amount': 0},
      'left': 2,
      'ownedFeatures': ['frame:frame_cat'],
    });
    expect(res.ok, isTrue);
    expect(res.ownedFeatures, ['frame:frame_cat']);
  });

  test('веса дают ровно сто процентов — с Плюсом и без', () {
    for (final withPlus in [true, false]) {
      expect(fallbackChestOdds(withPlus: withPlus).fold<int>(0, (t, p) => t + p.weight), 1000);
    }
  });

  test('подарки сундука есть в каталоге, но не в витрине и не в прайсе дарения', () {
    final gifts = fallbackChestOdds(
      withPlus: true,
    ).where((p) => p.kind == ChestPrizeKind.gift).map((p) => p.key).toSet();
    expect(gifts, GiftCatalog.chest.map((g) => g.key).toSet());
    final shop = GiftCatalog.all.map((g) => g.key).toSet();
    expect(gifts.intersection(shop), isEmpty);
    final prices = File('pocketbase/pb_hooks/gifts.pb.js').readAsStringSync();
    for (final k in gifts) {
      expect(RegExp('\\b$k:').hasMatch(prices), isFalse, reason: '$k продаётся через gifts/send');
    }
  });

  test('проценты: целые без запятой, половинки с запятой', () {
    final odds = fallbackChestOdds(withPlus: true);
    String pct(String key) => chestPercent(odds.firstWhere((p) => p.key == key), odds);
    expect(pct('coins10'), '18%');
    expect(pct('rose'), '0,9%');
    expect(pct('plus'), '0,1%');
    expect(pct('plus7'), '1%');
    expect(chestPercent(odds.firstWhere((p) => p.key == 'locket'), odds, decimal: '.'), '0.4%');
  });

  test('ярусы идут от обычных к легендарным, пустые пропадают', () {
    final tiers = chestTiers(fallbackChestOdds(withPlus: false));
    expect(tiers.map((t) => t.$1).toList(), ChestTier.values);
    expect(tiers.last.$2.map((p) => p.key), ['locket', 'rings']);
    expect(chestTiers(fallbackChestOdds(withPlus: true).where((p) => p.tier == ChestTier.rare).toList()).length, 1);
  });

  test('Togetherly+ стоит первым отдельным разделом и не повторяется в ярусах', () {
    final withPlus = chestSections(fallbackChestOdds(withPlus: true));
    expect(withPlus.first.$1, isNull);
    expect(withPlus.first.$2.map((p) => p.key), ['plus', 'plus7']);
    expect(withPlus.skip(1).expand((s) => s.$2).any((p) => p.key.startsWith('plus')), isFalse);
    expect(withPlus.last.$2.map((p) => p.key), ['locket', 'rings']);
    // Плюса в таблице нет (iPhone, уже куплен) — нет и главного раздела.
    expect(chestSections(fallbackChestOdds(withPlus: false)).first.$1, ChestTier.common);
  });

  test('состояние: незнакомый подарок пропускается, остаток не выходит за рамки', () {
    final st = ChestState.fromJson({
      'ok': true,
      'perDay': 3,
      'left': 7,
      'odds': [
        {'key': 'coins5', 'kind': 'coins', 'amount': 5, 'weight': 400, 'tier': 'common'},
        {'key': 'unicorn', 'kind': 'gift', 'amount': 0, 'weight': 10, 'tier': 'rare'},
        {'key': 'rings', 'kind': 'gift', 'amount': 0, 'weight': 10, 'tier': 'legendary'},
      ],
    })!;
    expect(st.left, 3);
    expect(st.odds.map((p) => p.key), ['coins5', 'rings']);
    expect(ChestState.fromJson({'ok': false}), isNull);
  });

  // Приз разыгрывается, как только ролик засчитан, а анимация идёт на экране
  // сундука. Ушёл с него (нажал уведомление посреди ролика) — приз твой, но
  // ты его не видел, и выглядит это как «попытка сгорела» (письмо 29.09.2026).
  // Поэтому состояние несёт призы за сегодня, экран их перечисляет.
  test('состояние: призы за сегодня по порядку, у старого сервера — пусто', () {
    final st = ChestState.fromJson({
      'ok': true,
      'perDay': 3,
      'left': 1,
      'odds': [
        {'key': 'coins5', 'kind': 'coins', 'amount': 5, 'weight': 1000, 'tier': 'common'},
      ],
      'today': [
        {'key': 'rings', 'kind': 'gift', 'amount': 0},
        {'key': 'unicorn', 'kind': 'gift', 'amount': 0},
        {'key': 'coins5', 'kind': 'coins', 'amount': 5},
      ],
    })!;
    expect(st.today.map((p) => p.key), ['rings', 'coins5']);
    expect(st.today.last.amount, 5);
    final old = ChestState.fromJson({
      'ok': true,
      'odds': [
        {'key': 'coins5', 'kind': 'coins', 'amount': 5, 'weight': 1000, 'tier': 'common'},
      ],
    })!;
    expect(old.today, isEmpty);
  });

  test('хук отдаёт призы за сегодня в состоянии сундука', () {
    final state = RegExp(r'routerAdd\("GET", "/api/chest/state".*?\n\}, \$apis', dotAll: true).firstMatch(src)!.group(0)!;
    expect(state, contains('today: today'), reason: 'state обязан отдавать список призов за сегодня');
    expect(state, contains('"b" + day'), reason: 'открытия из копилки пары тоже призы этого дня');
  });

  test('ответ открытия: приз, лимит и молчание сервера', () {
    final ok = parseChestOpen({
      'ok': true,
      'prize': {'key': 'rings', 'kind': 'gift', 'amount': 0},
      'left': 1,
      'coins': 40,
      'plus': false,
    });
    expect(ok.ok, isTrue);
    expect(ok.prize!.gift!.key, 'rings');
    expect(ok.left, 1);
    final limit = parseChestOpen({'ok': false, 'error': 'chest_limit', 'left': 0});
    expect(limit.error, 'chest_limit');
    expect(parseChestOpen(null).error, 'network');
  });

  test('дорожка приза: кадров столько же, сколько в открытии, и приз не выходит за картинку', () {
    // chest_open запечён на 3,8 с по 60 мс.
    expect(kChestPrizeTrack.length, (3800 / kChestFrameMs).round());
    for (final f in kChestPrizeTrack.whereType<List<double>>()) {
      expect(f[0] >= 0 && f[1] >= 0 && f[0] + f[2] <= 1 && f[1] + f[2] <= 1, isTrue);
    }
    expect(kChestPrizeTrack[kChestWonFrame], isNotNull);
  });

  test('запас в ленте: повторы в одну карточку, дарится самый старый', () {
    final groups = groupChestStash(const [
      ChestStashItem(openId: 'old', giftKey: 'throne'),
      ChestStashItem(openId: 'r1', giftKey: 'rings'),
      ChestStashItem(openId: 'new', giftKey: 'throne'),
    ]);
    expect(groups.map((g) => g.$1), ['throne', 'rings']);
    expect(groups.first.$2, ['old', 'new']);
  });

  test('в хуке есть роуты выбора и подарок не ложится на полку при выпадении', () {
    expect(src.contains('routerAdd("POST", "/api/chest/keep"'), isTrue);
    expect(src.contains('routerAdd("POST", "/api/chest/give"'), isTrue);
    final open = src.substring(src.indexOf('"/api/chest/open"'), src.indexOf('"/api/chest/keep"'));
    expect(open.contains('findCollectionByNameOrId("gifts")'), isFalse, reason: 'open не должен создавать подарок');
    expect(open.contains('"stash"'), isTrue);
  });
}
