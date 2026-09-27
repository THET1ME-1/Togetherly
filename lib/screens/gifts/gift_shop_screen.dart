import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/avatar_frame.dart';
import '../../models/gift.dart';
import '../../models/profile_icon.dart';
import '../../models/user_data.dart';
import '../../services/catalog_service.dart';
import '../../services/gift_result.dart';
import '../../services/gifts_service.dart';
import '../../services/locale_service.dart';
import '../../services/plus_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/common/badge_image.dart';
import '../chest_screen.dart';
import '../../widgets/chest/chest_stash_lane.dart';
import '../../widgets/common/gift_image.dart';
import '../../widgets/common/coin_image.dart';
import '../../widgets/common/coin_sheet.dart';

/// Магазин: подарки, значки и рамки на трёх вкладках под общей шапкой
/// (макет «Магазин», 27.09.2026). Карточка везде одна — «Ценник» подарков:
/// ценник в углу, крупный рисунок, название. Купленное помечено «Твой»,
/// надетое выделено тоном карточки. Цены значков и подарков приходят из
/// серверного каталога, рамки не продаются — они выпадают из сундука.
///
/// Витрина подарков: выбрал — списались монеты, партнёру улетел значок.
///
/// Экран собран по M3 Expressive, вариант «Ценник» (26.09.2026): полки по
/// уровням цены, в две колонки. Цена — ярлык цвета темы в углу карточки с
/// монетой, под ним живой подарок во всю ширину, внизу название. Движение —
/// пружина на нажатии (перелёт) и подскок подарка на тапе.
///
/// Баланс приходит снаружи и обновляется через [onCoins]: экран не ходит в
/// профиль сам, потому что источник истины по монетам — ответ серверного
/// роута, и он же возвращается из [GiftsService.send].
class GiftShopScreen extends StatefulWidget {
  const GiftShopScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.coins,
    this.onCoins,
    this.userData,
    this.initialTab = ShopTab.gifts,
    this.showGifts = true,
    this.partnerName,
    this.onOpenCoins,
  });

  final AppTheme theme;
  final String groupId;
  final int coins;

  /// Профиль: значки и рамки, купленное и надетое. Без него магазин — одни
  /// подарки, как раньше.
  final UserData? userData;

  /// Какая вкладка открыта первой: плитка «Магазин» ведёт к подаркам,
  /// значок у ника — к значкам, аватарка — к рамкам.
  final ShopTab initialTab;

  /// Подарки дарят только в паре и только при включённом разделе.
  final bool showGifts;

  /// Имя партнёра — для сундука, куда ведёт вкладка рамок.
  final String? partnerName;

  /// Кошелёк в шапке открывает лист монет.
  final VoidCallback? onOpenCoins;

  /// Новый баланс после отправки — чтобы главный экран не показывал старый.
  final ValueChanged<int>? onCoins;

  @override
  State<GiftShopScreen> createState() => _GiftShopScreenState();
}

enum ShopTab { gifts, badges, frames }

// ── M3-кривые движения ───────────────────────────────────────────────────────
const Cubic _emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
const Cubic _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

/// Уровень витрины по цене: 1 — каждый день (10–15), 2 — по поводу (20–30),
/// 3 — событие (40–60). Уровень задаёт тональный цвет и «крутость» формы.
int _tierOf(int price) => price <= 15 ? 1 : (price <= 30 ? 2 : 3);

/// Полка подарков сундука: в продаже их нет, они только выпадают.
const int _chestShelf = 4;

String _tierName(int tier) {
  if (tier == _chestShelf) return trKey('shopFromChest');
  final ru = LocaleService.instance.isRussian;
  return switch (tier) {
    1 => ru ? 'Каждый день' : 'Everyday',
    2 => ru ? 'По поводу' : 'Occasions',
    _ => ru ? 'Событие' : 'Milestones',
  };
}

class _GiftShopScreenState extends State<GiftShopScreen> {
  /// Тестовая сборка (`--dart-define=GIFTS_FORCE=true`) показывает код отказа.
  static const bool _diagnostics = bool.fromEnvironment('GIFTS_FORCE');

