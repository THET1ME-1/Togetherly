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

    test('кнопки ряда прячутся и переживают сохранение', () {
      final l = const HomeLayout()
          .withAction(HomeAction.wallet, shown: false)
          .withAction(HomeAction.draw, shown: false);
      expect(l.showsAction(HomeAction.wallet), isFalse);
      expect(l.showsAction(HomeAction.mood), isTrue);
      expect(l.isDefault, isFalse);
      final back = HomeLayout.fromJson(l.toJson());
      expect(back.hiddenActions, {HomeAction.wallet, HomeAction.draw});
      expect(l.effective(plus: false).hiddenActions, isEmpty);
      expect(l.withAction(HomeAction.wallet, shown: true)
          .withAction(HomeAction.draw, shown: true).isDefault, isTrue);
    });

    test('порядок вкладок: перестановка, панель и сохранение', () {
      // Профиль в начало (to = 0), «Смотрим» спрятана.
      final l = const HomeLayout()
          .tabMoved(4, 0)
          .withTab(HomeTab.watch, shown: false);
      expect(l.tabOrder.first, HomeTab.profile);
      // Панель получает номера вкладок без спрятанной.
      expect(l.navOrder, [3, 0, 1, 2]);
      expect(const HomeLayout().navOrder, [0, 1, 4, 2, 3]);
      final back = HomeLayout.fromJson(l.toJson());
      expect(back.tabOrder, l.tabOrder);
      expect(back.hiddenTabs, {HomeTab.watch});
      // Главную, «Связь» и профиль не спрятать, даже подсунув в сохранённое.
      expect(const HomeLayout().withTab(HomeTab.home, shown: false).isDefault,
          isTrue);
      expect(
          HomeLayout.fromJson({'hiddenTabs': ['profile', 'widgets']})
              .hiddenTabs,
          {HomeTab.widgets});
      // В сохранённом не было вкладки — она встала на своё место.
      expect(
          HomeLayout.fromJson({'tabOrder': ['profile', 'home', 'connect']})
              .tabOrder,
          [HomeTab.profile, HomeTab.home, HomeTab.widgets, HomeTab.watch,
            HomeTab.connect]);
      expect(const HomeLayout().tabMoved(1, 4).tabOrder,
          [HomeTab.home, HomeTab.watch, HomeTab.connect, HomeTab.widgets,
            HomeTab.profile]);
    });

    test('сохранённое без порядка не падает', () {
      // Старая запись или чужое поле: порядка нет, блоки встают как обычно.
      final l = HomeLayout.fromJson({'hiddenTabs': ['watch']});
      expect(l.order, HomeLayout.defaultOrder);
      expect(l.hiddenTabs, {HomeTab.watch});
      expect(l.hiddenActions, isEmpty);
    });

    test('перетаскивание на главной не трогает спрятанных', () {
      // На экране: сундук, маскоты, задания, лента (карта спрятана,
      // желания выключены с сервера).
      final l = const HomeLayout().withBlock(HomeBlock.map, shown: false);
      final shown = [
        HomeBlock.chest, HomeBlock.mascot, HomeBlock.tasks, HomeBlock.lane,
      ];
      // Ленту наверх.
      final up = l.dragged(shown, 3, 0);
      expect(up.order.first, HomeBlock.lane);
      expect(up.hiddenBlocks, {HomeBlock.map});
      // Сундук вниз в самый конец (to = длина, как у onReorder).
      final down = l.dragged(shown, 0, 4);
      expect(down.order.last, HomeBlock.chest);
      // Маскоты за задания: карта осталась между сундуком и заданиями.
      final mid = l.dragged(shown, 1, 3);
      expect(mid.order, [
        HomeBlock.chest, HomeBlock.map, HomeBlock.tasks, HomeBlock.wishes,
        HomeBlock.mascot, HomeBlock.lane,
      ]);
      // Отпустили на месте — ничего не изменилось.
      expect(l.dragged(shown, 2, 2).order, l.order);
      expect(l.dragged(shown, 2, 3).order, l.order);
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
