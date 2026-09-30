import 'dart:async';
import 'dart:io';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/ad_show_finished.dart';
import '../models/pair_jar.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import '../config/ad_units.dart';

import 'pair_jar_service.dart';
import 'pb_coins_service.dart';

/// Загрузка и показ rewarded-видео Яндекса. AdMob убран 28.09.2026: стоял
/// резервом и за месяц приносил центы. Нет объявления — фоновый повтор загрузки.
///
/// Факт досмотра возвращается из [show] (`true`), награду начисляет сервер
/// (`/api/coins/ad-reward`, с дневным лимитом) прямо в [_showYandex].
class RewardedAdService {
  RewardedAdService({this.chest = false});

  /// Ролик сундука недели: свой блок Яндекса, чтобы вся статистика сундука
  /// лежала в одном блоке РСЯ.
  final bool chest;
  // Яндекс — основная сеть. Debug использует официальный demo-блок Яндекса.
  static const String _demoYandexRewardedUnit = 'demo-rewarded-yandex';

  yandex.RewardedAd? _yandexAd;
  yandex.RewardedAdLoader? _yandexLoader;
  bool _isLoading = false;
  // Идёт показ ролика. Защита от «реклама показывается дважды»: двойной тап по
  // кнопке (она тапабельна в зазоре между тапом и появлением полноэкранной
  // рекламы) или гонка вызовов show() не должны запускать второй ролик.
  bool _isShowing = false;

