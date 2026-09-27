import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dict_strings.dart' show trKey;
import '../models/chest.dart';
import '../models/gift.dart';
import '../services/catalog_service.dart';
import '../services/chest_service.dart';
import '../services/locale_service.dart';
import '../services/offline/pb_id.dart';
import '../services/plus_service.dart';
import '../services/pocketbase_service.dart';
import '../services/rewarded_ad_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/chest/chest_frames.dart';
import '../widgets/chest/chest_prize_image.dart';

/// Экран сундука недели по макету «Сундук недели» (26.09.2026): сверху сундук
/// крупно, под ним кнопка открытия, ниже все призы с шансами по ярусам.
///
/// Кнопка стоит сразу под сундуком, а не прилипает к низу, как на макете:
/// список призов длинный, и до кнопки пришлось бы листать (правка заказчика).
///
/// Открытие: ролик → сервер разыгрывает приз → сундук играет открытие один
/// раз, приз поднимается из него по дорожке [kChestPrizeTrack], на 2,0 с
/// появляется название выигрыша, в 3,8 с сундук снова в покое, а название
/// остаётся — всё как на макете.
///
/// Выпал подарок — на месте кнопки открытия встают «Подарить» и «Оставить
/// себе» (макет «Подарок из сундука», вариант 4Б). Ушёл с экрана, не выбрав, —
/// подарок ждёт в ленте «Из сундука» в магазине подарков.
class ChestScreen extends StatefulWidget {
  const ChestScreen({
    super.key,
    required this.theme,
    required this.groupId,
    this.partnerName,
    this.onCoins,
    this.debugChoice,
  });

  final AppTheme theme;
  final String groupId;

  /// Имя партнёра для подсказки под кнопкой «Подарить».
  final String? partnerName;

  /// Новый баланс после монетного приза — доводится до профиля.
  final ValueChanged<int>? onCoins;

  /// Превью: экран сразу в состоянии «выпал подарок, ждёт выбора».
  @visibleForTesting
  final ChestStashItem? debugChoice;

  @override
  State<ChestScreen> createState() => _ChestScreenState();
}

class _ChestScreenState extends State<ChestScreen> {
  final RewardedAdService _ad = RewardedAdService();

  ChestState? _state;
  bool _busy = false;

  /// Открытие, за которое ролик уже досмотрен, но сервер не ответил. Повтор
  /// идёт с тем же id и без нового ролика: сервер выдаст приз один раз.
  String? _pendingOpenId;

  /// Идёт анимация открытия с этим призом; кадр — для дорожки приза.
  ChestPrize? _opening;
  int _frame = -1;
  int _openRun = 0;

  /// Название выигрыша под сундуком.
  String? _won;

  /// Открытие, приз которого сейчас разыгрывается, и выпавший подарок, который
  /// ждёт выбора под сундуком.
  String? _lastOpenId;
  ChestStashItem? _choice;
  bool _choosing = false;

  bool get _free => PlusService.instance.active;

  String? get _idleUrl => CatalogService.instance.giftArt('chest_idle')?.lgUrl;
  String? get _openUrl => CatalogService.instance.giftArt('chest_open')?.lgUrl;

  @override
  void initState() {
    super.initState();
    _choice = widget.debugChoice;
    if (_choice != null) _won = trKey('chestGiftTitle').replaceAll('{name}', GiftCatalog.byKey(_choice!.giftKey)?.title ?? '');
    if (!_free) _ad.load();
    ChestFrames.prefetch(_openUrl);
    _load();
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final st = await ChestService.instance.state();
    if (mounted && st != null) setState(() => _state = st);
  }

