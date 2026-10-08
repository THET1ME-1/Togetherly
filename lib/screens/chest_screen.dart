import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dict_strings.dart' show trKey;
import '../models/chest.dart';
import '../models/chest_pending.dart';
import '../models/gift.dart';
import '../models/user_data.dart';
import '../services/catalog_service.dart';
import '../services/chest_pending_store.dart';
import '../services/chest_service.dart';
import '../services/chest_telemetry.dart';
import '../services/locale_service.dart';
import '../services/offline/media_view_cache.dart';
import '../services/offline/pb_id.dart';
import '../services/plus_service.dart';
import '../services/chest_sound.dart';
import '../services/pair_jar_service.dart';
import '../services/pocketbase_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/season_music.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/readable_text.dart';
import '../widgets/chest/chest_frames.dart';
import '../widgets/chest/chest_prize_image.dart';
import '../widgets/chest/jar_drops.dart';
import '../widgets/common/ad_result.dart';
import '../widgets/common/badge_image.dart';
import '../widgets/common/gift_image.dart';
import '../widgets/chest/chest_rays.dart';
import '../widgets/chest/season_glitch.dart';
import 'chest_prize_screen.dart';
import 'chest_share_screen.dart';

/// Экран сундука по макету «Сундук на Хэллоуин», вариант Б (08.10.2026):
/// сундуки листаются вбок, как галерея, карточка во всю ширину, соседа не
/// видно. Первым стоит обычный сундук недели, за ним сезонные — их описание,
/// файлы и даты приходят с сервера (`ChestState.seasons`), приложение под
/// сезон своего кода не держит.
///
/// Переход на сезонный сундук закрывает экран занавесом тьмы (потёки, глаза,
/// стая мышей), под ним страница мгновенно меняет цвета на ночные, занавес
/// уходит, на карточке бьёт молния. Обратно — дневной облачный занавес,
/// окрашенный в цвет страницы темы. На странице сезона играет музыка сезона.
///
/// Открытие: ролик → сервер разыгрывает приз → приложение ждёт, пока реклама
/// закроется и экран снова рисуется, → сундук играет открытие один раз, приз
/// поднимается по дорожке своего сундука, на 2,0 с появляется название
/// выигрыша. Сундук остаётся открытым с призом до следующего открытия.
///
/// Выпал подарок — на месте кнопки открытия встают «Подарить» и «Оставить
/// себе». Ушёл с экрана, не выбрав, — подарок ждёт в ленте «Из сундука».
class ChestScreen extends StatefulWidget {
  const ChestScreen({
    super.key,
    required this.theme,
    required this.groupId,
    this.partnerName,
    this.onCoins,
    this.userData,
    this.debugChoice,
    this.debugSeasons,
    this.debugPage = 0,
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

  /// Превью и тесты: сезонные сундуки без сервера.
  @visibleForTesting
  final List<SeasonChest>? debugSeasons;

  /// Превью: с какой страницы ленты открыть экран.
  @visibleForTesting
  final int debugPage;

  @override
  State<ChestScreen> createState() => _ChestScreenState();
}

/// Всё, что экран помнит про один сундук ленты.
class _Slot {
  _Slot(this.season);

  /// null — обычный сундук недели.
  final SeasonChest? season;

  ChestState? state;

  /// Открытие, за которое ролик уже досмотрен, но сервер не ответил. Повтор
  /// идёт с тем же id и без нового ролика: сервер выдаст приз один раз.
  String? pendingOpenId;
  bool pendingFromJar = false;

  /// Приз в открытом сундуке; кадр — для дорожки приза.
  ChestPrize? opening;
  bool animating = false;
  int frame = -1;
  int openRun = 0;

  /// Название выигрыша под сундуком.
  String? won;
  String? lastOpenId;
  ChestStashItem? choice;
  ChestPrize? wearWon;
  bool soundStarted = false;

  /// Сбой кнопки «Открыть 3/3», если сезон его просит.
  SeasonGlitch? glitch;

  bool get isMain => season == null;
  String? get chest => season?.key;

  /// Ключ недосмотренного открытия на диске: у каждого сундука свой.
  String pendingKey(String groupId) => season == null ? groupId : '$groupId|${season!.key}';

  String? get idleUrl => season == null ? CatalogService.instance.giftArt('chest_idle')?.lgUrl : season!.file('idle');
  String? get openUrl => season == null ? CatalogService.instance.giftArt('chest_open')?.lgUrl : season!.file('open');

  /// Дорожка приза в кадрах открытия: у сезонного своя, с сервера.
  List<List<double>?> get track {
    final t = season?.track;
    return t == null || t.isEmpty ? kChestPrizeTrack : t;
  }

  double? get trackPeak => season == null || season!.track.isEmpty ? null : ChestPrizeFlight.trackPeak(track);
  int get frameMs => season?.trackFrameMs ?? kChestFrameMs;
  int get wonFrame => season == null ? kChestWonFrame : season!.wonAtMs ~/ frameMs;
  int get lockFrame => season == null ? ChestSound.lockFrame : season!.lockAtMs ~/ frameMs;
  int? get flashFrame => season?.flashColor == null ? null : season!.flashAtMs ~/ frameMs;

  int get left => state?.left ?? season?.perDay ?? 3;
  int get perDay => state?.perDay ?? season?.perDay ?? 3;
}

class _ChestScreenState extends State<ChestScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final RewardedAdService _ad = RewardedAdService(chest: true);

  late final List<_Slot> _slots = [_Slot(null)];
  late final PageController _pager = PageController(initialPage: widget.debugPage);

  /// Страница ленты под пальцем и сундук, чьи цвета и данные сейчас на
  /// экране. Они расходятся, пока идёт занавес: страница меняется под ним.
  int _page = 0;
  int _shown = 0;

  bool _busy = false;
  bool _choosing = false;

  /// Занавес смены страницы: к какой странице идём и закрыт ли уже экран.
  _Curtain? _curtain;

  /// Вспышка молнии на карточке сезона.
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  int _flashSlot = -1;

  _Slot get _s => _slots[_shown];

  bool get _free => PlusService.instance.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final debugSeasons = widget.debugSeasons;
    if (debugSeasons != null) _applySeasons(debugSeasons);
    if (widget.debugPage < _slots.length) _page = _shown = widget.debugPage;
    _syncGlitch();
    final main = _slots.first;
    main.choice = widget.debugChoice;
    if (main.choice != null) {
      main.won = trKey('chestGiftTitle').replaceAll('{name}', GiftCatalog.byKey(main.choice!.giftKey)?.title ?? '');
    }
    if (!_free) _ad.load();
    PairJarService.instance.addListener(_onJar);
    ChestSound.instance.addListener(_onJar);
    unawaited(ChestSound.instance.load());
    ChestFrames.prefetch(main.openUrl);
    _load();
    _restorePending(main);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (!_s.isMain) _startMusic(_s);
  }