  late int _coins = widget.coins;
  String? _sending;

  late final List<ShopTab> _tabs = [
    if (widget.showGifts) ShopTab.gifts,
    if (widget.userData != null) ...[ShopTab.badges, ShopTab.frames],
  ];
  late ShopTab _tab = _tabs.contains(widget.initialTab)
      ? widget.initialTab
      : _tabs.first;

  /// Фильтр по редкости на вкладках значков и рамок; null — все.
  String? _badgeRarity;
  String? _frameRarity;

  /// Значок или рамка, по которым сейчас идёт запрос.
  String? _busyItem;

  /// Баланс: профиль знает его точнее всех, магазин держит свой на случай,
  /// когда открыт без профиля.
  int get _wallet => widget.userData?.coins ?? _coins;

  /// Активный фильтр уровня; null — показываем все полки.
  int? _filter;

  /// Ролик для подарка без монет. С Плюсом рекламы нет, подарок уходит сразу.
  final RewardedAdService _ad = RewardedAdService();

  @override
  void initState() {
    super.initState();
    if (!PlusService.instance.active) _ad.load();
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  /// Тап по подарку: человек сам выбирает, чем платить — монетами или
  /// рекламой. С Плюсом вместо рекламы «бесплатно».
  Future<void> _choose(Gift gift) async {
    if (_sending != null) return;
    final byAd = await showAppSheet<bool>(
      context,
      builder: (_) => SheetScaffold(
        child: _PaySheet(
          gift: gift,
          coins: _coins,
          adAllowed: gift.giftableByAd,
          plus: PlusService.instance.active,
        ),
      ),
    );
    if (byAd == null || !mounted) return;
    await _send(gift, byAd: byAd);
  }

  Future<void> _send(Gift gift, {bool byAd = false}) async {
    if (_sending != null) return; // второй тап во время отправки

    // Записку спрашиваем до рекламы: иначе человек досмотрит ролик, передумает
    // на вводе, и просмотр пропадёт впустую.
    String? note;
    if (gift.carriesNote) {
      note = await _askNote(gift);
      if (note == null) return; // передумал на вводе записки
    }
    if (!mounted) return;

    if (byAd && !PlusService.instance.active) {
      final messenger = ScaffoldMessenger.of(context);
      if (!_ad.isReady) {
        _ad.load();
        messenger.showSnackBar(
          SnackBar(content: Text(LocaleService.current.streakRestoreNoAd)),
        );
        return;
      }
      setState(() => _sending = gift.key);
      final earned = await _ad.show(uid: PocketBaseService().userId ?? '');
      _ad.load();
      if (!mounted) return;
      // Реклама сама начисляет монеты: доводим новый баланс до профиля.
      final coins = _ad.lastServerCoins;
      setState(() {
        _sending = null;
        if (coins != null) _coins = coins;
      });
      if (coins != null) widget.onCoins?.call(coins);
      if (!earned) return;
    }

    setState(() => _sending = gift.key);
    final res = await GiftsService.instance.send(
      groupId: widget.groupId,
      giftKey: gift.key,
      note: note,
      byAd: byAd,
    );
    if (!mounted) return;

    final s = LocaleService.current;
    var text = res.ok
        ? s.giftSent
        : switch (res.error) {
            GiftError.insufficient => s.giftNotEnoughCoins,
            GiftError.adLimit => s.giftAdLimit,
            GiftError.network => s.giftNoConnection,
            _ => s.giftFailed,
          };
    // В тестовой сборке показываем код причины: без него отказ выглядит как
    // «просто не работает», и чинить нечего.
    if (!res.ok && _diagnostics && res.error != null) {
      text = '$text (${res.error!.name})';
    }
    setState(() {
      _sending = null;
      if (res.coins != null) _coins = res.coins!;
    });
    if (res.coins != null) widget.onCoins?.call(res.coins!);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    if (res.ok) Navigator.of(context).pop();
  }

  /// Записка внутрь коробки, печенья или письма. null = отменил отправку.
  Future<String?> _askNote(Gift gift) async {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final s = LocaleService.current;
    final ctrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: null,
      builder: (ctx) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 360),
        curve: _emphasizedDecelerate,
        builder: (ctx, v, child) => Opacity(
          opacity: v.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 40),
            child: child,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom +
                20,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: GiftImage(gift.key, side: 36),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        gift.title,
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          letterSpacing: -0.3,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  // Длину письма не ограничиваем: счётчик на 500 символов
                  // обрывал текст на полуслове, а хранится записка целиком.
                  // Поле растёт до десяти строк, дальше прокручивается внутри.
                  keyboardType: TextInputType.multiline,
                  maxLines: 10,
                  minLines: 3,
                  autofocus: true,
                  style: TextStyle(color: cs.onSurface, fontFamily: 'Onest'),
                  decoration: InputDecoration(
                    hintText: s.giftNoteHint,
                    hintStyle: TextStyle(color: cs.onSurfaceVariant),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(''),
                        child: Text(s.giftNoteSkip),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                        child: Text(s.giftNoteSend),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pickFilter(int? tier) {
    if (_filter == tier) return;
    setState(() => _filter = tier);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _appBar(cs),
        body: ListenableBuilder(
          listenable: Listenable.merge([
            CatalogService.instance,
            if (widget.userData != null) widget.userData!,
          ]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_tabs.length > 1)
                _ShopTabs(
                  tabs: _tabs,
                  selected: _tab,
                  onPick: (t) => setState(() => _tab = t),
                ),
              Expanded(
                child: switch (_tab) {
                  ShopTab.gifts => _body(cs),
                  ShopTab.badges => _badgesBody(cs),
                  ShopTab.frames => _framesBody(cs),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(ColorScheme cs) {
    final s = LocaleService.current;
    return AppBar(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: cs.onSurface),
      title: Text(
        _tabs.length > 1 ? trKey('shopTitle') : s.giftShopTitle,
        style: TextStyle(
          fontFamily: 'Unbounded',
          color: cs.onSurface,
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
          letterSpacing: -0.4,
          fontSize: 22,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenCoins,
              child: Container(
                padding: const EdgeInsets.fromLTRB(2, 2, 16, 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CoinImage(side: 40),
                    Text(
                      '$_wallet',
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        fontSize: 17,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(ColorScheme cs) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final tiers = _filter == null ? const [1, 2, 3, _chestShelf] : [_filter!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar<int?>(
          items: [
            (null, trKey('shopFilterAll')),
            (1, _tierName(1)),
            (2, _tierName(2)),
            (3, _tierName(3)),
            (_chestShelf, _tierName(_chestShelf)),
          ],
          selected: _filter,
          onPick: _pickFilter,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: _emphasizedDecelerate,
            switchOutCurve: _emphasized,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: ListView(
              key: ValueKey(_filter),
              padding: EdgeInsets.only(
                bottom: 28 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                // Выпавшие из сундука подарки, которые ещё ждут решения.
                if (_filter == null) ChestStashLane(groupId: widget.groupId),
                for (final tier in tiers) ...[
                  _ShelfHeader(title: _tierName(tier)),
                  if (tier == _chestShelf)
                    _chestGiftGrid(reduce)
                  else
                    _giftGrid(
                      GiftCatalog.all
                          .where((g) => _tierOf(g.price) == tier)
                          .toList(),
                      reduce,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Подарки ──────────────────────────────────────────────────────────────
  Widget _giftGrid(List<Gift> gifts, bool reduce) {
    return _CardGrid(
      count: gifts.length,
      builder: (context, i) {
        final gift = gifts[i];
        final affordable = _wallet >= gift.currentPrice;
        // Без монет подарок всё равно можно отправить за рекламу, кроме копилки.
        final usable = affordable || gift.giftableByAd;
        return _ShopCard(
          tag: _PriceTag(price: gift.currentPrice, affordable: affordable),
          art: (side) => GiftImage(gift.key, side: side),
          title: gift.title,
          muted: !affordable,
          usable: usable,
          busy: _sending == gift.key,
          reduce: reduce,
          onTap: () => _sending == null ? _choose(gift) : null,
        );
      },
    );
  }

  /// Подарки сундука: та же карточка, вместо цены «Из сундука». Купить или
  /// подарить их отсюда нельзя — нажатие объясняет это и ведёт в сундук.
  Widget _chestGiftGrid(bool reduce) {
    const gifts = GiftCatalog.chest;
    return _CardGrid(
      count: gifts.length,
      builder: (context, i) {
        final gift = gifts[i];
        return _ShopCard(
          tag: _LabelTag(trKey('shopFromChest'), icon: Icons.redeem_rounded),
          art: (side) => GiftImage(gift.key, side: side),
          title: gift.title,
          muted: true,
          reduce: reduce,
          onTap: () => _openChestGift(gift),
        );
      },
    );
  }

  Future<void> _openChestGift(Gift gift) async {
    final cs = Theme.of(context).colorScheme;
    final chest = widget.groupId.isNotEmpty;
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => SheetScaffold(
        child: _ItemSheet(
          art: Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: GiftImage(gift.key, side: 100),
          ),
          title: gift.title,
          lines: [
            trKey('shopGiftChestHint'),
            if (!chest) trKey('shopChestNeedsPair'),
          ],
          actions: [if (chest) ('chest', trKey('shopOpenChest'), true, true)],
        ),
      ),
    );
    if (action == 'chest' && mounted) await _openChest();
  }

  Future<void> _openChest() {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChestScreen(
          theme: widget.theme,
          groupId: widget.groupId,
          partnerName: widget.partnerName,
          onCoins: widget.onCoins,
          userData: widget.userData,
        ),
        settings: const RouteSettings(name: '/chest'),
      ),
    );
  }

  // ── Значки ───────────────────────────────────────────────────────────────
  Widget _rarityBar(
    String? selected,
    List<String> present,
    ValueChanged<String?> onPick,
  ) {
    String name(String r) => switch (r) {
      'rare' => trKey('shopRarityRare'),
      'legendary' => trKey('shopRarityLegendary'),
      'award' => trKey('shopRarityAward'),
      _ => trKey('shopRarityCommon'),
    };
    const order = ['common', 'rare', 'legendary', 'award'];
    return _FilterBar<String?>(
      items: [
        (null, trKey('shopFilterAll')),
        for (final r in order)
          if (present.contains(r)) (r, name(r)),
      ],
      selected: selected,
      onPick: onPick,
    );
  }

  Widget _emptyNote(ColorScheme cs, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: 14,
          color: cs.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget _badgesBody(ColorScheme cs) {
    final ud = widget.userData!;
    final all = ProfileIcon.all;
    if (all.isEmpty) return _emptyNote(cs, trKey('shopLoading'));
    final shown = _badgeRarity == null
        ? all
        : all.where((i) => i.rarity == _badgeRarity).toList();
    final reduce = MediaQuery.of(context).disableAnimations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rarityBar(
          _badgeRarity,
          {for (final i in all) i.rarity}.toList(),
          (r) => setState(() => _badgeRarity = r),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(
              top: 6,
              bottom: 28 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              _CardGrid(
                count: shown.length,
                builder: (context, i) {
                  final icon = shown[i];
                  final owns = ud.ownsIcon(icon.id);
                  final worn = ud.equippedIcon == icon.id;
                  final affordable = _wallet >= icon.price;
                  return _ShopCard(
                    tag: worn
                        ? _LabelTag(trKey('shopWornBadge'), filled: true)
                        : owns
                        ? _LabelTag(trKey('shopMineBadge'))
                        : icon.fromChest
                        ? _LabelTag(
                            trKey('shopFromChest'),
                            icon: Icons.redeem_rounded,
                          )
                        : icon.grantOnly
                        ? _LabelTag(trKey('shopAward'))
                        : _PriceTag(price: icon.price, affordable: affordable),
                    art: (side) => BadgeImage(icon.id, side: side * 0.86),
                    title: icon.name,
                    selected: worn,
                    muted: !owns && (icon.grantOnly || !affordable),
                    busy: _busyItem == icon.id,
                    reduce: reduce,
                    onTap: () => _openBadge(icon),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openBadge(ProfileIcon icon) async {
    final ud = widget.userData!;
    if (_busyItem != null) return;
    final owns = ud.ownsIcon(icon.id);
    final worn = ud.equippedIcon == icon.id;
    final canBuy = !owns && !icon.grantOnly && icon.price > 0;
    final affordable = _wallet >= icon.price;
    final chest = !owns && icon.fromChest && widget.groupId.isNotEmpty;
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => SheetScaffold(
        child: _ItemSheet(
          art: BadgeImage(icon.id, side: 104),
          title: icon.name,
          lines: [
            if (icon.description.isNotEmpty) icon.description,
            trKey(
              owns || !icon.grantOnly
                  ? 'shopBadgeHint'
                  : icon.fromChest
                  ? 'shopBadgeChestHint'
                  : 'shopBadgeAwardHint',
            ),
            if (!owns && icon.fromChest && !chest) trKey('shopChestNeedsPair'),
            if (canBuy && !affordable) LocaleService.current.giftNotEnoughCoins,
          ],
          actions: [
            if (worn) ('off', trKey('shopTakeOff'), false, true),
            if (owns && !worn) ('wear', trKey('shopWear'), true, true),
            if (canBuy)
              (
                'buy',
                trKey('shopBuyFor').replaceAll('{n}', '${icon.price}'),
                true,
                affordable,
              ),
            if (canBuy && !affordable && widget.onOpenCoins != null)
              ('coins', LocaleService.current.coinBalance, false, true),
            if (chest) ('chest', trKey('shopOpenChest'), true, true),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'coins') {
      widget.onOpenCoins?.call();
      return;
    }
    if (action == 'chest') {
      await _openChest();
      return;
    }
    setState(() => _busyItem = icon.id);
    var ok = true;
    if (action == 'off') {
      await ud.setBadgeIcon(null);
    } else if (action == 'wear') {
      await ud.setBadgeIcon(icon.id);
    } else if (action == 'buy') {
      ok = await ud.purchaseIcon(icon);
      // Купленный значок сразу надевается: ради этого его и брали.
      if (ok) await ud.setBadgeIcon(icon.id);
    }
    if (!mounted) return;
    setState(() => _busyItem = null);
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(trKey('shopFailed'))));
    }
  }

  // ── Рамки ────────────────────────────────────────────────────────────────
  /// Своя аватарка с рамкой [frame] — рамка занимает сторону [side] целиком.
  Widget _framedMe(String frame, double side) {
    final ud = widget.userData!;
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: side,
      child: Center(
        child: AvatarWidget(
          uid: ud.uid.isNotEmpty ? ud.uid : (PocketBaseService().userId ?? ''),
          liveUrl: ud.avatarUrl,
          name: ud.displayName,
          size: side / AvatarFrame.scale,
          primary: cs.primary,
          frame: frame,
        ),
      ),
    );
  }

  Widget _framesBody(ColorScheme cs) {
    final ud = widget.userData!;
    final all = AvatarFrame.all;
    if (all.isEmpty) return _emptyNote(cs, trKey('shopLoading'));
    final shown = _frameRarity == null
        ? all
        : all.where((f) => f.rarity == _frameRarity).toList();
    final reduce = MediaQuery.of(context).disableAnimations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rarityBar(
          _frameRarity,
          {for (final f in all) f.rarity}.toList(),
          (r) => setState(() => _frameRarity = r),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(
              top: 6,
              bottom: 28 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              _CardGrid(
                count: shown.length,
                builder: (context, i) {
                  final f = shown[i];
                  final owns = ud.ownsFrame(f.key);
                  final worn = ud.equippedFrame == f.key;
                  return _ShopCard(
                    tag: worn
                        ? _LabelTag(trKey('shopWornFrame'), filled: true)
                        : owns
                        ? _LabelTag(trKey('shopMineFrame'))
                        : _LabelTag(
                            trKey('shopFromChest'),
                            icon: Icons.redeem_rounded,
                          ),
                    art: (side) => _framedMe(f.key, side),
                    title: f.name,
                    selected: worn,
                    muted: !owns,
                    busy: _busyItem == f.key,
                    reduce: reduce,
                    onTap: () => _openFrame(f),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openFrame(AvatarFrame f) async {
    final ud = widget.userData!;
    if (_busyItem != null) return;
    final owns = ud.ownsFrame(f.key);
    final worn = ud.equippedFrame == f.key;
    final chest = !owns && widget.groupId.isNotEmpty;
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => SheetScaffold(
        child: _ItemSheet(
          art: _framedMe(f.key, 200),
          title: f.name,
          lines: [
            if (f.description.isNotEmpty) f.description,
            trKey('shopFrameHint'),
            if (!owns) trKey('shopFrameChestHint'),
            if (!owns && !chest) trKey('shopChestNeedsPair'),
          ],
          actions: [
            if (worn) ('off', trKey('shopTakeOff'), false, true),
            if (owns && !worn) ('wear', trKey('shopWear'), true, true),
            if (chest) ('chest', trKey('shopOpenChest'), true, true),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'chest') {
      await _openChest();
      return;
    }
    setState(() => _busyItem = f.key);
    await ud.setFrame(action == 'off' ? null : f.key);
    if (!mounted) return;
    setState(() => _busyItem = null);
  }
}

// ── Выбор оплаты ─────────────────────────────────────────────────────────────
/// Лист выбора: подарить за монеты или за рекламу. Возвращает `false` — монеты,
/// `true` — реклама (с Плюсом — бесплатно), `null` — передумал.
///
/// Главное действие залито, второе с обводкой: хватает монет — главное
/// «За монеты», не хватает — «За рекламу», и оно встаёт первым. Две залитые
/// кнопки подряд в светлой теме сливались в одну.
class _PaySheet extends StatelessWidget {
  const _PaySheet({
    required this.gift,
    required this.coins,
    required this.adAllowed,
    required this.plus,
  });

  final Gift gift;
  final int coins;
  final bool adAllowed;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final canPay = coins >= gift.currentPrice;
    final adFirst = adAllowed && !canPay;
    const minSize = Size.fromHeight(56);

    final coinLabel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(s.giftForCoins, textAlign: TextAlign.center)),
        const SizedBox(width: 10),
        CoinImage(side: 18),
        const SizedBox(width: 4),
        Text(
          '${gift.currentPrice}',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    final coinButton = canPay
        ? FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: FilledButton.styleFrom(minimumSize: minSize),
            child: coinLabel,
          )
        : OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(minimumSize: minSize),
            child: coinLabel,
          );

    final adIcon = Icon(
      plus ? Icons.card_giftcard_rounded : Icons.play_circle_rounded,
    );
    final adText = Text(
      plus ? s.giftForFree : s.giftForAd,
      textAlign: TextAlign.center,
    );
    void onAd() => Navigator.pop(context, true);
    final adButton = adFirst
        ? FilledButton.icon(
            onPressed: onAd,
            style: FilledButton.styleFrom(minimumSize: minSize),
            icon: adIcon,
            label: adText,
          )
        : OutlinedButton.icon(
            onPressed: onAd,
            style: OutlinedButton.styleFrom(minimumSize: minSize),
            icon: adIcon,
            label: adText,
          );

    final notes = [
      if (!canPay) s.giftNotEnoughCoins,
      if (adAllowed && !plus) s.giftAdHint,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: GiftImage(gift.key, side: 84),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            gift.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              fontSize: 20,
              letterSpacing: -0.3,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 22),
          if (adFirst) ...[
            adButton,
            const SizedBox(height: 10),
            coinButton,
          ] else ...[
            coinButton,
            if (adAllowed) ...[const SizedBox(height: 10), adButton],
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              notes.join('. '),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                color: cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Вкладки ──────────────────────────────────────────────────────────────────
/// Группа-пилюля M3: общая тональная подложка, выбранная вкладка залита
/// цветом темы, линий нет.
class _ShopTabs extends StatelessWidget {
  const _ShopTabs({
    required this.tabs,
    required this.selected,
    required this.onPick,
  });
  final List<ShopTab> tabs;
  final ShopTab selected;
  final ValueChanged<ShopTab> onPick;

  static String _label(ShopTab t) => switch (t) {
    ShopTab.gifts => trKey('shopTabGifts'),
    ShopTab.badges => trKey('shopTabBadges'),
    ShopTab.frames => trKey('shopTabFrames'),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                child: Semantics(
                  selected: t == selected,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: _emphasized,
                      constraints: const BoxConstraints(minHeight: 40),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: t == selected ? cs.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _label(t),
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            fontSize: 15,
                            color: t == selected
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Фильтр-чипы ──────────────────────────────────────────────────────────────
class _FilterBar<T> extends StatelessWidget {
  const _FilterBar({
    required this.items,
    required this.selected,
    required this.onPick,
  });
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (value, label) = items[i];
          return _FilterChip(
            label: label,
            selected: selected == value,
            onTap: () => onPick(value),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: _emphasized,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Onest',
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              fontSize: 13.5,
              color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Заголовок полки ──────────────────────────────────────────────────────────
class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Unbounded',
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
          fontSize: 18,
          letterSpacing: -0.3,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

// ── Сетка ────────────────────────────────────────────────────────────────────
/// Две колонки всегда: рисунок должен быть крупным. Высоту карточки
/// считаем из ширины колонки и настоящей высоты подписи — число
/// `childAspectRatio` верно только для той ширины и того шрифта, под
/// которые его подбирали.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.count, required this.builder});

  final int count;
  final IndexedWidgetBuilder builder;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final col = (box.maxWidth - 32 - _gap) / 2;
        final extent = _ShopCard.heightFor(context, col);
        return GridView.builder(
          // Запас прогрева: без него ряд за краем экрана начинал готовиться
          // ровно тогда, когда его уже листают.
          cacheExtent: 600,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            mainAxisExtent: extent,
          ),
          itemCount: count,
          itemBuilder: builder,
        );
      },
    );
  }
}

// ── Ярлыки в углу карточки ───────────────────────────────────────────────────
const BorderRadius _tagRadius = BorderRadius.only(
  topLeft: Radius.circular(999),
  topRight: Radius.circular(999),
  bottomRight: Radius.circular(999),
  bottomLeft: Radius.circular(10),
);

/// Цена ярлыком цвета темы с монетой. Нажатие открывает монету TY крупно.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price, required this.affordable});
  final int price;
  final bool affordable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showCoinSheet(context),
      child: Container(
        height: _ShopCard._tag,
        padding: const EdgeInsets.fromLTRB(2, 0, 14, 0),
        decoration: BoxDecoration(
          color: affordable ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: _tagRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoinImage(side: 38),
            Text(
              '$price',
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                fontSize: 20,
                height: 1,
                color: affordable ? cs.onPrimary : cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ярлык словом: «Твой», «Надет», «Из сундука». Залитый — надетое, светлая
/// плашка — купленное или откуда берётся, чтобы не сливаться с карточкой.
class _LabelTag extends StatelessWidget {
  const _LabelTag(this.text, {this.filled = false, this.icon});
  final String text;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = filled ? cs.onPrimary : cs.onSecondaryContainer;
    return Container(
      height: _ShopCard._tag,
      padding: EdgeInsets.fromLTRB(icon == null ? 14 : 10, 0, 14, 0),
      decoration: BoxDecoration(
        color: filled ? cs.primary : cs.surface,
        borderRadius: _tagRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Onest',
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                fontSize: 14,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Карточка («Ценник») ──────────────────────────────────────────────────────
/// Ярлык в левом верхнем углу, под ним рисунок во всю ширину карточки, внизу
/// название. Надетое выделено тоном карточки (`secondaryContainer`), обводок
/// нет. Движение — пружина на нажатии (перелёт) и подскок рисунка на тапе.
class _ShopCard extends StatefulWidget {
  const _ShopCard({
    required this.tag,
    required this.art,
    required this.title,
    required this.reduce,
    required this.onTap,
    this.selected = false,
    this.muted = false,
    this.usable = true,
    this.busy = false,
  });

  final Widget tag;
  final Widget Function(double side) art;
  final String title;
  final bool reduce;
  final VoidCallback onTap;
  final bool selected;
  final bool muted;
  final bool usable;
  final bool busy;

  static const double _pad = 10;
  static const double _tag = 40;
  static const double _art = 0.78;
  static const double _name = 15;

  /// Высота карточки при ширине колонки [width].
  static double heightFor(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final nameH = scaler.scale(_name) * 1.3;
    return _pad + _tag + (width - 2 * _pad) * _art + 4 + nameH + _pad + 6;
  }

  @override
  State<_ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<_ShopCard> with TickerProviderStateMixin {
  /// Пружина масштаба на нажатии: 0 — покой, 1 — вжато; отпускание —
  /// SpringSimulation с перелётом (карточка «пружинит» назад).
  late final AnimationController _press = AnimationController(
    vsync: this,
    value: 0,
    lowerBound: -0.4, // перелёт: масштаб чуть больше 1
    upperBound: 1,
  );

  /// Рисунок подпрыгивает на тапе (0→1→0).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _press.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _down(_) {
    if (widget.reduce) return;
    _press.animateTo(
      1,
      duration: const Duration(milliseconds: 110),
      curve: _emphasized,
    );
  }

  void _release() {
    if (widget.reduce) {
      _press.value = 0;
      return;
    }
    _press.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 480, damping: 17),
        _press.value,
        0,
        _press.velocity,
      ),
    );
  }

  void _tap() {
    if (widget.busy) return;
    if (!widget.reduce) _pulse.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final titleColor = selected
        ? cs.onSecondaryContainer
        : (widget.muted ? cs.onSurfaceVariant : cs.onSurface);

    final card = AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final scale = 1 - 0.05 * _press.value; // перелёт даёт scale > 1
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: _emphasized,
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
        ),
        padding: const EdgeInsets.all(_ShopCard._pad),
        child: LayoutBuilder(
          builder: (context, box) {
            final art = box.maxWidth * _ShopCard._art;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: widget.tag),
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final p = math.sin(_pulse.value * math.pi);
                        return Transform.translate(
                          offset: Offset(0, -8 * p),
                          child: Transform.scale(
                            scale: 1 + 0.08 * p,
                            child: child,
                          ),
                        );
                      },
                      child: widget.art(art),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    fontSize: _ShopCard._name,
                    height: 1.3,
                    letterSpacing: -0.2,
                    color: titleColor,
                  ),
                ),
                SizedBox(
                  height: 6,
                  child: widget.busy
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );

    final usable = widget.usable;
    return GestureDetector(
      onTapDown: usable ? _down : null,
      onTapUp: usable
          ? (_) {
              _release();
              _tap();
            }
          : null,
      onTapCancel: usable ? _release : null,
      child: Opacity(opacity: usable ? 1 : 0.55, child: card),
    );
  }
}

// ── Лист значка или рамки ────────────────────────────────────────────────────
/// Рисунок крупно, название, пояснения и кнопки. Кнопка — (действие, подпись,
/// залитая, доступна); лист возвращает действие.
class _ItemSheet extends StatelessWidget {
  const _ItemSheet({
    required this.art,
    required this.title,
    required this.lines,
    required this.actions,
  });

  final Widget art;
  final String title;
  final List<String> lines;
  final List<(String, String, bool, bool)> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const minSize = Size.fromHeight(56);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: art),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              fontSize: 20,
              letterSpacing: -0.3,
              color: cs.onSurface,
            ),
          ),
          for (final line in lines) ...[
            const SizedBox(height: 8),
            Text(
              line,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                color: cs.onSurfaceVariant,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
          if (actions.isNotEmpty) const SizedBox(height: 20),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final (id, label, filled, enabled) = actions[i];
                final onPressed = enabled
                    ? () => Navigator.pop(context, id)
                    : null;
                final child = FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1),
                );
                return filled
                    ? FilledButton(
                        onPressed: onPressed,
                        style: FilledButton.styleFrom(minimumSize: minSize),
                        child: child,
                      )
                    : OutlinedButton(
                        onPressed: onPressed,
                        style: OutlinedButton.styleFrom(minimumSize: minSize),
                        child: child,
                      );
              },
            ),
          ],
        ],
      ),
    );
  }
}
