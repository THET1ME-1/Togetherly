import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/level.dart';
import '../models/mood_pack.dart';
import '../models/user_data.dart';
import '../services/catalog_service.dart';
import '../services/coin_store.dart';
import '../services/level_service.dart';
import '../services/locale_service.dart';
import '../services/mood_pack_service.dart';
import '../theme/theme_scope.dart';
import 'mood_image.dart';

/// Выбор пака настроений в пикере: таблетки без обводки.
///
/// Пока паков два-три, они делят строку поровну — так строка читается как один
/// переключатель. Появится четвёртый — уезжают в горизонтальную прокрутку.
/// Ростом таблетки ниже вкладок «Настроение / Самочувствие»: выбор вкладки тут
/// главный, а пак — уточнение.
///
/// Платный пак виден всем, но с замком и ценой: закрытый выбрать нельзя, тап
/// по нему предлагает покупку за монеты. Без [user] замков нет вовсе — так
/// ведут себя старые точки вызова, куда данные о человеке не доходят.
class MoodPackSelector extends StatelessWidget {
  final Color primary;

  /// Вызывается после смены пака (родитель обновляет сетку настроений).
  final ValueChanged<MoodPack>? onChanged;

  /// Тап по ЗАКРЫТОМУ паку. Родитель показывает его эмоции в своей же сетке —
  /// человек видит набор целиком, а кнопка покупки стоит внизу экрана. Отдельного
  /// окна-витрины тут нет намеренно: это тот же экран настроения, только чужой
  /// набор в нём пока нельзя выбрать.
  final ValueChanged<MoodPack>? onPreview;

  /// Чей кошелёк и что уже куплено. Без него пак считается открытым.
  final UserData? user;

  /// Купленное партнёром: ключи `owned_features` группы. Пак общий на пару,
  /// как и маскот, поэтому платит кто-то один.
  final Set<String> pairOwned;

  /// Какой пак сейчас показан в сетке. Обычно это выбранный, но при просмотре
  /// закрытого набора подсвечен именно он.
  final String? shownId;

  const MoodPackSelector({
    super.key,
    required this.primary,
    this.onChanged,
    this.onPreview,
    this.user,
    this.pairOwned = const {},
    this.shownId,
  });

  /// Открыт ли пак этому человеку.
  ///
  /// Ключи пары берём из параметра, а если его не передали — из общего снимка
  /// каталога: пикер открывается с четырёх экранов, и на тех, где параметр
  /// забыли, купленный партнёром пак считался закрытым.
  ///
  /// Без данных пользователя открытыми считаем только бесплатные наборы и то,
  /// что куплено парой. Прежнее «нет user — открыто всё» показывало платный
  /// пак доступным на экране виджетов, где его никто не покупал.
  bool isOpen(MoodPack pack) {
    final key = Unlock.featureKey(kMoodPackFeatureKind, pack.id);
    final byPair = pairOwned.contains(key) ||
        CatalogService.instance.pairOwned.contains(key);
    final u = user;
    if (u == null) return byPair || !pack.unlock.isForSale;
    return u.unlocksCatalogItem(
      pack.unlock,
      kMoodPackFeatureKind,
      pack.id,
      LevelService.instance.level,
      boughtByPair: byPair,
    );
  }

