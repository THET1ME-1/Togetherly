import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import 'firebase_service.dart';

/// Загрузка и показ rewarded-видео по схеме «водопад»: сначала AdMob, и если
/// у Google нет рекламы ([onAdFailedToLoad]) — резерв из Яндекса.
///
/// AdMob выдаёт награду НЕ сам — это делает серверный SSV-callback
/// (Cloud Function adSsvCallback), который проверяет подпись Google и начисляет
/// коины по `uid` из `customData`. У Яндекса Google-SSV нет: для Яндекс-пути
/// факт досмотра возвращается из [show] (`true`), и начислять награду нужно по
/// этому результату (клиентски), если AdMob-резерв не сработал.
class RewardedAdService {
  static const String _testRewardedAdUnit =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _prodRewardedAdUnit =
      'ca-app-pub-1956369312643059/7521878316';

  // Яндекс — резервная сеть. Debug использует официальный demo-блок Яндекса.
  static const String _prodYandexRewardedUnit = 'R-M-19386995-2';
  static const String _demoYandexRewardedUnit = 'demo-rewarded-yandex';

  RewardedAd? _ad;
  yandex.RewardedAd? _yandexAd;
  yandex.RewardedAdLoader? _yandexLoader;
  bool _isLoading = false;

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

  String get _adUnitId =>
      kDebugMode ? _testRewardedAdUnit : _prodRewardedAdUnit;

  String get _yandexAdUnitId =>
      kDebugMode ? _demoYandexRewardedUnit : _prodYandexRewardedUnit;

  /// Готова реклама хоть из одной сети.
  bool get isReady => _ad != null || _yandexAd != null;

  /// True, если показанная реклама была из Яндекса (нет Google-SSV → награду
  /// нужно начислить клиентски по результату [show]).
  bool _lastShowWasYandex = false;
  bool get lastShowWasYandex => _lastShowWasYandex;

  /// Предзагружает рекламу: сначала AdMob, при неудаче — Яндекс.
  /// Безопасно дёргать несколько раз.
  Future<void> load() async {
    if (_disposed) return;
    if (_isLoading || isReady) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _retryTimer?.cancel();
    _isLoading = true;
    try {
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _isLoading = false;
            _retryCount = 0; // успех — сбрасываем backoff
          },
          onAdFailedToLoad: (error) {
            debugPrint('AdMob rewarded failed ($error) → Yandex fallback');
            _ad = null;
            unawaited(_loadYandex());
          },
        ),
      );
    } catch (e) {
      debugPrint('RewardedAd load exception: $e → Yandex fallback');
      unawaited(_loadYandex());
    }
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
              'Yandex rewarded failed: ${error.code} ${error.description}');
          _yandexAd = null;
          // Обе сети не дали рекламу → планируем фоновый ретрай каскада.
          _scheduleRetry();
        },
      );
      await _yandexLoader!.loadAd(
        adRequestConfiguration:
            yandex.AdRequestConfiguration(adUnitId: _yandexAdUnitId),
      );
    } catch (e) {
      debugPrint('Yandex rewarded load exception: $e');
      _scheduleRetry();
    }
  }

  /// Показывает загруженную рекламу (AdMob в приоритете, иначе Яндекс).
  ///
  /// `uid` — uid пользователя, передаётся в SSV `custom_data` (только AdMob).
  /// Возвращает true, если пользователь досмотрел до награды. Для AdMob само
  /// начисление произойдёт на сервере через SSV; для Яндекса (см. класс-док)
  /// награду начисляет вызывающий по этому результату — проверяй
  /// [lastShowWasYandex].
  Future<bool> show({required String uid}) async {
    if (_ad != null) {
      _lastShowWasYandex = false;
      return _showAdMob(_ad!, uid);
    }
    if (_yandexAd != null) {
      _lastShowWasYandex = true;
      return _showYandex(_yandexAd!);
    }
    return false;
  }

  Future<bool> _showAdMob(RewardedAd ad, String uid) async {
    _ad = null; // одноразовая

    ad.setServerSideOptions(
      ServerSideVerificationOptions(
        customData: uid, // SSV-callback увидит это в поле custom_data
      ),
    );

    bool earned = false;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('RewardedAd show failed: $error');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    ad.show(
      onUserEarnedReward: (_, reward) {
        earned = true;
      },
    );
    return completer.future;
  }

  Future<bool> _showYandex(yandex.RewardedAd ad) async {
    _yandexAd = null; // одноразовая
    bool earned = false;
    await ad.setAdEventListener(
      eventListener: yandex.RewardedAdEventListener(
        onRewarded: (reward) => earned = true,
        onAdFailedToShow: (error) =>
            debugPrint('Yandex rewarded show failed: ${error.description}'),
      ),
    );
    await ad.show();
    final reward = await ad.waitForDismiss();
    final didEarn = earned || reward != null;
    // У Яндекса нет Google-SSV, поэтому начисляем награду серверным callable
    // (авторитетно, с дневным лимитом). Делаем это здесь, чтобы оба вызывающих
    // экрана получили коины без изменений в их коде.
    if (didEarn) {
      try {
        await FirebaseService().callGrantAdReward();
      } catch (e) {
        debugPrint('grantAdReward (Yandex) failed: $e');
      }
    }
    return didEarn;
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _ad?.dispose();
    _ad = null;
    _yandexAd = null;
    unawaited(_yandexLoader?.destroy() ?? Future.value());
    _yandexLoader = null;
  }
}