  List<ChestPrize> get _odds =>
      _state?.odds ?? fallbackChestOdds(withPlus: PlusService.instance.visible && !PlusService.instance.active);
  int get _left => _state?.left ?? 3;
  int get _perDay => _state?.perDay ?? 3;

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open() async {
    if (_busy || _opening != null) return;
    if (_left <= 0 && _pendingOpenId == null) {
      _snack(trKey('chestLimit'));
      return;
    }
    final openId = _pendingOpenId ?? newPbId();
    if (_pendingOpenId == null && !_free) {
      if (!_ad.isReady) {
        _ad.load();
        _snack(LocaleService.current.streakRestoreNoAd);
        return;
      }
      setState(() => _busy = true);
      final earned = await _ad.show(uid: PocketBaseService().userId ?? '');
      _ad.load();
      if (!mounted) return;
      // Ролик и сам начисляет монеты — доводим баланс до профиля.
      final adCoins = _ad.lastServerCoins;
      if (adCoins != null) widget.onCoins?.call(adCoins);
      if (!earned) {
        setState(() => _busy = false);
        return;
      }
    }
    _pendingOpenId = openId;
    setState(() => _busy = true);
    final res = await ChestService.instance.open(openId: openId, groupId: widget.groupId);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _busy = false;
        if (res.error == 'chest_limit') {
          _pendingOpenId = null;
          _state = _state == null ? null : ChestState(left: 0, perDay: _perDay, odds: _state!.odds);
        }
      });
      _snack(trKey(res.error == 'chest_limit' ? 'chestLimit' : 'chestFailed'));
      return;
    }
    _pendingOpenId = null;
    _lastOpenId = openId;
    if (res.coins != null) widget.onCoins?.call(res.coins!);
    if (res.prize?.kind == ChestPrizeKind.plus) PlusService.instance.refresh();
    setState(() {
      _opening = res.prize;
      _frame = -1;
      _openRun++;
      _won = null;
      _choice = null;
      if (_state != null && res.left != null) {
        _state = ChestState(left: res.left!, perDay: _perDay, odds: _state!.odds);
      }
    });
  }

  void _onOpenFrame(int i) {
    if (!mounted) return;
    setState(() {
      _frame = i;
      if (i >= kChestWonFrame && _won == null && _opening != null) _won = _wonText(_opening!);
    });
  }

  void _onOpenDone() {
    if (!mounted) return;
    setState(() {
      final prize = _opening;
      _won ??= prize == null ? null : _wonText(prize);
      if (prize != null && prize.kind == ChestPrizeKind.gift && _lastOpenId != null) {
        _choice = ChestStashItem(openId: _lastOpenId!, giftKey: prize.key);
      }
      _opening = null;
      _busy = false;
    });
  }

  Future<void> _decide({required bool give}) async {
    final choice = _choice;
    if (choice == null || _choosing) return;
    setState(() => _choosing = true);
    final ok = give
        ? await ChestService.instance.give(choice.openId, widget.groupId)
        : await ChestService.instance.keep(choice.openId);
    if (!mounted) return;
    setState(() {
      _choosing = false;
      if (ok) _choice = null;
    });
    _snack(trKey(!ok ? 'chestChoiceFailed' : give ? 'chestGiven' : 'chestKept'));
  }

  String _wonText(ChestPrize p) => switch (p.kind) {
    ChestPrizeKind.coins => trKey('chestWonCoins').replaceAll('{n}', '${p.amount}'),
    ChestPrizeKind.gift => trKey('chestGiftTitle').replaceAll('{name}', p.gift?.title ?? p.key),
    ChestPrizeKind.plus => trKey('chestWonPlus'),
  };

  String _title(ChestPrize p) => switch (p.kind) {
    ChestPrizeKind.coins => trKey('chestCoins').replaceAll('{n}', '${p.amount}'),
    ChestPrizeKind.gift => trKey('chestGiftTitle').replaceAll('{name}', p.gift?.title ?? p.key),
    ChestPrizeKind.plus => 'Togetherly+',
  };

  String _subtitle(ChestPrize p) => switch (p.kind) {
    ChestPrizeKind.coins => trKey('chestCoinsSub'),
    ChestPrizeKind.gift => trKey('chestGiftSub'),
    ChestPrizeKind.plus => trKey('chestPlusSub'),
  };

  String _tierName(ChestTier t) => switch (t) {
    ChestTier.common => trKey('chestTierCommon'),
    ChestTier.rare => trKey('chestTierRare'),
    ChestTier.legendary => trKey('chestTierLegendary'),
  };

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: cs.onSurface),
          title: Text(
            trKey('chestTitle'),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(context).padding.bottom + 28),
          children: [
            _hero(cs),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24),
              child: Text(
                _won ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_choice != null) _pick(cs) else _button(cs),
            const SizedBox(height: 8),
            Text(
              _choice != null
                  ? trKey('chestChoiceNote').replaceAll('{name}', _partnerName)
                  : trKey(_free ? 'chestNoteFree' : 'chestNote'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final (tier, prizes) in chestTiers(_odds)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                child: Text(
                  _tierName(tier),
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              for (final p in prizes) ...[const SizedBox(height: 6), _row(cs, p)],
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(32)),
      child: LayoutBuilder(
        builder: (context, c) {
          final side = math.min(300.0, c.maxWidth);
          final opening = _opening;
          final spot = opening != null && _frame >= 0 && _frame < kChestPrizeTrack.length
              ? kChestPrizeTrack[_frame]
              : null;
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (opening == null)
                    ChestFrames(key: const ValueKey('idle'), url: _idleUrl, still: kChestStill, side: side)
                  else
                    ChestFrames(
                      key: ValueKey('open$_openRun'),
                      url: _openUrl,
                      still: kChestStill,
                      side: side,
                      loop: false,
                      onFrame: _onOpenFrame,
                      onDone: _onOpenDone,
                    ),
                  if (opening != null && spot != null)
                    Positioned(
                      left: spot[0] * side,
                      top: spot[1] * side,
                      width: spot[2] * side,
                      height: spot[2] * side,
                      child: ChestPrizeImage(opening, side: spot[2] * side),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _button(ColorScheme cs) {
    final String label;
    if (_busy || _opening != null) {
      label = trKey('chestOpening');
    } else if (_left <= 0 && _pendingOpenId == null) {
      label = trKey('chestTomorrow');
    } else {
      // Счётчик в самой кнопке: «Открыть за рекламу 2/3».
      label = '${trKey(_free || _pendingOpenId != null ? 'chestOpenFree' : 'chestOpenAd')} $_left/$_perDay';
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _busy || _opening != null ? null : _open,
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.primary.withValues(alpha: 0.6),
          disabledForegroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  String get _partnerName {
    final n = widget.partnerName?.trim() ?? '';
    return n.isEmpty ? trKey('chestPartner') : n;
  }

  /// «Подарить» и «Оставить себе» на месте кнопки открытия.
  Widget _pick(ColorScheme cs) {
    ButtonStyle style(Color bg, Color fg) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: bg.withValues(alpha: 0.6),
      disabledForegroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w700),
    );
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _choosing ? null : () => _decide(give: true),
            style: style(cs.primary, cs.onPrimary),
            // На узком экране надпись ужимается, а не режется многоточием.
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(trKey('chestGive'), maxLines: 1)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _choosing ? null : () => _decide(give: false),
            style: style(cs.primaryContainer, cs.onPrimaryContainer),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(trKey('chestKeep'), maxLines: 1)),
          ),
        ),
      ],
    );
  }

  Widget _row(ColorScheme cs, ChestPrize p) {
    final decimal = LocaleService.instance.language.code == 'en' ? '.' : ',';
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          ChestPrizeImage(p, side: 52),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(p),
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                Text(_subtitle(p), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            chestPercent(p, _odds, decimal: decimal),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
