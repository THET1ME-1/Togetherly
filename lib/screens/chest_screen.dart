import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dict_strings.dart' show trKey;
import '../models/chest.dart';
import '../models/gift.dart';
import '../models/user_data.dart';
import '../services/catalog_service.dart';
import '../services/chest_service.dart';
import '../services/locale_service.dart';
import '../services/offline/pb_id.dart';
import '../services/plus_service.dart';
import '../services/chest_sound.dart';
import '../services/pair_jar_service.dart';
import '../services/pocketbase_service.dart';
import '../services/rewarded_ad_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/readable_text.dart';
import '../widgets/chest/chest_frames.dart';
import '../widgets/chest/chest_prize_image.dart';
import '../widgets/chest/jar_drops.dart';
import '../widgets/common/ad_result.dart';
import '../widgets/chest/chest_rays.dart';
import 'chest_prize_screen.dart';

/// Экран сундука недели по макету «Сундук недели» (26.09.2026): сверху сундук
/// крупно, под ним кнопка открытия, ниже все призы с шансами по ярусам.
///
/// Кнопка стоит сразу под сундуком, а не прилипает к низу, как на макете:
/// список призов длинный, и до кнопки пришлось бы листать (правка заказчика).
///
/// Открытие: ролик → сервер разыгрывает приз → приложение ждёт, пока реклама
/// закроется и экран снова рисуется, → сундук играет открытие один раз, приз
/// поднимается из него по дорожке [kChestPrizeTrack], на 2,0 с появляется
/// название выигрыша. Дальше сундук стоит открытым с призом до следующего
/// открытия: по макету он возвращался к покою, и после рекламы человек видел
/// уже закрытую крышку (жалоба 27.09.2026).
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
    this.userData,
    this.debugChoice,
  });

  final AppTheme theme;
  final String groupId;

  /// Имя партнёра для подсказки под кнопкой «Подарить».
  final String? partnerName;

  /// Новый баланс после монетного приза — доводится до профиля.
  final ValueChanged<int>? onCoins;

  /// Профиль: выпавшая рамка ложится во владение и надевается отсюда.
  final UserData? userData;

  /// Превью: экран сразу в состоянии «выпал подарок, ждёт выбора».
  @visibleForTesting
  final ChestStashItem? debugChoice;

  @override
  State<ChestScreen> createState() => _ChestScreenState();
}

class _ChestScreenState extends State<ChestScreen> {
  final RewardedAdService _ad = RewardedAdService(chest: true);

  ChestState? _state;
  bool _busy = false;

  /// Открытие, за которое ролик уже досмотрен, но сервер не ответил. Повтор
  /// идёт с тем же id и без нового ролика: сервер выдаст приз один раз.
  String? _pendingOpenId;

  /// Приз в открытом сундуке; кадр — для дорожки приза. После анимации
  /// сундук остаётся открытым с призом до следующего открытия: вернувшись из
  /// рекламы, человек должен увидеть, что выпало, а не закрытую крышку.
  ChestPrize? _opening;
  bool _animating = false;
  int _frame = -1;
  int _openRun = 0;

  /// Название выигрыша под сундуком.
  String? _won;

  /// Открытие, приз которого сейчас разыгрывается, и выпавший подарок, который
  /// ждёт выбора под сундуком.
  String? _lastOpenId;
  ChestStashItem? _choice;
  bool _choosing = false;

  /// Выпавшая рамка или значок, которые предлагаем надеть под сундуком.
  ChestPrize? _wearWon;

  bool get _free => PlusService.instance.active;

  String? get _idleUrl => CatalogService.instance.giftArt('chest_idle')?.lgUrl;
  String? get _openUrl => CatalogService.instance.giftArt('chest_open')?.lgUrl;

  @override
  void initState() {
    super.initState();
    _choice = widget.debugChoice;
    if (_choice != null) {
      _won = trKey('chestGiftTitle').replaceAll('{name}', GiftCatalog.byKey(_choice!.giftKey)?.title ?? '');
    }
    if (!_free) _ad.load();
    PairJarService.instance.addListener(_onJar);
    ChestSound.instance.addListener(_onJar);
    unawaited(ChestSound.instance.load());
    ChestFrames.prefetch(_openUrl);
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _onJar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PairJarService.instance.removeListener(_onJar);
    ChestSound.instance.removeListener(_onJar);
    unawaited(ChestSound.instance.stop());
    _clock?.cancel();
    _ad.dispose();
    super.dispose();
  }

