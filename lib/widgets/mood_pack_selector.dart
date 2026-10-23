import 'dart:io' show Platform;
import '../utils/safe_launch.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/level.dart';
import '../models/mood_pack.dart';
import '../models/own_mood_pack.dart';
import '../models/user_data.dart';
import '../services/catalog_service.dart';
import '../services/coin_store.dart';
import '../services/level_service.dart';
import '../dict_strings.dart';
import '../services/locale_service.dart';
import '../services/mood_pack_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_scope.dart';
import 'mood_image.dart';
import '../models/catalog_price.dart';

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
///
/// Первой в ряду стоит таблетка «Свои» ([own]), если она есть: набор пары
/// отдельный, а не раздел внутри выбранного набора.
class MoodPackSelector extends StatelessWidget {
  final Color primary;

  /// Вызывается после смены пака (родитель обновляет сетку настроений). Зовётся
  /// и при нажатии на уже выбранный набор: так родитель снимает просмотр
  /// закрытого или «Своих».
  final ValueChanged<MoodPack>? onChanged;

  /// Таблетка «Свои» перед наборами. null — её нет: одиночка без пары или
  /// iPhone, где Плюса нет вовсе.
  final OwnPackChip? own;

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
    this.own,
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
  bool isOpen(MoodPack pack) =>
      moodPackOpenFor(pack, user: user, pairOwned: pairOwned);

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
        // Платный набор показывается там, где его можно купить: на iPhone это
        // биллинг Apple (товар заведён 19.08.2026), в сборке Play — биллинг
        // Google, в остальных — счёт на сайте. Купленный (в том числе
        // партнёром с другой платформы) виден везде: отбирать оплаченное
        // нельзя.
        final packs = CatalogService.instance.allPacks
            .where((p) => moodPackVisible(
                  isIOS: Platform.isIOS,
                  isMoney: p.unlock.isMoney,
                  isOpen: isOpen(p),
                  buysInStore: kCatalogBuysInStore,
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
          if (pack.id != selectedId) {
            HapticFeedback.selectionClick();
            MoodPackService.instance.setSelectedPack(pack.id);
          }
          onChanged?.call(pack);
        }

        final own = this.own;
        final ownSelected = shownId == kOwnMoodPackId;
        Widget ownChip({required bool stretched}) => OwnMoodPackChip(
              key: const Key('mood-pack-own'),
              chip: own!,
              selected: ownSelected,
              stretched: stretched,
            );
        Widget packChip(MoodPack p, {required bool stretched}) => MoodPackChip(
              key: Key('mood-pack-${p.id}'),
              pack: p,
              selected: p.id == shownId,
              locked: !isOpen(p),
              primary: primary,
              stretched: stretched,
              onTap: () => select(p),
            );
        final count = packs.length + (own == null ? 0 : 1);

        if (count <= _stretchUpTo) {
          final chips = [
            if (own != null) ownChip(stretched: true),
            for (final p in packs) packChip(p, stretched: true),
          ];
          return SizedBox(
            height: _height,
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: chips[i]),
                ],
              ],
            ),
          );
        }

        return SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            // «Свои» отделены от наборов чуть шире: это набор пары, а не пак.
            separatorBuilder: (_, i) => SizedBox(width: own != null && i == 0 ? 12 : 8),
            itemBuilder: (context, i) {
              if (own != null && i == 0) return ownChip(stretched: false);
              return packChip(packs[i - (own == null ? 0 : 1)], stretched: false);
            },
          ),
        );
      },
    );
  }
}

