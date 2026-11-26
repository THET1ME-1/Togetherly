import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree.dart';

void main() {
  group('сезон ёлки', () {
    test('ёлка на главной только в декабре', () {
      expect(xtHomeTileVisible(DateTime(2026, 11, 30, 23, 59)), isFalse);
      expect(xtHomeTileVisible(DateTime(2026, 12, 1)), isTrue);
      expect(xtHomeTileVisible(DateTime(2026, 12, 31, 23, 59)), isTrue);
      expect(xtHomeTileVisible(DateTime(2027, 1, 1)), isFalse);
    });

    test('последняя ёлка: в декабре своя, в январе и летом прошлогодняя', () {
      expect(xtLatestSeason(DateTime(2026, 12, 5)), 2026);
      expect(xtLatestSeason(DateTime(2027, 1, 31)), 2026);
      expect(xtLatestSeason(DateTime(2027, 7, 1)), 2026);
      expect(xtActiveSeason(DateTime(2027, 1, 1)), isNull);
      expect(xtActiveSeason(DateTime(2026, 12, 1)), 2026);
    });

    test('подпись сезона', () {
      expect(xtSeasonLabel(2026), '2026–27');
      expect(xtSeasonLabel(2099), '2099–00');
    });
  });

  group('коробка', () {
    const me = 'me', him = 'him';
    final toys = [
      const TreeToy(id: '1', toy: 'red', x: 40, y: 40, author: me),
      const TreeToy(id: '2', toy: 'red', x: 50, y: 50, author: him),
      const TreeToy(id: '3', toy: 'gold', x: 60, y: 60, author: me),
    ];

    test('мои повешенные убавляют счёт, чужие — нет', () {
      final free = xtFreeToys({'red': 2, 'gold': 1, 'tu': 1}, toys, me);
      expect(free, {'red': 1, 'gold': 0, 'tu': 1});
    });

    test('служебные и пустые ключи сервера не попадают в коробку', () {
      expect(xtOwned({'_st': 1, 'red': 2, 'blue': 0, 'x': 'y'}), {'red': 2});
      expect(xtOwned(null), isEmpty);
    });

    test('«Под снегом» — только если стиль выпал из сундука', () {
      expect(xtStyleOwned('fir', const {}), isTrue);
      expect(xtStyleOwned('snowy', const {}), isFalse);
      expect(xtStyleOwned('snowy', {'style_snowy': 1}), isTrue);
    });
  });

  group('ответ сервера', () {
    test('состояние разбирается целиком', () {
      final s = TreeState.fromJson({
        'tree': {'kind': 'snowy', 'star': false, 'garland': true},
        'toys': [
          {'id': 'a1', 'toy': 'red', 'x': 33.3, 'y': 44.4, 'author': 'u1', 'created': '2026-12-01 10:52:14.541Z'},
          {'id': '', 'toy': 'red'},
          'мусор',
        ],
        'owned': {'_st': 1, 'red': 2},
        'seasons': [2026, 2025],
      });
      expect(s.tree, const PairTree(kind: 'snowy', star: false, garland: true));
      expect(s.toys.single.x, 33.3);
      expect(s.toys.single.created, DateTime.utc(2026, 12, 1, 10, 52, 14, 541));
      expect(s.owned, {'red': 2});
      expect(s.seasons, [2026, 2025]);
    });

    test('неизвестный стиль читается как ель', () {
      expect(PairTree.fromJson({'kind': 'pine'}).kind, 'fir');
    });

    test('игрушка каталога', () {
      final t = XtToy.fromCatalog({
        'price': 60,
        'sort': 105,
        'data': {
          'key': 'tu', 'cat': 'tu', 'live': true, 'src': 'coins', 'pick': 'xt_pick_tu', 'tree': 'xt3toy_tu',
          'name': {'ru': 'Ту', 'en': 'Tu', 'zh': '图图'},
        },
      })!;
      expect(t.forSale, isTrue);
      expect(t.live, isTrue);
      expect(t.name('zh'), '图图');
      expect(t.name('de'), 'Tu');
      final chest = XtToy.fromCatalog({'price': 0, 'data': {'key': 'tupair', 'src': 'chest'}})!;
      expect(chest.forSale, isFalse);
    });
  });
}
