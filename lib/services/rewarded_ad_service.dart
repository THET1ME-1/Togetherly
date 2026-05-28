import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Загрузка и показ rewarded-видео.
///
/// Награду НЕ выдаёт сам — это делает серверный SSV-callback
/// (Cloud Function adSsvCallback), который проверяет подпись Google.
/// Здесь только UX: загрузить, показать, дождаться закрытия.
///
/// Передаём `uid` в `customData` SSV-параметров — сервер по нему понимает,
/// кому начислять коины.
class RewardedAdService {
  static const String _testRewardedAdUnit =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _prodRewardedAdUnit =
      'ca-app-pub-1956369312643059/7521878316';

  RewardedAd? _ad;
  bool _isLoading = false;

  String get _adUnitId =>
      kDebugMode ? _testRewardedAdUnit : _prodRewardedAdUnit;

  bool get isReady => _ad != null;

  /// Предзагружает рекламу. Безопасно дёргать несколько раз.
  Future<void> load() async {
    if (_isLoading || _ad != null) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _isLoading = true;
    try {
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _isLoading = false;
          },
          onAdFailedToLoad: (error) {
            debugPrint('RewardedAd load failed: $error');
            _ad = null;
            _isLoading = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('RewardedAd load exception: $e');
      _isLoading = false;
    }
  }

  /// Показывает загруженную рекламу.
  ///
  /// `uid` — uid пользователя, передаётся в SSV `custom_data`.
  /// Возвращает true, если пользователь досмотрел до награды.
  /// Само начисление произойдёт асинхронно на сервере через SSV.
  Future<bool> show({required String uid}) async {
    final ad = _ad;
    if (ad == null) return false;
    _ad = null; // одноразовая

    ad.setServerSideOptions(
      ServerSideVerificationOptions(
        customData: uid, // SSV-callback увидит это в поле custom_data
      ),
    );

    bool earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('RewardedAd show failed: $error');
        ad.dispose();
      },
    );

    await ad.show(
      onUserEarnedReward: (_, reward) {
        earned = true;
      },
    );
    return earned;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
