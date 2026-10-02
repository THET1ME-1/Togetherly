import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/home_layout.dart';
import 'package:love_app/services/frame_gift_service.dart';

void main() {
  group('HomeLayout', () {
    test('без Плюса действует порядок по умолчанию', () {
      final custom = const HomeLayout()
          .withBlock(HomeBlock.map, shown: false)
          .withTab(HomeTab.watch, shown: false)
          .moved(0, 3);
      final eff = custom.effective(plus: false);
      expect(eff.isDefault, isTrue);
      expect(eff.visibleBlocks, HomeLayout.defaultOrder);
      expect(custom.effective(plus: true).showsBlock(HomeBlock.map), isFalse);
      expect(custom.effective(plus: true).showsTab(HomeTab.watch), isFalse);
    });

    test('сдвиг шагает через спрятанных соседей', () {
      // сундук, маскоты, [карта спрятана], задания…
      final l = const HomeLayout().withBlock(HomeBlock.map, shown: false);
      final up = l.shifted(HomeBlock.tasks, -1);
      expect(up.visibleBlocks.take(3).toList(),
          [HomeBlock.chest, HomeBlock.tasks, HomeBlock.mascot]);
      // Крайние не двигаются.
      expect(l.shifted(HomeBlock.chest, -1).order, l.order);
      expect(l.shifted(HomeBlock.lane, 1).order, l.order);
    });

    test('перестановка как у ReorderableListView', () {
      final l = const HomeLayout().moved(0, 5);
      expect(l.order.last, HomeBlock.chest);
      expect(l.order.length, HomeLayout.defaultOrder.length);
    });

    test('сохранение и разбор туда-обратно', () {
      final l = const HomeLayout()
          .moved(5, 0)
          .withBlock(HomeBlock.wishes, shown: false)
          .withTab(HomeTab.widgets, shown: false);
      final back = HomeLayout.fromJson(l.toJson());
      expect(back.order, l.order);
      expect(back.hiddenBlocks, {HomeBlock.wishes});
      expect(back.hiddenTabs, {HomeTab.widgets});
    });

    test('мусор и забытые блоки в сохранённом не ломают раскладку', () {
      final l = HomeLayout.fromJson({
        'order': ['lane', 'nope', 'chest', 'lane'],
        'hiddenBlocks': ['map', 42],
        'hiddenTabs': ['profile'],
      });
      // Все блоки на месте ровно по разу, известный порядок сохранён.
      expect(l.order.toSet(), HomeBlock.values.toSet());
      expect(l.order.length, HomeBlock.values.length);
      expect(l.order.indexOf(HomeBlock.lane) < l.order.indexOf(HomeBlock.chest),
          isTrue);
      // Пропавший mascot встал сразу за chest, как в порядке по умолчанию.
      expect(l.order.indexOf(HomeBlock.mascot),
          l.order.indexOf(HomeBlock.chest) + 1);
      expect(l.hiddenBlocks, {HomeBlock.map});
      expect(l.hiddenTabs, isEmpty);
      expect(HomeLayout.fromJson('битое').isDefault, isTrue);
    });
  });

  group('рамка в подарке', () {
    test('ключ рамки из gift_key', () {
      expect(FrameGiftService.frameKeyOf('frame_wreath'), 'wreath');
      expect(FrameGiftService.frameKeyOf(FrameGiftService.giftKeyOf('cat')),
          'cat');
      expect(FrameGiftService.frameKeyOf('frame_'), isNull);
      expect(FrameGiftService.frameKeyOf('heart'), isNull);
    });

    test('ответ сервера', () {
      final r = FrameGiftResult.fromJson({
        'ok': true,
        'coins': 15,
        'ownedFeatures': ['frame:frame_cat', 3],
        'frame': '',
      });
      expect(r.ok, isTrue);
      expect(r.coins, 15);
      expect(r.ownedFeatures, ['frame:frame_cat']);
      final no = FrameGiftResult.fromJson({'ok': false, 'error': 'partner_has'});
      expect(no.ok, isFalse);
      expect(no.error, 'partner_has');
      expect(FrameGiftQuote.fromJson({'ok': false}), isNull);
      final q = FrameGiftQuote.fromJson(
          {'ok': true, 'price': 40, 'partnerHas': true, 'adLeft': 2, 'coins': 9})!;
      expect(q.price, 40);
      expect(q.partnerHas, isTrue);
      expect(q.adLeft, 2);
    });
  });
}