  void _onJar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PairJarService.instance.removeListener(_onJar);
    ChestSound.instance.removeListener(_onJar);
    unawaited(ChestSound.instance.stop());
    unawaited(SeasonMusic.instance.release());
    for (final s in _slots) {
      s.glitch?.dispose();
    }
    _clock?.cancel();
    _ad.dispose();
    _pager.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Свёрнутое приложение не играет музыку сезона, а вернувшееся — снова.
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!_s.isMain) _startMusic(_s);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _foreground = false;
      unawaited(SeasonMusic.instance.stop());
    }
    _syncGlitch();
  }

  /// Часы отсчёта на кнопке, когда открытия на сегодня кончились. Дневной
  /// лимит сервер считает по местному времени, поэтому отсчёт идёт до полуночи
  /// телефона; в полночь остаток перечитывается.
  Timer? _clock;

  void _tick() {
    if (!mounted || _s.left > 0 || _s.pendingOpenId != null) return;
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

  /// Ролик досмотрен в прошлый раз, а сундук так и не открылся: кнопка
  /// открывает его без рекламы.
  Future<void> _restorePending(_Slot slot) async {
    final item = await ChestPendingStore.read(slot.pendingKey(widget.groupId));
    if (item == null || !mounted || slot.pendingOpenId != null || _busy) return;
    ChestTelemetry.step(
      item.openId,
      'pending:restored',
      data: {'jar': item.fromJar, 'age_s': DateTime.now().difference(item.at).inSeconds, 'chest': ?slot.chest},
    );
    setState(() {
      slot.pendingOpenId = item.openId;
      slot.pendingFromJar = item.fromJar;
    });
  }

  Future<void> _load() async {
    final st = await ChestService.instance.state(groupId: widget.groupId);
    if (!mounted || st == null) return;
    setState(() {
      _slots.first.state = st;
      if (widget.debugSeasons == null) _applySeasons(st.seasons);
    });
    for (final slot in _slots.skip(1)) {
      unawaited(_loadSeason(slot));
    }
  }

  Future<void> _loadSeason(_Slot slot) async {
    final st = await ChestService.instance.state(groupId: widget.groupId, chest: slot.chest);
    if (mounted && st != null) setState(() => slot.state = st);
  }

  /// Сезонные сундуки с сервера: новые встают в ленту, кончившиеся уходят.
  /// Сундук, который сейчас на экране, не выдёргиваем из-под пальца — он
  /// уйдёт при следующем заходе.
  void _applySeasons(List<SeasonChest> seasons) {
    final keep = <_Slot>[];
    for (final s in seasons) {
      final old = _slots.skip(1).where((x) => x.chest == s.key).firstOrNull;
      final slot = old ?? _Slot(s);
      keep.add(slot);
      if (old == null) {
        _restorePending(slot);
        // Занавес, карточка и открытие качаются заранее: переход и открытие
        // должны начаться сразу, без ожидания сети.
        for (final name in const ['curtain_night', 'curtain_day', 'card_back', 'card_front', 'idle', 'open']) {
          ChestFrames.prefetch(s.file(name));
        }
        unawaited(SeasonMusic.instance.prepareThunder(s.file('thunder')));
        final spec = s.glitch;
        if (spec != null) {
          unawaited(SeasonMusic.instance.prepareCrackle(s.file('static')));
          final glitch = SeasonGlitch(spec);
          // Срывается только кнопка, которую сейчас можно нажать.
          glitch.canRun = () =>
              mounted &&
              identical(_s, slot) &&
              !_busy &&
              !slot.animating &&
              _curtain == null &&
              slot.left > 0 &&
              slot.choice == null &&
              slot.wearWon == null;
          glitch.onPeak = () {
            HapticFeedback.heavyImpact();
            unawaited(SeasonMusic.instance.crackle(s.file('static')));
          };
          slot.glitch = glitch;
        }
      }
    }
    final current = _s;
    if (!current.isMain && !keep.contains(current)) keep.insert(math.min(_shown - 1, keep.length), current);
    for (final gone in _slots.skip(1)) {
      if (!keep.contains(gone)) gone.glitch?.dispose();
    }
    _slots
      ..removeRange(1, _slots.length)
      ..addAll(keep);
    _shown = _slots.indexOf(current);
    _page = _page.clamp(0, _slots.length - 1);
    _syncGlitch();
  }

  bool _foreground = true;

  /// Сбой кнопки живёт только у сундука на экране и пока приложение видно.
  void _syncGlitch() {
    for (var i = 0; i < _slots.length; i++) {
      final g = _slots[i].glitch;
      if (g == null) continue;
      if (i == _shown && _foreground) {
        g.start();
      } else if (g.scheduled || g.phase != GlitchPhase.calm) {
        g.stop();
      }
    }
  }

  List<ChestPrize> get _odds {
    final st = _s.state;
    if (st != null) return st.odds;
    if (!_s.isMain) return const [];
    return fallbackChestOdds(withPlus: PlusService.instance.visible && !PlusService.instance.active);
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Открытия из копилки пары, что ждут меня.
  int get _jarBonus => PairJarService.instance.jar?.bonus ?? 0;

  bool get _anyAnimating => _slots.any((s) => s.animating);

  Future<void> _open({bool fromJar = false}) async {
    final slot = _s;
    if (_busy || slot.animating || _curtain != null) return;
    if (slot.pendingOpenId != null) fromJar = slot.pendingFromJar;
    if (fromJar && _jarBonus <= 0 && slot.pendingOpenId == null) return;
    if (!fromJar && slot.left <= 0 && slot.pendingOpenId == null) {
      _snack(trKey('chestLimit'));
      return;
    }
    final openId = slot.pendingOpenId ?? newPbId();
    final storeKey = slot.pendingKey(widget.groupId);
    final total = Stopwatch()..start();
    ChestTelemetry.step(
      openId,
      'tap',
      data: {'pending': slot.pendingOpenId != null, 'jar': fromJar, 'free': _free, 'chest': ?slot.chest},
    );
    // Плеер звука готовится, пока идут реклама и розыгрыш.
    if (slot.isMain) ChestSound.instance.prepare();
    var adShown = false;
    if (slot.pendingOpenId == null && !_free && !fromJar) {
      if (!_ad.isReady) {
        _ad.load();
        _snack(LocaleService.current.streakRestoreNoAd);
        return;
      }
      setState(() => _busy = true);
      // Реклама глушит музыку сезона сама, но плеер оставался бы «играющим»
      // под ней — останавливаем честно и включаем после.
      if (!slot.isMain) unawaited(SeasonMusic.instance.stop());
      final earned = await _ad.show(uid: PocketBaseService().userId ?? '', chestOpenId: openId);
      _ad.load();
      ChestTelemetry.step(
        openId,
        'ad:closed',
        data: {
          'earned': earned,
          'away_s': _ad.lastSecondsAway,
          'granted': _ad.lastRewardGranted,
          'grant_timed_out': _ad.lastGrantTimedOut,
        },
      );
      // Досмотренный ролик ложится на диск ДО всего остального: уйдёт человек
      // с экрана или приложение выгрузят — открытие дойдёт без новой рекламы.
      if (earned) {
        unawaited(ChestPendingStore.write(storeKey, ChestPending(openId: openId, fromJar: false, at: DateTime.now())));
      }
      if (!mounted) return;
      if (!slot.isMain && identical(_s, slot)) _startMusic(slot);
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
    if (slot.pendingOpenId == null && fromJar) {
      unawaited(ChestPendingStore.write(storeKey, ChestPending(openId: openId, fromJar: true, at: DateTime.now())));
    }
    slot.pendingOpenId = openId;
    slot.pendingFromJar = fromJar;
    setState(() => _busy = true);
    // Приз разыгрывается, пока закрывается реклама и докачивается открытие.
    final request = ChestService.instance.open(
      openId: openId,
      groupId: widget.groupId,
      fromJar: fromJar,
      chest: slot.chest,
    );
    if (adShown) await untilAppVisible();
    await ChestFrames.prefetch(slot.openUrl);
    if (!ChestFrames.isReady(slot.openUrl)) ChestTelemetry.step(openId, 'anim:skip');
    final res = await request;
    // Итог на диске фиксируется и тогда, когда экран уже закрыт: иначе
    // следующий заход предложил бы открыть то, что уже открылось.
    final settled =
        res.ok ||
        res.error == 'no_bonus' ||
        res.error == 'chest_limit' ||
        res.error == 'conflict' ||
        res.error == 'season_over';
    if (settled) unawaited(ChestPendingStore.clear(storeKey));
    if (!res.ok && res.error != 'chest_limit' && res.error != 'no_bonus') {
      ChestTelemetry.failure(
        openId,
        'open',
        res.error ?? 'unknown',
        data: {
          'ms': total.elapsedMilliseconds,
          'ad': adShown,
          'jar': fromJar,
          'grant_timed_out': adShown && _ad.lastGrantTimedOut,
          'away_s': adShown ? _ad.lastSecondsAway : 0,
          'chest': ?slot.chest,
        },
      );
    } else if (res.ok && total.elapsed > const Duration(seconds: 20)) {
      // Открылось, но так долго, что человек мог решить «не работает».
      ChestTelemetry.failure(openId, 'open', 'slow', data: {'ms': total.elapsedMilliseconds, 'ad': adShown});
    }
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _busy = false;
        if (res.error == 'no_bonus') {
          slot.pendingOpenId = null;
          PairJarService.instance.setBonus(0);
        }
        if (res.error == 'chest_limit') {
          slot.pendingOpenId = null;
          slot.state = slot.state?.afterOpen(left: 0, jar: slot.state!.jar);
        }
        if (res.error == 'season_over') slot.pendingOpenId = null;
      });
      _snack(
        trKey(switch (res.error) {
          'chest_limit' => 'chestLimit',
          'season_over' => 'chestSeasonOver',
          _ => 'chestFailed',
        }),
      );
      if (res.error == 'season_over') _load();
      return;
    }
    slot.pendingOpenId = null;
    slot.pendingFromJar = false;
    slot.lastOpenId = openId;
    if (res.coins != null) widget.onCoins?.call(res.coins!);
    if (res.prize?.kind == ChestPrizeKind.plus) PlusService.instance.refresh();
    // Выпавшая рамка уже во владении на сервере — кладём её и в профиль,
    // иначе «Надеть» упрётся в «не твоя» до следующей синхронизации.
    if (res.ownedFeatures != null) widget.userData?.applyOwnedFeatures(res.ownedFeatures!);
    if (res.ownedIcons != null) widget.userData?.applyOwnedIcons(res.ownedIcons!);
    if (res.plusTrialUntil != null) PlusService.instance.setTrialUntil(res.plusTrialUntil!);
    setState(() {
      slot.opening = res.prize;
      slot.animating = true;
      slot.soundStarted = false;
      slot.frame = -1;
      slot.openRun++;
      slot.won = null;
      slot.choice = null;
      slot.wearWon = null;
      if (slot.state != null && res.left != null) {
        slot.state = slot.state!.afterOpen(
          left: res.left!,
          untilRare: res.untilRare,
          jar: PairJarService.instance.jar,
          prize: res.prize,
        );
      }
    });
  }

  void _onOpenFrame(_Slot slot, int i) {
    if (!mounted) return;
    final from = slot.frame;
    if (slot.isMain) {
      if (!slot.soundStarted) {
        slot.soundStarted = true;
        ChestSound.instance.start(i);
      }
      ChestSound.instance.haptic(from, i);
    } else {
      // У сезонного сундука вместо фанфары гром на щелчке замка, музыка
      // страницы играет дальше.
      if (from < slot.lockFrame && i >= slot.lockFrame) {
        HapticFeedback.lightImpact();
        unawaited(SeasonMusic.instance.thunder(slot.season!.file('thunder')));
      }
      final flashAt = slot.flashFrame;
      if (flashAt != null && from < flashAt && i >= flashAt) _bolt(_slots.indexOf(slot));
      if (from < slot.wonFrame && i >= slot.wonFrame) HapticFeedback.mediumImpact();
    }
    setState(() {
      slot.frame = i;
      if (i >= slot.wonFrame && slot.won == null && slot.opening != null) slot.won = _wonText(slot.opening!);
    });
  }

  void _onOpenDone(_Slot slot) {
    if (!mounted) return;
    setState(() {
      final prize = slot.opening;
      slot.won ??= prize == null ? null : _wonText(prize);
      if (prize != null && prize.kind == ChestPrizeKind.gift && slot.lastOpenId != null) {
        slot.choice = ChestStashItem(openId: slot.lastOpenId!, giftKey: prize.key);
      }
      if (prize != null &&
          (prize.kind == ChestPrizeKind.frame || prize.kind == ChestPrizeKind.badge) &&
          widget.userData != null) {
        slot.wearWon = prize;
      }
      slot.animating = false;
      _busy = false;
    });
  }

  Future<void> _decide({required bool give}) async {
    final slot = _s;
    final choice = slot.choice;
    if (choice == null || _choosing) return;
    setState(() => _choosing = true);
    final ok = give
        ? await ChestService.instance.give(choice.openId, widget.groupId)
        : await ChestService.instance.keep(choice.openId);
    if (!mounted) return;
    setState(() {
      _choosing = false;
      if (ok) slot.choice = null;
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

  // ── смена страницы ──────────────────────────────────────────────────────

  void _onPage(int i) {
    _page = i;
    _swap(i);
  }

  /// Занавес закрывает экран, под ним страница мгновенно меняет цвета и
  /// данные, занавес уходит и открывает уже ночной (или дневной) экран.
  void _swap(int to) {
    if (_curtain != null || to == _shown || to >= _slots.length) return;
    final from = _slots[_shown], target = _slots[to];
    final toNight = !target.isMain;
    // Ночь идёт занавесом сезона, куда идём; день — того, откуда уходим.
    final source = toNight ? target.season! : from.season!;
    final url = source.file(toNight ? 'curtain_night' : 'curtain_day');
    if (toNight) {
      _startMusic(target);
    } else {
      unawaited(SeasonMusic.instance.stop());
    }
    if (MediaQuery.of(context).disableAnimations || !ChestFrames.isReady(url)) {
      // Без анимаций или без файла — страница меняется сразу.
      setState(() => _shown = to);
      _syncGlitch();
      if (toNight) _bolt(to);
      return;
    }
    setState(() {
      _curtain = _Curtain(
        to: to,
        url: url!,
        night: toNight,
        coverMs: toNight ? source.curtainNightCoverMs : source.curtainDayCoverMs,
      );
    });
  }

  void _curtainAt(Duration pos) {
    final c = _curtain;
    if (c == null || c.covered || pos.inMilliseconds < c.coverMs) return;
    c.covered = true;
    setState(() => _shown = c.to);
    _syncGlitch();
  }

  void _curtainDone() {
    final c = _curtain;
    if (c == null || !mounted) return;
    setState(() {
      _curtain = null;
      _shown = c.to;
    });
    _syncGlitch();
    if (c.night) _bolt(c.to);
    // Пока шёл занавес, человек мог долистать дальше.
    if (_page != _shown) _swap(_page);
  }

  void _startMusic(_Slot slot) {
    // Мелодии сезона сменяют друг друга плавным переходом, первая — по умолчанию.
    final s = slot.season;
    unawaited(SeasonMusic.instance.play(s?.musicUrls ?? const [], fadeMs: s?.musicFadeMs ?? 3500));
  }

  /// Молния на карточке сезона: вспышка и гром.
  void _bolt(int slotIndex) {
    if (slotIndex <= 0 || slotIndex >= _slots.length) return;
    final season = _slots[slotIndex].season!;
    if (season.flashColor == null) return;
    setState(() => _flashSlot = slotIndex);
    _flash.forward(from: 0);
    unawaited(SeasonMusic.instance.thunder(season.file('thunder')));
  }

  // ── тексты ──────────────────────────────────────────────────────────────

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

  String get _lang => LocaleService.instance.language.code;

  /// «Хэллоуин · до 1 ноября»: день, с которого сундука уже нет, как на макете.
  String _seasonTag(SeasonChest s) {
    final until = DateTime.tryParse(s.until);
    return s.tagIn(_lang, until == null ? '' : LocaleService.current.dayLogDate(until));
  }

  // ── вёрстка ─────────────────────────────────────────────────────────────

  /// Цвета страницы: ночные у сезонного сундука, темы пары у обычного.
  ColorScheme _schemeFor(_Slot slot, ColorScheme base) {
    final p = slot.season?.palette;
    if (p == null) return base;
    final dark = ThemeData.estimateBrightnessForColor(p.page) == Brightness.dark;
    return base.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: p.page,
      onSurface: p.ink,
      onSurfaceVariant: p.ink2,
      primary: p.fill,
      onPrimary: p.onFill,
      primaryContainer: p.surface,
      onPrimaryContainer: p.ink,
      secondaryContainer: p.surface,
      onSecondaryContainer: p.ink,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surface,
      outline: p.line,
      outlineVariant: p.line,
      inverseSurface: p.ink,
      onInverseSurface: p.page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = ProfileTheme.schemeFor(widget.theme);
    final cs = _schemeFor(_s, base);
    final slot = _s;
    final curtain = _curtain;
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Theme(
          data: ProfileTheme.data(cs),
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: cs.onSurface),
              systemOverlayStyle: cs.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
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
            body: _shake(
              slot,
              ListView(
                padding: EdgeInsets.fromLTRB(0, 4, 0, MediaQuery.of(context).padding.bottom + 28),
                children: [
                  _pagerView(base),
                  if (_slots.length > 1) _dots(cs),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _content(cs, slot)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (curtain != null) Positioned.fill(child: IgnorePointer(child: _curtainLayer(curtain, base, size))),
      ],
    );
  }

  Widget _curtainLayer(_Curtain c, ColorScheme base, Size size) {
    Widget frames = ChestFrames(
      key: ValueKey('curtain${c.to}${c.night}'),
      url: c.url,
      still: null,
      side: size.width,
      height: size.height,
      fit: BoxFit.cover,
      loop: false,
      holdLast: true,
      onPosition: _curtainAt,
      onDone: _curtainDone,
    );
    // Дневной занавес нарисован белым: красим его в цвет страницы темы.
    if (!c.night) {
      frames = ColorFiltered(colorFilter: ColorFilter.mode(base.surface, BlendMode.srcIn), child: frames);
    }
    return frames;
  }

  /// Лента сундуков: карточка во всю ширину, соседа не видно, между ними
  /// зазор 40.
  Widget _pagerView(ColorScheme base) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - 32;
        final aspect = _slots.length > 1 ? (_slots[1].season?.cardAspect ?? 600 / 516) : 600 / 516;
        final h = w / aspect;
        final locked = _busy || _anyAnimating || _curtain != null;
        return SizedBox(
          height: h,
          child: PageView.builder(
            controller: _pager,
            itemCount: _slots.length,
            onPageChanged: _onPage,
            physics: locked ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            itemBuilder: (context, i) =>
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _card(i, w, h, base)),
          ),
        );
      },
    );
  }

  void _goTo(int i) {
    if (_busy || _anyAnimating || _curtain != null) return;
    _pager.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
  }

  Widget _card(int i, double w, double h, ColorScheme base) {
    final slot = _slots[i];
    final season = slot.season;
    final multi = _slots.length > 1;
    final next = i + 1 < _slots.length ? i + 1 : 0;
    final nextLabel = next == 0 ? '← ${trKey('chestTagMain')}' : '${_slots[next].season!.nameIn(_lang)} →';
    final tagBg = season == null ? base.surfaceContainerLowest : season.palette?.fill ?? base.primary;
    final tagFg = season == null ? base.onSurfaceVariant : season.palette?.onFill ?? base.onPrimary;
    final nextBg = season == null ? base.inverseSurface : season.palette?.ink ?? base.inverseSurface;
    final nextFg = season == null ? base.onInverseSurface : season.palette?.page ?? base.onInverseSurface;
    return _bloodTint(
      slot,
      ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: season == null
                    ? ChestRays(scheme: base, focus: const Alignment(0, 0.24))
                    : ChestFrames(url: season.file('card_back'), still: null, side: w, height: h, fit: BoxFit.fill),
              ),
              // Сундук квадратом в высоту карточки, центр на 52% высоты, как на
              // макете: рисунок целиком, с полем по бокам.
              Positioned(left: (w - h) / 2, top: h * 0.02, width: h, height: h, child: _chestArt(slot, h)),
              if (season != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ChestFrames(
                      url: season.file('card_front'),
                      still: null,
                      side: w,
                      height: h,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              if (season?.flashColor != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _flash,
                      builder: (context, _) => ColoredBox(
                        color: season!.flashColor!.withValues(alpha: _flashSlot == i ? _boltOpacity(_flash.value) : 0),
                      ),
                    ),
                  ),
                ),
              if (multi)
                Positioned(
                  left: 14,
                  top: 14,
                  child: _pill(season == null ? trKey('chestTagMain') : _seasonTag(season), tagBg, tagFg),
                ),
              if (multi)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: nextBg,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _goTo(next),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 34),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                          child: Text(
                            nextLabel,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: nextFg),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// На пике сбоя кнопки карточка темнеет и краснеет: луна становится
  /// кровавой, сундук — бурым.
  Widget _bloodTint(_Slot slot, Widget child) {
    final g = slot.glitch;
    if (g == null) return child;
    return AnimatedBuilder(
      animation: g,
      child: child,
      builder: (context, c) => g.phase == GlitchPhase.peak
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                0.55, 0.35, 0.1, 0, 10, //
                0.08, 0.14, 0.04, 0, 0,
                0.08, 0.08, 0.16, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: c,
            )
          : c!,
    );
  }

  /// Пока кнопка рвётся, страница мелко дрожит, на пиксель туда-сюда.
  Widget _shake(_Slot slot, Widget child) {
    final g = slot.glitch;
    if (g == null) return child;
    return AnimatedBuilder(
      animation: g,
      child: child,
      builder: (context, c) {
        if (!g.shaking || g.reduced) return c!;
        final s = g.frame.isEven ? 1.0 : -1.0;
        return Transform.translate(offset: Offset(s, -s), child: c);
      },
    );
  }

  /// Вспышка молнии: как `@keyframes bolt` макета — два удара и затухание.
  static double _boltOpacity(double t) {
    if (t <= 0 || t >= 1) return 0;
    const keys = [(0.0, 0.0), (0.08, 0.85), (0.16, 0.1), (0.26, 0.7), (1.0, 0.0)];
    for (var k = 1; k < keys.length; k++) {
      final (t1, v1) = keys[k];
      if (t <= t1) {
        final (t0, v0) = keys[k - 1];
        return v0 + (v1 - v0) * (t - t0) / (t1 - t0);
      }
    }
    return 0;
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _chestArt(_Slot slot, double side) {
    final opening = slot.opening;
    final track = slot.track;
    final spot = opening != null && slot.frame >= 0 && slot.frame < track.length ? track[slot.frame] : null;
    final still = slot.isMain ? kChestStill : null;
    final stillUrl = slot.season?.file('still');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (opening == null)
          ChestFrames(
            key: ValueKey('idle${slot.chest}'),
            url: slot.idleUrl,
            still: still,
            stillUrl: stillUrl,
            side: side,
          )
        else
          ChestFrames(
            key: ValueKey('open${slot.chest}${slot.openRun}'),
            url: slot.openUrl,
            still: still,
            stillUrl: stillUrl,
            side: side,
            loop: false,
            onFrame: (i) => _onOpenFrame(slot, i),
            onDone: () => _onOpenDone(slot),
          ),
        if (opening != null && spot != null)
          ChestPrizeFlight(prize: opening, spot: spot, stage: side, peak: slot.trackPeak),
      ],
    );
  }

  Widget _dots(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _slots.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: i == _shown ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _shown ? cs.primary : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: Text(
              _s.isMain
                  ? trKey('chestSwipeHint').replaceAll('{name}', _slots[1].season!.nameIn(_lang))
                  : _s.season!.hintIn(_lang),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(ColorScheme cs, _Slot slot) {
    return [
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 24),
        child: Text(
          slot.won ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      if (slot.opening != null && !slot.animating && slot.won != null) ...[
        const SizedBox(height: 4),
        Center(child: _shareButton(cs, slot)),
      ],
      const SizedBox(height: 12),
      if (slot.choice != null)
        _pick(cs)
      else if (slot.wearWon != null)
        _wear(cs, slot)
      else ...[
        if (_jarBonus > 0 || slot.pendingFromJar) ...[_jarButton(cs, slot), const SizedBox(height: 8)],
        _button(cs, slot),
      ],
      if (slot.choice == null && slot.state?.untilRare != null) ...[
        const SizedBox(height: 8),
        _pity(cs, slot.state!.untilRare!),
      ],
      // Пока идёт анимация, последний приз ещё «тайна» — строка ждёт её конца.
      if (!slot.animating && (slot.state?.today.isNotEmpty ?? false)) ...[
        const SizedBox(height: 8),
        _today(cs, slot.state!.today),
      ],
      const SizedBox(height: 8),
      Text(
        slot.choice != null
            ? trKey('chestChoiceNote').replaceAll('{name}', _partnerName)
            : trKey(_free ? 'chestNoteFree' : 'chestNote'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
      ),
      if (PairJarService.instance.jar != null) ...[const SizedBox(height: 10), _jarRow(cs, slot)],
      if (slot.season != null) ..._inside(cs, slot.season!),
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
    ];
  }

  /// «Что внутри»: три ленты набора — рамки, значки-жильцы, подарки.
  List<Widget> _inside(ColorScheme cs, SeasonChest season) {
    final frames = [
      for (final f in CatalogService.instance.frames)
        if (f.set == season.set) f,
    ];
    final badges = [
      for (final b in CatalogService.instance.badges)
        if (b.set == season.set) b,
    ];
    final gifts = CatalogService.instance.giftArtsOfSet(season.set);
    if (frames.isEmpty && badges.isEmpty && gifts.isEmpty) return const [];
    Widget label(String key, int n) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        trKey(key).replaceAll('{n}', '$n').toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: cs.onSurfaceVariant),
      ),
    );
    Widget strip(List<Widget> tiles) => SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
          alignment: Alignment.center,
          child: tiles[i],
        ),
      ),
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
        child: Text(
          trKey('chestInside'),
          style: TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      if (frames.isNotEmpty) ...[
        label('chestInsideFrames', frames.length),
        strip([for (final f in frames) _frameThumb(f.key)]),
      ],
      if (badges.isNotEmpty) ...[
        label('chestInsideBadges', badges.length),
        strip([for (final b in badges) BadgeImage(b.id, side: 56)]),
      ],
      if (gifts.isNotEmpty) ...[
        label('chestInsideGifts', gifts.length),
        strip([for (final g in gifts) GiftImage(g.key, side: 56)]),
      ],
    ];
  }

  /// Рамка на неподвижном круге: в ленте важна сама рамка, а не чьё фото.
  Widget _frameThumb(String key) {
    return ChestPrizeImage(
      ChestPrize(kind: ChestPrizeKind.frame, key: 'frame_$key', tier: ChestTier.common, weight: 0),
      side: 56,
    );
  }

  /// «Поделиться» выпавшим призом: карточка с подписью Togetherly вместо
  /// скриншота экрана (просьба владельца, 07.10.2026).
  Widget _shareButton(ColorScheme cs, _Slot slot) {
    final prize = slot.opening!;
    return FilledButton.tonalIcon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/chest/share'),
          builder: (_) => ChestShareScreen(
            prize: prize,
            title: slot.won ?? _wonText(prize),
            chance: trKey('chestChance').replaceAll('{p}', chestPercent(prize, _odds, decimal: _decimal)),
            scheme: cs,
            fill: slot.isMain ? widget.theme.fillColor : cs.primary,
            openUrl: slot.openUrl,
            track: slot.isMain ? null : slot.track,
          ),
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: Text(LocaleService.current.share),
    );
  }

  // Цифры одной ширины: иначе надпись с отсчётом дёргается каждую секунду.
  static const TextStyle _buttonText = TextStyle(
    fontFamily: ProfileTheme.displayFont,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _button(ColorScheme cs, _Slot slot) {
    final String label;
    final out = slot.left <= 0 && slot.pendingOpenId == null;
    final busy = _busy || slot.animating;
    // Счётчик в самой кнопке: «Открыть за рекламу 2/3».
    final prefix = trKey(_free || slot.pendingOpenId != null ? 'chestOpenFree' : 'chestOpenAd');
    final count = '${slot.left}/${slot.perDay}';
    if (busy) {
      label = trKey('chestOpening');
    } else if (out) {
      // Открытия кончились — вместо кнопки отсчёт до полуночи.
      label = trKey('chestCountdown').replaceAll('{t}', _countdown());
    } else {
      label = '$prefix $count';
    }
    final glitch = slot.glitch;
    if (glitch != null && !busy && !out) {
      glitch.reduced = MediaQuery.of(context).disableAnimations;
      return AnimatedBuilder(
        animation: glitch,
        builder: (context, _) => _glitchButton(cs, glitch, prefix, count, label),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy || out || _curtain != null ? null : _open,
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.primary.withValues(alpha: 0.6),
          disabledForegroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: _buttonText,
        ),
        // Одной строкой: на 320 точках «Открыть за рекламу 3/3» ломалась на две.
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      ),
    );
  }

  /// Кнопка сезонного сундука со сбоем (макет «Кнопка 666», вариант А).
  /// Подменяется только надпись: нажатие открывает сундук, читалка экрана
  /// слышит настоящее число.
  Widget _glitchButton(ColorScheme cs, SeasonGlitch g, String prefix, String count, String label) {
    final (Color bg, Color fg) = switch (g.phase) {
      GlitchPhase.dim => (Color.lerp(cs.primary, Colors.black, 0.4)!, cs.onPrimary),
      GlitchPhase.neg => (const Color(0xFFF6F0FF), Colors.black),
      GlitchPhase.peak => (g.spec.peakColor ?? const Color(0xFFA3101C), g.spec.onPeak ?? const Color(0xFFFFE9E4)),
      _ => (cs.primary, cs.onPrimary),
    };
    final torn = g.phase == GlitchPhase.split || g.phase == GlitchPhase.peak;
    final style = _buttonText.copyWith(color: fg, letterSpacing: g.phase == GlitchPhase.peak ? 2.2 : null);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            FilledButton(
              onPressed: _curtain != null ? null : _open,
              style: FilledButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: fg,
                minimumSize: const Size(double.infinity, 0),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: const StadiumBorder(),
                animationDuration: Duration.zero,
                textStyle: _buttonText,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GlitchLabel(glitch: g, prefix: prefix, real: count, style: style),
              ),
            ),
            if (torn)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: const CustomPaint(painter: GlitchScanlines()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Открыть из копилки пары: без ролика и сверх трёх в день.
  Widget _jarButton(ColorScheme cs, _Slot slot) {
    final busy = _busy || slot.animating;
    final bg = slot.isMain ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = slot.isMain ? readableTextOn(cs.primaryContainer) : cs.onSurface;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy || _curtain != null ? null : () => _open(fromJar: true),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.6),
          disabledForegroundColor: fg,
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

  /// Копилка пары под кнопкой: капли и как она работает. У сезонного сундука
  /// капли — его рисунки с сервера.
  Widget _jarRow(ColorScheme cs, _Slot slot) {
    final jar = PairJarService.instance.jar!;
    final on = slot.season?.file('drop_on'), off = slot.season?.file('drop_off');
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
          if (on != null && off != null)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < jar.size; i++)
                  Image(
                    image: CachedNetworkImageProvider(
                      i < jar.count ? on : off,
                      cacheManager: OfflineImageCacheManager.instance,
                    ),
                    width: 22,
                    height: 27,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(width: 22, height: 27),
                  ),
              ],
            )
          else
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

  /// Что уже выпало сегодня. Приз разыгрывается, как только ролик засчитан;
  /// ушёл с экрана посреди открытия (нажал уведомление) — приз твой, а видно
  /// его только здесь. Без строки это читалось как «попытка сгорела».
  Widget _today(ColorScheme cs, List<ChestPrize> won) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.redeem_rounded, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            trKey('chestToday').replaceAll('{list}', won.map(_title).join(', ')),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
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
  Widget _wear(ColorScheme cs, _Slot slot) {
    ButtonStyle style(Color bg, Color fg) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w700),
    );
    final prize = slot.wearWon!;
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
              setState(() => slot.wearWon = null);
              _snack(trKey(prize.kind == ChestPrizeKind.badge ? 'chestBadgeWorn' : 'chestFrameWorn'));
            },
            style: style(cs.primary, cs.onPrimary),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(trKey('shopWear'), maxLines: 1)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => setState(() => slot.wearWon = null),
            style: style(cs.primaryContainer, cs.onPrimaryContainer),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(trKey('chestLater'), maxLines: 1)),
          ),
        ),
      ],
    );
  }

  String get _decimal => _lang == 'en' ? '.' : ',';

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

/// Занавес смены страницы, пока он идёт.
class _Curtain {
  _Curtain({required this.to, required this.url, required this.night, required this.coverMs});

  final int to;
  final String url;
  final bool night;
  final int coverMs;

  /// Экран уже закрыт: страница под занавесом сменилась.
  bool covered = false;
}