  /// До скольких паков строка делится поровну.
  static const int _stretchUpTo = 3;
  static const double _height = 38;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        [MoodPackService.instance, CatalogService.instance],
      ),
      builder: (context, _) {
        final selectedId = MoodPackService.instance.selectedPackId;
        // Подсвечиваем тот набор, который человек сейчас видит: у закрытого это
        // просмотр, а не выбор, поэтому галочки у него не будет — только замок.
        final shownId = this.shownId ?? selectedId;
        // На iOS платного за деньги не показываем вовсе: вести на оплату мимо
        // биллинга Apple запрещает 3.1.1, за это уже прилетал реджект 1.21.0.
        // Купленный (в том числе партнёром с Android) остаётся видимым —
        // отбирать оплаченное нельзя.
        final packs = CatalogService.instance.allPacks
            .where((p) => moodPackVisible(
                  isIOS: Platform.isIOS,
                  isMoney: p.unlock.isMoney,
                  isOpen: isOpen(p),
                ))
            .toList();
        if (packs.isEmpty) return const SizedBox.shrink();

        void select(MoodPack pack) {
          if (!isOpen(pack)) {
            // Закрытый набор просто показываем в сетке — купить его можно
            // кнопкой внизу экрана, когда человек посмотрел, что берёт.
            HapticFeedback.selectionClick();
            onPreview?.call(pack);
            return;
          }
          if (pack.id == selectedId) return;
          HapticFeedback.selectionClick();
          MoodPackService.instance.setSelectedPack(pack.id);
          onChanged?.call(pack);
        }

        if (packs.length <= _stretchUpTo) {
          return SizedBox(
            height: _height,
            child: Row(
              children: [
                for (var i = 0; i < packs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PackChip(
                      pack: packs[i],
                      selected: packs[i].id == shownId,
                      locked: !isOpen(packs[i]),
                      primary: primary,
                      stretched: true,
                      onTap: () => select(packs[i]),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _PackChip(
              pack: packs[i],
              selected: packs[i].id == shownId,
              locked: !isOpen(packs[i]),
              primary: primary,
              stretched: false,
              onTap: () => select(packs[i]),
            ),
          ),
        );
      },
    );
  }
}

/// Купить пак: за деньги или за монеты, смотря что стоит в каталоге.
///
/// Зовётся кнопкой внизу экрана настроения, когда человек смотрит закрытый
/// набор. Цену показываем из каталога, а списывает её сервер по своей же
/// записи: клиентскому числу он не верит, подменить его в запросе нельзя.
///
/// Платный за деньги набор идёт разными путями, смотря чья это сборка. В
/// Google Play — только биллинг Google: увести оттуда на сайт значит потерять
/// приложение. В остальных сборках (sideload, RuStore) товаров Play нет, и
/// оплату ведёт lava.top — счёт заводит сервер на почту аккаунта, потому что
/// по витринной ссылке уведомление об оплате не приходит вовсе и набор
/// пришлось бы выдавать руками.
///
/// [onBought] срабатывает после покупки за монеты и после покупки в магазине;
/// оплата на сайте уходит в браузер и возвращается уведомлением сервера.
Future<void> buyMoodPack(
  BuildContext context,
  MoodPack pack, {
  required UserData user,
  VoidCallback? onBought,
}) async {
  final ru = LocaleService.instance.isRussian;
  final price = pack.unlock.price;
  final messenger = ScaffoldMessenger.of(context);

  void say(String text) => messenger.showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  if (!pack.unlock.isForSale) {
    say(ru ? 'Этот набор пока не продаётся' : 'This pack is not for sale yet');
    return;
  }

  // Пак за деньги: монеты тут ни при чём, оплату ведёт lava.top. Счёт заводит
  // сервер на почту аккаунта — по витринной ссылке уведомление об оплате не
  // приходит вовсе, и набор пришлось бы выдавать руками.
  if (pack.unlock.isMoney) {
    // Платный набор на iPhone не показывается вовсе (`moodPackVisible`), но и
    // покупку отсюда не начинаем: биллинга Apple для него нет, а внешняя
    // оплата — 3.1.1.
    if (Platform.isIOS) return;
    final featureKey = Unlock.featureKey(kMoodPackFeatureKind, pack.id);

    if (kCatalogBuysInStore) {
      final store = sharedCoinStore;
      final productId = catalogProductId(featureKey);
      final known = await store.ensureProduct(productId);
      if (!context.mounted) return;
      if (!known) {
        say(ru ? 'Набор пока недоступен к покупке' : 'This pack is not available yet');
        return;
      }
      final res = await store.buy(productId);
      if (!context.mounted) return;
      switch (res.status) {
        case IapStatus.success:
          // Ключ владения положил сервер при сверке чека — перечитываем свой
          // профиль (`refreshCoinsFromServer` тянет и `owned_features`), на нём
          // завязаны все проверки доступа.
          await user.refreshCoinsFromServer();
          if (!context.mounted) return;
          HapticFeedback.selectionClick();
          await MoodPackService.instance.setSelectedPack(pack.id);
          onBought?.call();
        case IapStatus.pending:
          say(ru
              ? 'Оплата обрабатывается — набор откроется сам'
              : 'Payment is processing — the pack will open by itself');
        case IapStatus.cancelled:
          break;
        case IapStatus.error:
          say(ru ? 'Покупка не прошла' : 'Purchase failed');
      }
      return;
    }

    final res = await CatalogService.instance.purchaseUrl(
      featureKey,
      currency: pack.unlock.currency,
    );
    if (!context.mounted) return;
    if (res.already) {
      say(ru ? 'Набор уже открыт' : 'You already own this pack');
      return;
    }
    final url = res.url;
    if (url == null) {
      say(ru ? 'Не удалось открыть оплату' : 'Could not open checkout');
      return;
    }
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      say(ru ? 'Не удалось открыть оплату' : 'Could not open checkout');
    }
    return;
  }

  if (user.coins < price) {
    say(ru
        ? 'Не хватает монет: нужно $price, у вас ${user.coins}'
        : 'Not enough coins: $price needed, you have ${user.coins}');
    return;
  }

  final bought = await user.purchaseCatalogItem(kMoodPackFeatureKind, pack.id);
  if (!context.mounted) return;
  if (!bought) {
    say(ru ? 'Покупка не прошла' : 'Purchase failed');
    return;
  }

  HapticFeedback.selectionClick();
  await MoodPackService.instance.setSelectedPack(pack.id);
  onBought?.call();
}

class _PackChip extends StatelessWidget {
  final MoodPack pack;
  final bool selected;

  /// Пак виден, но закрыт: замок вместо галочки и цена вместо выбора.
  final bool locked;
  final Color primary;

  /// Таблетка занимает свою долю строки (текст по центру) или обжимается
  /// по содержимому в прокручиваемом ряду.
  final bool stretched;
  final VoidCallback onTap;

  const _PackChip({
    required this.pack,
    required this.selected,
    required this.locked,
    required this.primary,
    required this.stretched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = Theme.of(context).colorScheme;
    final gradient = pack.tileGradient;
    final fg = selected ? cs.onPrimaryContainer : t.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: MoodPackSelector._height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : t.surfaceMuted,
          borderRadius: BorderRadius.circular(MoodPackSelector._height / 2),
        ),
        child: Row(
          mainAxisSize: stretched ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Превью пака — первое настроение набора.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient != null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      )
                    : null,
                color: gradient == null ? Colors.white : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: pack.previewImage.isNotEmpty
                  ? MoodImage(pack.previewImage, fit: BoxFit.cover)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                pack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_rounded, size: 13, color: fg),
              if (pack.unlock.isForSale) ...[
                const SizedBox(width: 3),
                Text(
                  // Монеты — голое число рядом со значком монеты, деньги — со
                  // знаком валюты: «150» и «5 $» не должны читаться одинаково.
                  pack.unlock.priceLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ] else if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 15, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