  /// Часы отсчёта на кнопке, когда открытия на сегодня кончились. Дневной
  /// лимит сервер считает по местному времени, поэтому отсчёт идёт до полуночи
  /// телефона; в полночь остаток перечитывается.
  Timer? _clock;

  void _tick() {
    if (!mounted || _left > 0 || _pendingOpenId != null) return;
    if (_untilMidnight() <= Duration.zero) {
      _load();
    } else {
      setState(() {});
    }
  }

  Duration _untilMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1).difference(now);
  }

  String _countdown() {
    final d = _untilMidnight();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _load() async {
    final st = await ChestService.instance.state(groupId: widget.groupId);
    if (mounted && st != null) setState(() => _state = st);
  }

  List<ChestPrize> get _odds =>
      _state?.odds ?? fallbackChestOdds(withPlus: PlusService.instance.visible && !PlusService.instance.active);
  int get _left => _state?.left ?? 3;
  int get _perDay => _state?.perDay ?? 3;

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Открытия из копилки пары, что ждут меня.
  int get _jarBonus => PairJarService.instance.jar?.bonus ?? 0;

  /// Открытие из копилки после обрыва связи повторяется тем же видом.
  bool _pendingFromJar = false;

  Future<void> _open({bool fromJar = false}) async {
    if (_busy || _animating) return;
    if (_pendingOpenId != null) fromJar = _pendingFromJar;
    if (fromJar && _jarBonus <= 0 && _pendingOpenId == null) return;
    if (!fromJar && _left <= 0 && _pendingOpenId == null) {
      _snack(trKey('chestLimit'));
      return;
    }
    final openId = _pendingOpenId ?? newPbId();
    // Плеер звука готовится, пока идут реклама и розыгрыш.
    ChestSound.instance.prepare();
    var adShown = false;
    if (_pendingOpenId == null && !_free && !fromJar) {
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
        await showAdNotEarned(context);
        return;
      }
      adShown = true;
    }
    _pendingOpenId = openId;
    _pendingFromJar = fromJar;
    setState(() => _busy = true);
    // Приз разыгрывается, пока закрывается реклама и докачивается открытие.
    final request = ChestService.instance.open(openId: openId, groupId: widget.groupId, fromJar: fromJar);
    if (adShown) await untilAppVisible();
    await ChestFrames.prefetch(_openUrl);
    final res = await request;
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _busy = false;
        if (res.error == 'no_bonus') {
          _pendingOpenId = null;
          PairJarService.instance.setBonus(0);
        }
        if (res.error == 'chest_limit') {
          _pendingOpenId = null;
          _state = _state == null
              ? null
              : ChestState(left: 0, perDay: _perDay, odds: _state!.odds, untilRare: _state!.untilRare, jar: _state!.jar);
        }
      });
      _snack(trKey(res.error == 'chest_limit' ? 'chestLimit' : 'chestFailed'));
      return;
    }
    _pendingOpenId = null;
    _pendingFromJar = false;
    _lastOpenId = openId;
    if (res.coins != null) widget.onCoins?.call(res.coins!);
    if (res.prize?.kind == ChestPrizeKind.plus) PlusService.instance.refresh();
    // Выпавшая рамка уже во владении на сервере — кладём её и в профиль,
    // иначе «Надеть» упрётся в «не твоя» до следующей синхронизации.
    if (res.ownedFeatures != null) widget.userData?.applyOwnedFeatures(res.ownedFeatures!);
    if (res.ownedIcons != null) widget.userData?.applyOwnedIcons(res.ownedIcons!);
    if (res.plusTrialUntil != null) PlusService.instance.setTrialUntil(res.plusTrialUntil!);
    setState(() {
      _opening = res.prize;
      _animating = true;
      _soundStarted = false;
      _frame = -1;
      _openRun++;
      _won = null;
      _choice = null;
      _wearWon = null;
      if (_state != null && res.left != null) {
        _state = ChestState(
          left: res.left!,
          perDay: _perDay,
          odds: _state!.odds,
          untilRare: res.untilRare ?? _state!.untilRare,
          jar: PairJarService.instance.jar,
        );
      }
    });
  }

  /// Звук открытия уже пошёл для этого прогона анимации.
  bool _soundStarted = false;

  void _onOpenFrame(int i) {
    if (!mounted) return;
    if (!_soundStarted) {
      _soundStarted = true;
      ChestSound.instance.start(i);
    }
    ChestSound.instance.haptic(_frame, i);
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
      if (prize != null &&
          (prize.kind == ChestPrizeKind.frame || prize.kind == ChestPrizeKind.badge) &&
          widget.userData != null) {
        _wearWon = prize;
      }
      _animating = false;
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
    _snack(
      trKey(
        !ok
            ? 'chestChoiceFailed'
            : give
            ? 'chestGiven'
            : 'chestKept',
      ),
    );
  }

  String _frameName(ChestPrize p) => p.frame?.name ?? p.frameKey ?? p.key;
  String _badgeName(ChestPrize p) => p.badge?.name ?? p.key;

  String _wonText(ChestPrize p) => switch (p.kind) {
    ChestPrizeKind.coins => trKey('chestWonCoins').replaceAll('{n}', '${p.amount}'),
    ChestPrizeKind.gift => trKey('chestGiftTitle').replaceAll('{name}', p.gift?.title ?? p.key),
    ChestPrizeKind.plus => trKey('chestWonPlus'),
    ChestPrizeKind.frame => trKey('chestFrameTitle').replaceAll('{name}', _frameName(p)),
    ChestPrizeKind.badge => trKey('chestBadgeTitle').replaceAll('{name}', _badgeName(p)),
    ChestPrizeKind.plusTrial => trKey('chestPlusTrialTitle'),
  };

  String _title(ChestPrize p) => switch (p.kind) {
    ChestPrizeKind.coins => trKey('chestCoins').replaceAll('{n}', '${p.amount}'),
    ChestPrizeKind.gift => trKey('chestGiftTitle').replaceAll('{name}', p.gift?.title ?? p.key),
    ChestPrizeKind.plus => 'Togetherly+',
    ChestPrizeKind.frame => trKey('chestFrameTitle').replaceAll('{name}', _frameName(p)),
    ChestPrizeKind.badge => trKey('chestBadgeTitle').replaceAll('{name}', _badgeName(p)),
    ChestPrizeKind.plusTrial => trKey('chestPlusTrialTitle'),
  };

  String _subtitle(ChestPrize p) => switch (p.kind) {
    ChestPrizeKind.coins => trKey('chestCoinsSub'),
    ChestPrizeKind.gift => trKey('chestGiftSub'),
    ChestPrizeKind.plus => trKey('chestPlusSub'),
    ChestPrizeKind.frame => trKey('chestFrameSub'),
    ChestPrizeKind.badge => trKey('chestBadgeSub'),
    ChestPrizeKind.plusTrial => trKey('chestPlusTrialSub'),
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
          actions: [
            IconButton(
              tooltip: trKey(ChestSound.instance.enabled ? 'chestSoundOff' : 'chestSoundOn'),
              icon: Icon(ChestSound.instance.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded),
              onPressed: () => ChestSound.instance.setEnabled(!ChestSound.instance.enabled),
            ),
            const SizedBox(width: 4),
          ],
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
            if (_choice != null)
              _pick(cs)
            else if (_wearWon != null)
              _wear(cs)
            else ...[
              if (_jarBonus > 0 || _pendingFromJar) ...[_jarButton(cs), const SizedBox(height: 8)],
              _button(cs),
            ],
            if (_choice == null && _state?.untilRare != null) ...[
              const SizedBox(height: 8),
              _pity(cs, _state!.untilRare!),
            ],
            const SizedBox(height: 8),
            Text(
              _choice != null
                  ? trKey('chestChoiceNote').replaceAll('{name}', _partnerName)
                  : trKey(_free ? 'chestNoteFree' : 'chestNote'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
            ),
            if (PairJarService.instance.jar != null) ...[const SizedBox(height: 10), _jarRow(cs)],
            const SizedBox(height: 8),
            for (final (tier, prizes) in chestSections(_odds)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                child: Text(
                  tier == null ? trKey('chestTierTop') : _tierName(tier),
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
    // Фон блока — светлые лучи (макет «Фон за сундуком»), рисунок поверх.
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Stack(
        children: [
          Positioned.fill(child: ChestRays(scheme: cs)),
          Padding(padding: const EdgeInsets.all(6), child: _heroArt()),
        ],
      ),
    );
  }

  Widget _heroArt() {
    return LayoutBuilder(
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
    );
  }

  Widget _button(ColorScheme cs) {
    final String label;
    final out = _left <= 0 && _pendingOpenId == null;
    if (_busy || _animating) {
      label = trKey('chestOpening');
    } else if (out) {
      // Открытия кончились — вместо кнопки отсчёт до полуночи.
      label = trKey('chestCountdown').replaceAll('{t}', _countdown());
    } else {
      // Счётчик в самой кнопке: «Открыть за рекламу 2/3».
      label = '${trKey(_free || _pendingOpenId != null ? 'chestOpenFree' : 'chestOpenAd')} $_left/$_perDay';
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _busy || _animating || out ? null : _open,
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.primary.withValues(alpha: 0.6),
          disabledForegroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: const StadiumBorder(),
          // Цифры одной ширины: иначе надпись с отсчётом дёргается каждую секунду.
          textStyle: const TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        child: Text(label),
      ),
    );
  }

  /// Открыть из копилки пары: без ролика и сверх трёх в день.
  Widget _jarButton(ColorScheme cs) {
    final busy = _busy || _animating;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : () => _open(fromJar: true),
        style: FilledButton.styleFrom(
          backgroundColor: cs.primaryContainer,
          foregroundColor: readableTextOn(cs.primaryContainer),
          disabledBackgroundColor: cs.primaryContainer.withValues(alpha: 0.6),
          disabledForegroundColor: readableTextOn(cs.primaryContainer),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            busy ? trKey('chestOpening') : trKey('jarOpen').replaceAll('{n}', '${_jarBonus > 0 ? _jarBonus : 1}'),
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  /// Копилка пары под кнопкой: капли и как она работает.
  Widget _jarRow(ColorScheme cs) {
    final jar = PairJarService.instance.jar!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trKey('jarTitle'),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            jar.capped ? trKey('jarCapped') : trKey('jarHint'),
            style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          JarDrops(jar: jar, mine: cs.primary, partner: cs.primaryContainer, dropHeight: 26, gap: 2),
        ],
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

  /// Гарантия редкого приза: сколько открытий подряд уже прошло без него.
  Widget _pity(ColorScheme cs, int untilRare) {
    final next = untilRare <= 1;
    final text = next
        ? trKey('chestPityNext')
        : trKey('chestPity').replaceAll('{n}', '${kChestPity - untilRare}').replaceAll('{m}', '$kChestPity');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(next ? Icons.auto_awesome_rounded : Icons.shield_moon_rounded, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
        ),
      ],
    );
  }

  /// «Надеть» и «Позже» под выпавшей рамкой или значком. «Позже» возвращает
  /// кнопку открытия: приз уже твой и ждёт в магазине.
  Widget _wear(ColorScheme cs) {
    ButtonStyle style(Color bg, Color fg) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w700),
    );
    final prize = _wearWon!;
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () async {
              final ud = widget.userData;
              if (ud == null) return;
              if (prize.kind == ChestPrizeKind.badge) {
                await ud.setBadgeIcon(prize.badge?.id);
              } else {
                await ud.setFrame(prize.frameKey);
              }
              if (!mounted) return;
              setState(() => _wearWon = null);
              _snack(trKey(prize.kind == ChestPrizeKind.badge ? 'chestBadgeWorn' : 'chestFrameWorn'));
            },
            style: style(cs.primary, cs.onPrimary),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(trKey('shopWear'), maxLines: 1)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => setState(() => _wearWon = null),
            style: style(cs.primaryContainer, cs.onPrimaryContainer),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(trKey('chestLater'), maxLines: 1)),
          ),
        ),
      ],
    );
  }

  String get _decimal => LocaleService.instance.language.code == 'en' ? '.' : ',';

  /// Приз во весь экран: крупно и живым, с названием и шансом.
  void _preview(ChestPrize p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/chest/prize'),
        builder: (_) => ChestPrizeScreen(
          theme: widget.theme,
          prize: p,
          title: _title(p),
          subtitle: _subtitle(p),
          tier: _tierName(p.tier),
          chance: chestPercent(p, _odds, decimal: _decimal),
        ),
      ),
    );
  }

  Widget _row(ColorScheme cs, ChestPrize p) {
    final decimal = _decimal;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _preview(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
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
        ),
      ),
    );
  }
}