  // Фоновый авто-ретрай предзагрузки. Когда обе сети не дали рекламу (частый
  // транзиентный no-fill), без ретрая реклама остаётся «не готова» до тех пор,
  // пока юзер не тапнет кнопку — и только этот тап перезапускал загрузку.
  // Отсюда симптом «первый тап — не готово, второй — работает». Сами
  // перезапрашиваем каскад с backoff, чтобы ролик дозагрузился, пока юзер ещё
  // на экране, и тап был мгновенным.
  static const List<Duration> _retryBackoff = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
  ];
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _disposed = false;

  String get _yandexAdUnitId => kDebugMode
      ? _demoYandexRewardedUnit
      : chest
          ? AdUnits.yandexRewardedChest(ios: Platform.isIOS)
          : AdUnits.yandexRewarded(ios: Platform.isIOS);

  /// Готова реклама хоть из одной сети.
  bool get isReady => _yandexAd != null;

  /// True, если показанная реклама была из Яндекса (нет Google-SSV → награду
  /// начисляет серверный callable `grantAdReward`, авторитетно).
  bool _lastShowWasYandex = false;
  bool get lastShowWasYandex => _lastShowWasYandex;

  /// Авторитетный баланс коинов после Яндекс-показа (из ответа `grantAdReward`).
  /// null, если
  /// callable не ответил (не задеплоен/оффлайн) — тогда баланс надо подтянуть
  /// с сервера отдельно.
  int? _lastServerCoins;
  int? get lastServerCoins => _lastServerCoins;

  /// True, если сервер РЕАЛЬНО начислил награду за Яндекс-показ (false при
  /// дневном лимите/ошибке). Нужно, чтобы не показывать фейковую награду.
  bool _lastRewardGranted = false;
  bool get lastRewardGranted => _lastRewardGranted;

  /// True, если сервер отказал из-за дневного лимита (а не из-за ошибки).
  /// Используется, чтобы показать пользователю «лимит исчерпан».
  bool _lastRateLimited = false;
  bool get lastRateLimited => _lastRateLimited;

  /// Ответ о начислении не пришёл за [kAdGrantWait] — показ отпустили без
  /// него. Для телеметрии: отличает потерю ответа от отказа.
  bool _lastGrantTimedOut = false;
  bool get lastGrantTimedOut => _lastGrantTimedOut;

  /// Сколько секунд приложение было за рекламой в прошлом показе.
  int _lastSecondsAway = 0;
  int get lastSecondsAway => _lastSecondsAway;

  /// Номер открытия сундука, за который идёт этот ролик (уходит в начисление).
  String? _chestOpenId;

  /// Предзагружает ролик Яндекса; при отказе — фоновый повтор.
  /// Безопасно дёргать несколько раз.
  Future<void> load() async {
    if (_disposed) return;
    if (_isLoading || isReady) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _retryTimer?.cancel();
    _isLoading = true;
    unawaited(_loadYandex());
  }

  /// Планирует фоновую перезагрузку каскада после полного провала обеих сетей.
  /// Backoff и лимит попыток — чтобы не молотить запросами при оффлайне.
  void _scheduleRetry() {
    _isLoading = false;
    if (_disposed || isReady) return;
    if (_retryCount >= _retryBackoff.length) return; // лимит исчерпан
    final delay = _retryBackoff[_retryCount];
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_disposed || isReady) return;
      load();
    });
  }

  Future<void> _loadYandex() async {
    try {
      _yandexLoader ??= await yandex.RewardedAdLoader.create(
        onAdLoaded: (ad) {
          _yandexAd = ad;
          _isLoading = false;
          _retryCount = 0; // успех — сбрасываем backoff
        },
        onAdFailedToLoad: (error) {
          debugPrint(
              'Yandex rewarded failed: ${error.code} ${error.description}'
              ' → retry');
          _yandexAd = null;
          _reportLoadFailure('${error.code}', error.description);
          _scheduleRetry();
        },
      );
      await _yandexLoader!.loadAd(
        adRequestConfiguration:
            yandex.AdRequestConfiguration(adUnitId: _yandexAdUnitId),
      );
    } catch (e) {
      debugPrint('Yandex rewarded load exception: $e → retry');
      _reportLoadFailure('exception', '$e');
      _scheduleRetry();
    }
  }

  /// Сообщал ли уже этот запуск, что ролик не грузится.
  static bool _loadFailureReported = false;

  /// Почему ролик не загрузился. Раньше код ошибки Яндекса уходил только в
  /// debugPrint, и на жалобу «реклама не грузится третий день» (обращение 210)
  /// ответить было нечем: не видно, пустой ли показ, сеть или запрет на
  /// телефоне. Каждая неудача — крошкой, последняя попытка — событием, не
  /// чаще раза за запуск, чтобы один телефон без рекламы не засыпал панель.
  void _reportLoadFailure(String code, String description) {
    Sentry.addBreadcrumb(Breadcrumb(
      message: 'Yandex rewarded load failed: $code $description',
      level: SentryLevel.info,
    ));
    final lastTry = _retryCount >= _retryBackoff.length - 1;
    if (!lastTry || _loadFailureReported) return;
    _loadFailureReported = true;
    unawaited(Sentry.captureMessage(
      'Yandex rewarded never loaded',
      level: SentryLevel.warning,
      withScope: (s) {
        s.setTag('ad_error_code', code);
        s.setExtra('ad_error', description);
        s.setExtra('ad_unit', _yandexAdUnitId);
        s.setExtra('chest', chest);
        s.setExtra('attempts', _retryCount + 1);
      },
    ));
  }

  /// Показывает загруженный ролик Яндекса.
  ///
  /// Возвращает true, если человек досмотрел до награды; награду начисляет
  /// сервер внутри [_showYandex]. [uid] оставлен ради прежних вызовов.
  /// [chestOpenId] — ролик за сундук: номер открытия едет в начисление.
  Future<bool> show({required String uid, String? chestOpenId}) async {
    // Уже идёт показ — игнорируем повторный вызов (двойной тап/гонка), иначе
    // запустится второй ролик подряд.
    if (_isShowing) return false;
    _isShowing = true;
    // Сбрасываем авторитетный результат прошлого показа.
    _lastServerCoins = null;
    _lastRewardGranted = false;
    _lastRateLimited = false;
    _lastGrantTimedOut = false;
    _lastSecondsAway = 0;
    _chestOpenId = chestOpenId;
    try {
      if (_yandexAd != null) {
        _lastShowWasYandex = true;
        return await _showYandex(_yandexAd!);
      }
      return false;
    } finally {
      _isShowing = false;
    }
  }

  /// Ждёт закрытия показа: событие от SDK, возврат приложения на передний план
  /// или предохранитель — что случится раньше.
  ///
  /// Событие закрытия приходит не всегда (по журналу — тысячи случаев), и пока
  /// ждали только его, человек стоял перед пустым экраном две минуты: медиана
  /// ожидания была ровно 120 секунд. Возврат приложения — такой же честный
  /// признак того, что реклама закрылась.
  Future<AdShowWatch> _awaitAdClosed(Completer<void> dismissed, String who) async {
    final watch = AdShowWatch();
    late final AppLifecycleListener listener;
    final returned = Completer<void>();
    listener = AppLifecycleListener(
      onStateChange: (state) {
        watch.onState(state);
        if (watch.finished && !returned.isCompleted) returned.complete();
      },
    );
    try {
      await Future.any([
        dismissed.future,
        returned.future.then((_) async {
          // Событие закрытия часто приходит следом за возвратом — даём ему
          // долететь, чтобы награда засчиталась штатным путём.
          await Future<void>.delayed(kAdReturnGrace);
        }),
      ]).timeout(kAdShowGuard, onTimeout: () {
        debugPrint('$who: событий закрытия нет, выходим по предохранителю');
      });
    } finally {
      listener.dispose();
    }
    return watch;
  }

  Future<bool> _showYandex(yandex.RewardedAd ad) async {
    _yandexAd = null; // одноразовая
    // Награду начисляем ПРЯМО В onRewarded, а не после закрытия. Раньше код
    // ждал onAdDismissed и лишь потом смотрел флаг earned (с окном 400мс на
    // запоздавший reward). На медленных устройствах Яндекс присылает onRewarded
    // уже ПОСЛЕ dismiss+окна → earned читался как false, grantAdReward не
    // вызывался, коины/счётчик не менялись (баг «посмотрел — монет нет»). Грант
    // внутри колбэка снимает гонку с таймингом закрытия полностью.
    bool earned = false;
    // Показ и его длительность: без них «награды не было» ничего не объясняет —
    // человек мог закрыть ролик на второй секунде, а мог досмотреть до конца и
    // остаться без монет. В панели крашей это была одна и та же строка.
    bool shown = false;
    DateTime? shownAt;
    Future<void>? grantFuture;
    final dismissed = Completer<void>();
    void finish() {
      if (!dismissed.isCompleted) dismissed.complete();
    }

    await ad.setAdEventListener(
      eventListener: yandex.RewardedAdEventListener(
        onAdShown: () {
          shown = true;
          shownAt = DateTime.now();
        },
        onRewarded: (reward) {
          if (earned) return; // защита от повторного события
          earned = true;
          grantFuture = _grantAdReward();
        },
        onAdDismissed: finish,
        onAdFailedToShow: (error) {
          debugPrint('Yandex rewarded show failed: ${error.description}');
          finish();
        },
      ),
    );
    // Показ может не начаться вовсе: на iOS SDK Яндекса отвечает
    // «no view controller present», и тогда ни одного события не приходит —
    // ни onAdShown, ни onAdFailedToShow. Раньше на этом месте ожидание висело
    // навсегда, и вход в совместный просмотр замирал на спиннере у обоих
    // партнёров. Ошибку показа считаем закрытием без награды, а на само
    // ожидание ставим предохранитель.
    // Сам вызов show() тоже ограничен: SDK, не нашедший куда показать,
    // может не ответить вовсе. Дальше решает ожидание закрытия.
    try {
      await ad.show().timeout(kAdShowStart, onTimeout: () {});
    } catch (e) {
      debugPrint('Yandex rewarded show() бросил — $e');
      finish();
    }
    final watch = await _awaitAdClosed(dismissed, 'Yandex rewarded');
    _lastSecondsAway = watch.away.inSeconds;
    // onRewarded может прийти вплотную к закрытию (или сразу после) — даём ему
    // долететь, прежде чем решить, что награды не было. Окно щедрое: грант всё
    // равно идёт внутри колбэка, лишнего ожидания на успешном пути нет.
    if (!earned) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    // Если награда засчитана — дожидаемся завершения серверного начисления,
    // чтобы вызывающий получил актуальные lastServerCoins/lastRewardGranted.
    // Ждём не дольше [kAdGrantWait]: потерянный ответ держал бы вызывающий
    // экран на спиннере навсегда (сундук стоял на «Открываем…», обращение
    // 211). Начисление при этом доходит само, баланс подтянется позже.
    if (grantFuture != null) {
      await grantFuture!.timeout(kAdGrantWait, onTimeout: () => _lastGrantTimedOut = true);
    }
    // Событие награды теряется по дороге: за тридцать дней 214 показов
    // кончились «монет нет», и в 188 из них ролик держал экран дольше
    // тридцати секунд — люди досматривали и оставались ни с чем. Досмотренный
    // ролик засчитываем сами; экономику держит серверный предел в девять
    // начислений за сутки, а не молчание SDK.
    final onScreen = shownAt == null
        ? Duration.zero
        : DateTime.now().difference(shownAt!);
    var grantedByWatch = false;
    if (!earned &&
        adRewardDeserved(
          shown: shown,
          away: watch.away,
          onScreen: onScreen,
        )) {
      earned = true;
      grantedByWatch = true;
      await _grantAdReward().timeout(kAdGrantWait, onTimeout: () => _lastGrantTimedOut = true);
      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Yandex rewarded: награда засчитана без onRewarded '
            '(${watch.away.inSeconds} с за рекламой)',
        level: SentryLevel.info,
      ));
    }
    if (!earned) {
      // Реклама показана и закрыта, но onRewarded так и не пришёл → грант не
      // вызывался, коинов нет. Это ядро жалоб «посмотрел рекламу — монет нет».
      final seconds = onScreen.inSeconds;
      unawaited(Sentry.captureException(
        'Yandex rewarded shown but no reward earned (onRewarded missing)',
        withScope: (s) {
          s.setExtra('reason', 'rewarded ad shown without reward callback');
          s.setExtra('ad_shown', shown);
          s.setExtra('seconds_on_screen', seconds);
          // Время ЗА рекламой: стенные часы включают и то, что человек делал
          // вне ролика, поэтому судить по ним нельзя было.
          s.setExtra('seconds_behind_ad', watch.away.inSeconds);
          // Ролик короче пяти секунд — человек закрыл сам, это не поломка.
          // Дольше — награда действительно потерялась по дороге.
          s.setExtra('likely_user_skip', shown && seconds < 5);
          s.setExtra('granted_by_watch', grantedByWatch);
          s.level = SentryLevel.warning;
        },
      ));
    }
    return earned;
  }

  /// Серверное начисление за rewarded-показ авторитетным роутом
  /// `/api/coins/ad-reward`, зовётся из onRewarded. С дневным лимитом на сервере. Результат — в
  /// [lastServerCoins]/[lastRewardGranted]/[lastRateLimited]: вызывающий
  /// применяет точный баланс и не рисует фейк при лимите.
  Future<void> _grantAdReward() async {
    try {
      final res = await PbCoinsService().adReward(groupId: PairJarService.instance.groupId, chestOpenId: _chestOpenId);
      if (res != null) {
        // Копилка пары: капля падает за каждый засчитанный ролик, и после
        // дневного предела монет тоже.
        PairJarService.instance.applyDrop(PairJar.fromJson(res['jar']));
        _lastRewardGranted = res['ok'] == true;
        _lastRateLimited = res['rateLimited'] == true;
        final c = res['coins'];
        if (c is num) _lastServerCoins = c.toInt();
        if (_lastRateLimited) {
          // Лимит 3/сутки — это НЕ баг, поэтому breadcrumb, а не recordError.
          // Но в панели видно «дошёл до лимита» → отличаем от реального отказа.
          debugPrint('Yandex reward: daily limit reached, not granted');
          Sentry.addBreadcrumb(Breadcrumb(
              message: 'ad_reward: rate-limited (daily cap), coins=$c',
              level: SentryLevel.info));
        } else if (!_lastRewardGranted) {
          // ok=false без rateLimited — неожиданный отказ начисления.
          unawaited(Sentry.captureException(
            'grantAdReward ok=false (not rate-limited): $res',
            withScope: (s) {
              s.setExtra('reason', 'ad reward not granted (server said no)');
              s.level = SentryLevel.warning;
            },
          ));
        } else {
          Sentry.addBreadcrumb(Breadcrumb(
              message: 'ad_reward: granted +3, coins=$c',
              level: SentryLevel.info));
        }
      } else {
        // null = функция не ответила. Самая частая причина — grantAdReward
        // не задеплоена: `firebase deploy --only functions:grantAdReward`.
        // Это и есть «посмотрел рекламу — коинов нет». Фиксируем как ошибку.
        debugPrint('grantAdReward returned null '
            '(not deployed / offline?) — coins not credited');
        unawaited(Sentry.captureException(
          'grantAdReward returned null — coins NOT credited '
          '(function not deployed / offline?)',
          withScope: (s) {
            s.setExtra('reason', 'ad reward grant call returned null');
            s.level = SentryLevel.warning;
          },
        ));
      }
    } catch (e, st) {
      debugPrint('grantAdReward (Yandex) failed: $e');
      unawaited(Sentry.captureException(
        e,
        stackTrace: st,
        withScope: (s) {
          s.setExtra('reason', 'ad reward grant call threw');
          s.level = SentryLevel.warning;
        },
      ));
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _yandexAd = null;
    unawaited(_yandexLoader?.destroy() ?? Future.value());
    _yandexLoader = null;
  }
}
