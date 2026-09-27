import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/gift.dart';
import '../../services/gift_result.dart';
import '../../services/gifts_service.dart';
import '../../services/locale_service.dart';
import '../../services/plus_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/chest/chest_stash_lane.dart';
import '../../widgets/common/gift_image.dart';
import '../../widgets/common/coin_image.dart';
import '../../widgets/common/coin_sheet.dart';

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
  });

  final AppTheme theme;
  final String groupId;
  final int coins;

  /// Новый баланс после отправки — чтобы главный экран не показывал старый.
  final ValueChanged<int>? onCoins;

  @override
  State<GiftShopScreen> createState() => _GiftShopScreenState();
}

// ── M3-кривые движения ───────────────────────────────────────────────────────
const Cubic _emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
const Cubic _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

/// Уровень витрины по цене: 1 — каждый день (10–15), 2 — по поводу (20–30),
/// 3 — событие (40–60). Уровень задаёт тональный цвет и «крутость» формы.
int _tierOf(int price) => price <= 15 ? 1 : (price <= 30 ? 2 : 3);

String _tierName(int tier) {
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
            SnackBar(content: Text(LocaleService.current.streakRestoreNoAd)));
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
        groupId: widget.groupId, giftKey: gift.key, note: note, byAd: byAd);
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
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
          child: Transform.translate(offset: Offset(0, (1 - v) * 40), child: child),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
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
                      child: Text(gift.title,
                          style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
                              letterSpacing: -0.3,
                              color: cs.onSurface)),
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
        body: _body(cs),
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
        s.giftShopTitle,
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
                    '$_coins',
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
      ],
    );
  }

  Widget _body(ColorScheme cs) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final tiers = _filter == null ? const [1, 2, 3] : [_filter!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(selected: _filter, onPick: _pickFilter),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: _emphasizedDecelerate,
            switchOutCurve: _emphasized,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: child,
            ),
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
                  _ShelfGrid(
                    gifts: GiftCatalog.all
                        .where((g) => _tierOf(g.price) == tier)
                        .toList(),
                    coins: _coins,
                    sending: _sending,
                    reduce: reduce,
                    onSend: (g) => _sending == null ? _choose(g) : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
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

    final adIcon = Icon(plus ? Icons.card_giftcard_rounded : Icons.play_circle_rounded);
    final adText = Text(plus ? s.giftForFree : s.giftForAd, textAlign: TextAlign.center);
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
          if (adFirst) ...[adButton, const SizedBox(height: 10), coinButton]
          else ...[
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

// ── Фильтр-чипы уровней ──────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onPick});
  final int? selected;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.instance.isRussian;
    final items = <(int?, String)>[
      (null, ru ? 'Все' : 'All'),
      (1, _tierName(1)),
      (2, _tierName(2)),
      (3, _tierName(3)),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (tier, label) = items[i];
          return _FilterChip(
            label: label,
            selected: selected == tier,
            onTap: () => onPick(tier),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});
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
              color:
                  selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
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

// ── Сетка полки ──────────────────────────────────────────────────────────────
/// Две колонки всегда: подарок должен быть крупным. Высоту карточки
/// считаем из ширины колонки и настоящей высоты подписи — число
/// `childAspectRatio` верно только для той ширины и того шрифта, под
/// которые его подбирали.
class _ShelfGrid extends StatelessWidget {
  const _ShelfGrid({
    required this.gifts,
    required this.coins,
    required this.sending,
    required this.reduce,
    required this.onSend,
  });

  final List<Gift> gifts;
  final int coins;
  final String? sending;
  final bool reduce;
  final ValueChanged<Gift> onSend;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final col = (box.maxWidth - 32 - _gap) / 2;
      final extent = _GiftCard.heightFor(context, col);
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
        itemCount: gifts.length,
        itemBuilder: (context, i) {
          final gift = gifts[i];
          return _GiftCard(
            gift: gift,
            affordable: coins >= gift.currentPrice,
            busy: sending == gift.key,
            reduce: reduce,
            onSend: () => onSend(gift),
          );
        },
      );
    });
  }
}

// ── Карточка подарка («Ценник») ──────────────────────────────────────────────
/// Цена ярлыком цвета темы в левом верхнем углу, под ним подарок во всю
/// ширину карточки, внизу название. Ни подложек, ни подписей-характеристик:
/// подарок и цена должны читаться с первого взгляда.
class _GiftCard extends StatefulWidget {
  const _GiftCard({
    required this.gift,
    required this.affordable,
    required this.busy,
    required this.reduce,
    required this.onSend,
  });

  final Gift gift;
  final bool affordable;
  final bool busy;
  final bool reduce;
  final VoidCallback onSend;

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
  State<_GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends State<_GiftCard> with TickerProviderStateMixin {
  /// Пружина масштаба на нажатии: 0 — покой, 1 — вжато; отпускание —
  /// SpringSimulation с перелётом (карточка «пружинит» назад).
  late final AnimationController _press = AnimationController(
    vsync: this,
    value: 0,
    lowerBound: -0.4, // перелёт: масштаб чуть больше 1
    upperBound: 1,
  );

  /// Подарок подпрыгивает на тапе (0→1→0).
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
    _press.animateTo(1, duration: const Duration(milliseconds: 110), curve: _emphasized);
  }

  void _release() {
    if (widget.reduce) {
      _press.value = 0;
      return;
    }
    _press.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 480, damping: 17),
      _press.value,
      0,
      _press.velocity,
    ));
  }

  void _tap() {
    if (widget.busy) return;
    if (!widget.reduce) _pulse.forward(from: 0);
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gift = widget.gift;
    final affordable = widget.affordable;
    // Без монет подарок всё равно можно отправить за рекламу, кроме копилки.
    final usable = affordable || gift.giftableByAd;
    final tagBg = affordable ? cs.primary : cs.surfaceContainerHighest;
    final tagFg = affordable ? cs.onPrimary : cs.onSurfaceVariant;

    final card = AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final scale = 1 - 0.05 * _press.value; // перелёт даёт scale > 1
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
        ),
        padding: const EdgeInsets.all(_GiftCard._pad),
        child: LayoutBuilder(builder: (context, box) {
          final art = box.maxWidth * _GiftCard._art;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                // Ценник открывает монету TY крупно; нажатие мимо него — это
                // подарок, как и раньше.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showCoinSheet(context),
                  child: Container(
                  height: _GiftCard._tag,
                  padding: const EdgeInsets.fromLTRB(2, 0, 14, 0),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(999),
                      topRight: Radius.circular(999),
                      bottomRight: Radius.circular(999),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CoinImage(side: 38),
                      Text(
                        '${gift.currentPrice}',
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          fontSize: 20,
                          height: 1,
                          color: tagFg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final p = math.sin(_pulse.value * math.pi);
                      return Transform.translate(
                        offset: Offset(0, -8 * p),
                        child: Transform.scale(scale: 1 + 0.08 * p, child: child),
                      );
                    },
                    child: GiftImage(gift.key, side: art),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                gift.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  fontSize: _GiftCard._name,
                  height: 1.3,
                  letterSpacing: -0.2,
                  color: affordable ? cs.onSurface : cs.onSurfaceVariant,
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
        }),
      ),
    );

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
