import 'dart:async';
import 'dart:io';
import '../utils/safe_launch.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/plus_gift.dart';
import '../services/coin_store.dart';
import '../services/locale_service.dart';
import '../services/pb_coins_service.dart';
import '../services/plus_service.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/plus/gift_recipient_sheet.dart';

/// Экран Togetherly+.
///
/// Разовая покупка, не подписка: заплатил один раз — доступ остаётся и
/// переезжает вместе с аккаунтом. Оплата идёт на lava.top, оттуда вебхук
/// приходит в PocketBase и ставит флаг; если почта покупки совпала с почтой
/// аккаунта, всё открывается само, иначе бот выдаёт код.
///
/// Кнопка покупки показывается только в сборках мимо Google Play: там нельзя
/// проводить оплату цифровых товаров чужим биллингом. Уже купленный доступ
/// работает везде — флаг живёт на аккаунте, а не в сборке.
class PlusScreen extends StatefulWidget {
  const PlusScreen({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  final PlusService _plus = PlusService.instance;
  bool _busy = false;

  /// Кому можно подарить доступ, почём и со скидкой ли. Пока сервер не ответил
  /// — карточки подарка нет: пустая заготовка обещала бы то, чего может не
  /// быть (пары нет, подарок выключен, у партнёра всё куплено).
  PlusGiftOffer _gift = PlusGiftOffer.none;

  /// Магазин заводится только в Play-сборке — там покупка идёт через биллинг.
  /// В остальных сборках оплата уходит на lava.top, и магазин не нужен.
  CoinStore? _store;

  ColorScheme get _cs => widget.scheme;
  AppStrings get _s => LocaleService.current;

  @override
  void initState() {
    super.initState();
    _plus.addListener(_onChanged);
    unawaitedRefresh();
    _loadGift();
    if (PlusService.buysInStore) _initStore();
  }

  Future<void> _loadGift() async {
    if (!PlusService.canGift) return;
    final offer = await _plus.giftOffer();
    if (mounted) setState(() => _gift = offer);
    // В Play и App Store цену называет магазин, поэтому товар надо догрузить:
    // в постоянном списке продуктов его нет — он нужен только тем, у кого есть
    // пара.
    if (PlusService.buysInStore && offer.visible) {
      await _store?.ensureProduct(kGiftProductId);
      if (mounted) setState(() {});
    }
  }

  /// Сколько стоит подарок. В магазинных сборках сумму называет магазин —
  /// у него своя цена в каждой стране; в остальных её считает наш сервер по
  /// каталогу lava.top.
  String get _giftPriceLabel {
    if (PlusService.buysInStore) {
      return _store?.priceLabel(kGiftProductId) ?? '';
    }
    return _gift.priceLabel;
  }

  Future<void> _initStore() async {
    // Общий магазин на всё приложение: свой экземпляр отписывался бы от потока
    // покупок в `dispose`, и оплата, случившаяся при закрытом экране, до
    // сервера не доезжала (инцидент 30 июля).
    final store = sharedCoinStore;
    _store = store;
    store.addListener(_onChanged);
    await store.init(
      onGrantCoins: ({
        required String productId,
        required String purchaseToken,
      }) async {
        // Тот же роут, что начисляет монеты: для togetherly_plus он ставит флаг
        // доступа. Возвращаем баланс — по non-null сервис понимает, что сервер
        // покупку принял.
        //
        // У подарка к чеку добавляется связь получателя. Она лежит на диске, а
        // не в поле экрана: магазин подтверждает покупку когда угодно — через
        // минуту, после перезапуска приложения, на другом экране, — и без
        // адресата чек ушёл бы в никуда.
        final giftGroup = productId == kGiftProductId
            ? await _plus.takeGiftGroup()
            : '';
        final res = await PbCoinsService().iapPurchase(
          productId: productId,
          purchaseToken: purchaseToken,
          groupId: giftGroup,
        );
        if (res == null || res['ok'] != true) {
          // Сервер покупку не принял — связь возвращаем на место, иначе
          // повторная попытка (магазин пришлёт чек снова) уйдёт без адресата.
          if (giftGroup.isNotEmpty) await _plus.rememberGiftGroup(giftGroup);
          return null;
        }
        return (res['coins'] as num?)?.toInt() ?? 0;
      },
    );
    if (mounted) setState(() {});
  }

  void unawaitedRefresh() {
    _plus.refresh();
  }

  @override
  void dispose() {
    _plus.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    // dispose у общего магазина не зовём: он живёт со всем приложением и
    // должен продолжать слушать поток покупок после закрытия экрана.
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = _plus.active;

    return Theme(
      data: ProfileTheme.data(_cs),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: _cs.surface,
          appBar: AppBar(
            backgroundColor: _cs.surface,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            title: Text(
              _s.plusTitle,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                color: _cs.onSurface,
              ),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).padding.bottom + 32,
            ),
            children: [
              _hero(active),
              const SizedBox(height: 20),
              _features(),
              const SizedBox(height: 20),
              if (!active) _actions(),
              if (active) _ownedNote(),
              if (_gift.visible) ...[
                const SizedBox(height: 20),
                _giftCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(bool active) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: active ? _cs.primaryContainer : _cs.primary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active ? Icons.verified_rounded : Icons.workspace_premium_rounded,
            size: 32,
            color: active ? _cs.onPrimaryContainer : _cs.onPrimary,
          ),
          const SizedBox(height: 14),
          Text(
            active ? _s.plusActiveTitle : _s.plusHeroTitle,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              letterSpacing: -0.5,
              color: active ? _cs.onPrimaryContainer : _cs.onPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            active ? _s.plusActiveBody : _s.plusHeroBody,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 14,
              height: 1.4,
              color: (active ? _cs.onPrimaryContainer : _cs.onPrimary)
                  .withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _features() {
    final items = <(IconData, String, String)>[
      (Icons.block_rounded, _s.plusNoAdsTitle, _s.plusNoAdsBody),
      (Icons.palette_rounded, _s.plusThemesTitle, _s.plusThemesBody),
      (Icons.colorize_rounded, _s.plusCustomThemeTitle, _s.plusCustomThemeBody),
      (Icons.water_drop_rounded, _s.plusCycleTitle, _s.plusCycleBody),
      (Icons.widgets_rounded, _s.plusWidgetsTitle, _s.plusWidgetsBody),
      (Icons.lightbulb_rounded, _s.plusTipsTitle, _s.plusTipsBody),
      (Icons.interests_rounded, _s.plusShapesTitle, _s.plusShapesBody),
      (Icons.videocam_rounded, _s.plusVideoTitle, _s.plusVideoBody),
      (Icons.brush_rounded, _s.plusColoringTitle, _s.plusColoringBody),
      (Icons.favorite_rounded, _s.plusWishesTitle, _s.plusWishesBody),
      (Icons.menu_book_rounded, _s.plusBookTitle, _s.plusBookBody),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 72,
                endIndent: 16,
                color: _cs.outlineVariant.withValues(alpha: 0.4),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(items[i].$1,
                        size: 22, color: _cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontVariations: const [FontVariation('wght', 600)],
                            color: _cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 13,
                            height: 1.3,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    if (!PlusService.canPurchase) {
      // В сборке из Google Play покупка не предлагается: их правила запрещают
      // проводить оплату цифровых товаров мимо своего биллинга.
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          _s.plusUnavailableHere,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 13,
            height: 1.35,
            color: _cs.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _openPurchase,
            icon: Icon(
              PlusService.buysInStore
                  ? Icons.lock_open_rounded
                  : Icons.open_in_new_rounded,
              size: 18,
            ),
            label: Text(
              _buyLabel,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        // Распродажу объявляет сервер, поэтому она появляется без новой
        // сборки: прежняя цена зачёркнута, рядом размер скидки.
        if (_gift.plusDiscount > 0 && _gift.plusBaseLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _gift.plusBaseLabel,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  decoration: TextDecoration.lineThrough,
                  color: _cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _s.plusGiftDiscountBadge(_gift.plusDiscount),
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
        // Ввод кода в Play-сборке не показываем: код выдают за оплату мимо
        // биллинга Google, и кнопка «у меня есть код» рядом с их же покупкой
        // читается как обход. Купившие на lava.top с другой почтой открывают
        // доступ в сборке с GitHub — флаг всё равно ложится на аккаунт.
        if (!PlusService.buysInStore) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          // Без обводки: рамка спорила с заливкой кнопки покупки и вторая
          // кнопка читалась равной первой. Вес ей задаёт только текст.
          child: TextButton(
            onPressed: _busy ? null : _openRedeem,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              _s.plusHaveCode,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ],
        const SizedBox(height: 12),
        Text(
          _s.plusHowItWorks,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 12,
            height: 1.4,
            color: _cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Карточка «подарить партнёру» — своя, под списком возможностей.
  ///
  /// Стоит и у тех, кто Плюс уже купил: им покупать больше нечего, и подарок
  /// остаётся единственным действием на этом экране.
  Widget _giftCard() {
    final target = _gift.suggested;
    final single = _gift.recipients.length == 1;
    final canGift = _gift.hasAnyoneToGift;
    final price = _giftPriceLabel;
    // Зачёркнутая цена — только у скидки на нашей стороне: акции магазинов
    // приезжают уже посчитанными в его же цене.
    final base = PlusService.buysInStore ? '' : _gift.baseLabel;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (single && target != null) ...[
                AvatarWidget(
                  uid: target.uid,
                  liveUrl: target.avatarUrl,
                  name: target.name,
                  size: 40,
                  primary: _cs.primary,
                ),
                const SizedBox(width: 12),
              ] else ...[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.card_giftcard_rounded,
                      size: 21, color: _cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      single && target != null && target.name.isNotEmpty
                          ? _s.plusGiftTitleFor(target.name)
                          : _s.plusGiftTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation('wght', 600)],
                        color: _cs.onSurface,
                      ),
                    ),
                    if (single && canGift) ...[
                      const SizedBox(height: 2),
                      Text(
                        _s.plusGiftPairRole,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 12,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Скидку называет сервер, поэтому плашка появляется у людей в
              // тот же час, когда её включают, — без новой сборки.
              if (canGift && _gift.discount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _s.plusGiftDiscountBadge(_gift.discount),
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            canGift ? _s.plusGiftBody : _s.plusGiftAllHave,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              height: 1.4,
              color: _cs.onSurfaceVariant,
            ),
          ),
          if (canGift) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _busy ? null : _openGift,
                style: FilledButton.styleFrom(
                  backgroundColor: _cs.primaryContainer,
                  foregroundColor: _cs.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.card_giftcard_rounded, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        price.isEmpty
                            ? _s.plusGiftAction
                            : _s.plusGiftActionFor(price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (base.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        base,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                          color: _cs.onPrimaryContainer.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Выбор получателя, затем счёт на его почту.
  ///
  /// Почту подставляет сервер: клиент передаёт только связь, через которую
  /// виден человек. Иначе подделанный запрос дарил бы доступ чужому адресу.
  Future<void> _openGift() async {
    final chosen = await showGiftRecipientSheet(
      context,
      scheme: _cs,
      offer: _gift,
      priceLabel: _giftPriceLabel,
    );
    if (chosen == null || !mounted) return;

    // В Play и App Store подарок покупается их биллингом: отдельный расходуемый
    // товар, а доступ получателю выдаёт сервер по чеку. Вести оттуда на внешнюю
    // оплату нельзя — за это снимают приложение.
    if (PlusService.buysInStore) {
      await _buyGiftInStore(chosen);
      return;
    }

    setState(() => _busy = true);
    final res = await _plus.giftCheckoutUrl(groupId: chosen.groupId);
    if (!mounted) return;
    setState(() => _busy = false);

    // Доступ появился, пока выбирали, — платить не за что.
    if (res.already) {
      _toast(_s.plusGiftHasPlus);
      unawaited(_loadGift());
      return;
    }
    final url = Uri.tryParse(res.url ?? '');
    if (url == null) {
      _toast(_s.plusGiftFailed);
      return;
    }
    try {
      await safeLaunchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _toast(_s.plusGiftFailed);
    }
  }

  Widget _ownedNote() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.devices_rounded, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _s.plusPortableNote,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                height: 1.35,
                color: _cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Подпись кнопки покупки.
  ///
  /// Цену берём у магазина, а не пишем в коде: у Apple и Google свои валюты,
  /// округления и налоги в каждой стране, и захардкоженные «9,99 $» врали бы
  /// всем, кроме США. Товар ещё не загрузился — показываем действие без цены,
  /// а не пустое место.
  String get _buyLabel {
    final fromStore = _store?.priceLabel(kPlusProductId);
    if (fromStore != null && fromStore.isNotEmpty) {
      return _s.plusBuyFor(fromStore);
    }
    // В сборках с сайта магазина нет, и цену называет сервер: он читает её из
    // каталога lava.top в валюте этой страны. Пока ответ не пришёл — кнопка
    // говорит действие без суммы, а не показывает пустое место.
    final fromServer = _gift.plusPriceLabel;
    if (fromServer.isNotEmpty) return _s.plusBuyFor(fromServer);
    return _s.plusBuy;
  }

  Future<void> _openPurchase() async {
    // На iPhone и в Play покупка идёт ТОЛЬКО через биллинг магазина: внешняя
    // оплата — это 3.1.1, за которое версию уже отклоняли. В остальных
    // сборках остаётся счёт на lava.top.
    if (PlusService.buysInStore) {
      await _buyInStore();
      return;
    }
    // Дальше идёт внешняя оплата, и на iPhone её быть не может: 3.1.1, за
    // которое версию уже отклоняли. Сюда попадём только если биллинг магазина
    // почему-то отвалился — тогда честнее сказать это, чем увести на сайт.
    if (Platform.isIOS) {
      _toast(_s.plusStoreUnavailable);
      return;
    }
    setState(() => _busy = true);
    // Ссылку выдаёт сервер: он заводит счёт в lava.top на почту аккаунта, и
    // только по счетам оттуда приходят уведомления об оплате. Не ответил —
    // идём на витрину, как раньше, но тогда доступ придётся выдавать руками.
    final fromServer = await PlusService.instance.checkoutUrl();
    final url = Uri.tryParse(fromServer ?? PlusService.purchaseUrl);
    if (url == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await safeLaunchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Браузера нет или ссылка не открылась — молча возвращаем кнопку.
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Подарок через биллинг магазина.
  ///
  /// Связь получателя записывается на диск ДО покупки: чек может прийти когда
  /// угодно, вплоть до следующего запуска приложения, и сервер должен знать,
  /// кому открывать доступ. Отмена и ошибка её снимают — иначе следующий
  /// подарок ушёл бы прошлому человеку.
  Future<void> _buyGiftInStore(GiftRecipient chosen) async {
    final store = _store;
    if (store == null || !store.isAvailable) {
      _toast(_s.plusStoreUnavailable);
      return;
    }
    setState(() => _busy = true);
    if (!await store.ensureProduct(kGiftProductId)) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_s.plusStoreUnavailable);
      return;
    }

    await _plus.rememberGiftGroup(chosen.groupId);
    final res = await store.buy(kGiftProductId);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (res.status) {
      case IapStatus.success:
        _toast(_s.plusGiftDone(chosen.name));
        unawaited(_loadGift());
      case IapStatus.pending:
        // Оплата ещё идёт (родительский контроль, отложенный платёж): связь
        // остаётся на диске и дождётся чека.
        _toast(_s.plusPurchasePending);
      case IapStatus.cancelled:
        await _plus.takeGiftGroup();
      case IapStatus.error:
        await _plus.takeGiftGroup();
        if (mounted) _toast(_s.plusGiftFailed);
    }
  }

  /// Покупка через биллинг Google Play. Флаг доступа ставит сервер, экран лишь
  /// показывает исход: успех, отмену или ошибку.
  Future<void> _buyInStore() async {
    final store = _store;
    if (store == null || !store.isAvailable) {
      _toast(_s.plusStoreUnavailable);
      return;
    }
    setState(() => _busy = true);
    final res = await store.buy(kPlusProductId);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res.status) {
      case IapStatus.success:
        await _plus.refresh();
        if (mounted) _toast(_s.plusPurchased);
      case IapStatus.pending:
        _toast(_s.plusPurchasePending);
      case IapStatus.cancelled:
        break; // человек сам отказался — молчим
      case IapStatus.error:
        _toast(_s.plusPurchaseFailed);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// Ввод кода, выданного ботом: платили с другой почты или аккаунта ещё не
  /// было в момент покупки.
  void _openRedeem() {
    final controller = TextEditingController();

    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: _s.plusHaveCode,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.plusCodeHint,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    height: 1.35,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'TG••••••',
                    filled: true,
                    fillColor: _cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottom: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final code = controller.text.trim();
                if (code.isEmpty) return;
                final ok = await _plus.redeem(code);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? _s.plusCodeOk : _s.plusCodeFailed),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _s.plusCodeApply,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