/// Открыт ли пак этому человеку — правило [MoodPackSelector.isOpen], оно же
/// у листа наклеек: наклейки берутся из тех же наборов.
bool moodPackOpenFor(
  MoodPack pack, {
  UserData? user,
  Set<String> pairOwned = const {},
}) {
  final key = Unlock.featureKey(kMoodPackFeatureKind, pack.id);
  final byPair = pairOwned.contains(key) ||
      CatalogService.instance.pairOwned.contains(key);
  if (user == null) return byPair || !pack.unlock.isForSale;
  return user.unlocksCatalogItem(
    pack.unlock,
    kMoodPackFeatureKind,
    pack.id,
    LevelService.instance.level,
    boughtByPair: byPair,
  );
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

  // Сообщения ниже написаны парой «русский / английский»; китайский и
  // украинский берут перевод английской половины.
  void say(String text) => messenger.showSnackBar(
        SnackBar(
          content: Text(ru ? text : trEnglish(text)),
          behavior: SnackBarBehavior.floating,
        ),
      );

  if (!pack.unlock.isForSale) {
    say(ru ? 'Этот набор пока не продаётся' : 'This pack is not for sale yet');
    return;
  }

  // Пак за деньги: монеты тут ни при чём, оплату ведёт lava.top. Счёт заводит
  // сервер на почту аккаунта — по витринной ссылке уведомление об оплате не
  // приходит вовсе, и набор пришлось бы выдавать руками.
  if (pack.unlock.isMoney) {
    final featureKey = Unlock.featureKey(kMoodPackFeatureKind, pack.id);
    // На iPhone покупка идёт только через StoreKit: внешняя оплата — 3.1.1.
    // Товара там нет (сборка старее самого товара) — молчим, а не ведём на
    // сайт.
    if (Platform.isIOS && !kCatalogBuysInStore) return;

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
    final ok = await safeLaunchUrl(Uri.parse(url),
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

/// Что показать таблеткой «Свои».
class OwnPackChip {
  /// Картинка первого своего настроения; пусто — набор пуст, в кружке «+».
  final String preview;

  /// Подложка под картинку-эмодзи: она прозрачная и без фона висела бы в
  /// воздухе. null — картинка заполняет кружок сама.
  final Color? previewTint;

  /// Без Плюса таблетка носит замок.
  final bool locked;
  final VoidCallback onTap;

  const OwnPackChip({
    required this.preview,
    required this.locked,
    required this.onTap,
    this.previewTint,
  });
}

/// Цвета таблетки: выбранная заливается цветом темы. primaryContainer у
/// рисованных тем совпадает с фоном листа (у тёмной «Кофе» #2A1F18 против
/// #2A1E19), и выбранный набор от невыбранного не отличался.
(Color, Color) _chipColors(AppTheme t, bool selected) => selected
    ? (t.fillColor, AppThemes.onColor(t.fillColor, mode: t.brightness))
    : (t.surfaceMuted, t.textSecondary);

/// Таблетка «Свои». Её же берёт лист наклеек.
class OwnMoodPackChip extends StatelessWidget {
  final OwnPackChip chip;
  final bool selected;
  final bool stretched;

  const OwnMoodPackChip({super.key, required this.chip, required this.selected, required this.stretched});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final (bg, fg) = _chipColors(t, selected);
    final onFill = AppThemes.onColor(t.fillColor, mode: t.brightness);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          chip.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: MoodPackSelector._height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(MoodPackSelector._height / 2),
          ),
          child: Row(
            mainAxisSize: stretched ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Пустой набор: «+» на заливке темы, а на выбранной таблетке,
                  // которая сама цвета темы, — на её надписи.
                  color: chip.preview.isEmpty
                      ? (selected ? fg : t.fillColor)
                      : (chip.previewTint ?? Colors.white),
                ),
                clipBehavior: Clip.antiAlias,
                child: chip.preview.isEmpty
                    ? Icon(Icons.add_rounded, size: 18, color: selected ? bg : onFill)
                    : MoodImage(chip.preview, fit: BoxFit.cover, width: 24, height: 24),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  LocaleService.current.customMoodBand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (chip.locked) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_rounded, size: 13, color: fg),
              ] else if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_rounded, size: 15, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Таблетка набора: превью, название, галочка у выбранного, замок с ценой у
/// закрытого. Её же берёт лист наклеек.
class MoodPackChip extends StatelessWidget {
  final MoodPack pack;
  final bool selected;

  /// Пак виден, но закрыт: замок вместо галочки и цена вместо выбора.
  final bool locked;
  final Color primary;

  /// Таблетка занимает свою долю строки (текст по центру) или обжимается
  /// по содержимому в прокручиваемом ряду.
  final bool stretched;
  final VoidCallback onTap;

  const MoodPackChip({
    super.key,
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
    final gradient = pack.tileGradient;
    final (bg, fg) = _chipColors(t, selected);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: MoodPackSelector._height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
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
                  // Цену называет магазин, каталог — запасной ответ, пока
                  // товар не подгрузился (см. catalogPriceLabel).
                  catalogPriceLabel(
                    storePrice: kCatalogBuysInStore
                        ? sharedCoinStore.priceLabel(catalogProductId(
                            Unlock.featureKey(kMoodPackFeatureKind, pack.id)))
                        : null,
                    catalogPrice: pack.unlock.priceLabel,
                  ),
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
