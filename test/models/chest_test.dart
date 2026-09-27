import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/services/chest_service.dart';

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

  test('запасная таблица совпадает с серверной', () {
    final server = serverOdds(src);
    final client = fallbackChestOdds(withPlus: true);
    expect(client.map((p) => [p.key, p.kind.name, '${p.amount}', '${p.weight}', p.tier.name]).toList(), server);
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
    expect(pct('coins5'), '35%');
    expect(pct('rose'), '2,5%');
    expect(pct('plus'), '5%');
    expect(chestPercent(odds.firstWhere((p) => p.key == 'locket'), odds, decimal: '.'), '1.5%');
  });

  test('ярусы идут от обычных к легендарным, пустые пропадают', () {
    final tiers = chestTiers(fallbackChestOdds(withPlus: false));
    expect(tiers.map((t) => t.$1).toList(), ChestTier.values);
    expect(tiers.last.$2.map((p) => p.key), ['locket', 'rings']);
    expect(chestTiers(fallbackChestOdds(withPlus: true).where((p) => p.tier == ChestTier.rare).toList()).length, 1);
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
}
