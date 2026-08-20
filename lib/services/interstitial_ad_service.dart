import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

/// Межстраничный ролик: показывается на переходе между экранами, награды за
/// него нет.
///
/// Отдельно от [RewardedAdService] не по прихоти: rewarded обе сети разрешают
/// показывать ТОЛЬКО по выбору человека — он сам жмёт «посмотреть ролик за
/// монеты». Показ такого ролика без спроса нарушает правила и AdMob, и Яндекса,
/// а за это снимают аккаунт целиком. Обязательный показ бывает только
/// межстраничным, и кнопку закрытия внутри рисует сама сеть.
///
/// Водопад тот же, что у наградного: сперва Яндекс, при отказе — AdMob.
class InterstitialAdService {
  // AdMob. В отладке — официальный тестовый блок Google.
  static const String _testAdMobUnit = 'ca-app-pub-3940256099942544/1033173712';

  /// Боевой блок AdMob. Пустая строка означает «блок ещё не заведён»: тогда
  /// AdMob из водопада просто выпадает, а не сыпет ошибками загрузки.
  static const String _prodAdMobUnit = '';

  // Яндекс. В отладке — демо-блок из документации.
  static const String _demoYandexUnit = 'demo-interstitial-yandex';

  /// Боевой блок Яндекса — «Межстраничная реклама», заведён 20.08.2026.
  static const String _prodYandexUnit = 'R-M-19386995-3';

  InterstitialAd? _adMob;
  yandex.InterstitialAd? _yandexAd;
  yandex.InterstitialAdLoader? _yandexLoader;
  bool _isLoading = false;
  bool _isShowing = false;
  bool _disposed = false;

  String get _adMobUnit => kDebugMode ? _testAdMobUnit : _prodAdMobUnit;
  String get _yandexUnit => kDebugMode ? _demoYandexUnit : _prodYandexUnit;

  /// Ролик загружен хотя бы одной сетью.
  bool get isReady => _adMob != null || _yandexAd != null;

  /// Предзагрузка. Звать заранее — на входе в экран, а не в момент показа:
  /// загрузка занимает секунды, и ждать её человеку не за чем.
  Future<void> load() async {
    if (_disposed || _isLoading || isReady) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _isLoading = true;
    await _loadYandex();
  }

  Future<void> _loadYandex() async {
    if (_yandexUnit.isEmpty) {
      unawaited(_loadAdMob());
      return;
    }
    try {
      _yandexLoader ??= await yandex.InterstitialAdLoader.create(
        onAdLoaded: (ad) {
          _yandexAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Yandex interstitial failed: ${error.code} '
              '${error.description} → AdMob');
          _yandexAd = null;
          unawaited(_loadAdMob());
        },
      );
      await _yandexLoader!.loadAd(
        adRequestConfiguration:
            yandex.AdRequestConfiguration(adUnitId: _yandexUnit),
      );
    } catch (e) {
      debugPrint('Yandex interstitial load exception: $e → AdMob');
      unawaited(_loadAdMob());
    }
  }

  Future<void> _loadAdMob() async {
    if (_disposed) return;
    if (_adMobUnit.isEmpty) {
      _isLoading = false;
      return;
    }
    try {
      await InterstitialAd.load(
        adUnitId: _adMobUnit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _adMob = ad;
            _isLoading = false;
          },
          onAdFailedToLoad: (error) {
            debugPrint('AdMob interstitial failed ($error)');
            _adMob = null;
            _isLoading = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('AdMob interstitial load exception: $e');
      _isLoading = false;
    }
  }

  /// Показывает ролик и ждёт, пока его закроют.
  ///
  /// Возвращает true, если показ состоялся. Ожидание ограничено [timeout]:
  /// сеть иногда не присылает событие закрытия вовсе, и без предела человек
  /// остался бы перед пустым экраном навсегда — так замирал совместный
  /// просмотр 12.08.2026.
  Future<bool> show({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_isShowing || !isReady) return false;
    _isShowing = true;
    try {
      if (_yandexAd != null) return await _showYandex(timeout);
      return await _showAdMob(timeout);
    } finally {
      _isShowing = false;
      // Ролик одноразовый: следующий заказываем сразу, чтобы к следующему
      // разу он уже лежал.
      unawaited(load());
    }
  }

  Future<bool> _showYandex(Duration timeout) async {
    final ad = _yandexAd;
    if (ad == null) return false;
    _yandexAd = null;
    final done = Completer<bool>();
    try {
      await ad.setAdEventListener(
        eventListener: yandex.InterstitialAdEventListener(
          onAdDismissed: () {
            if (!done.isCompleted) done.complete(true);
          },
          onAdFailedToShow: (error) {
            debugPrint('Yandex interstitial show failed: $error');
            if (!done.isCompleted) done.complete(false);
          },
        ),
      );
      unawaited(ad.show());
      final shown = await done.future.timeout(timeout, onTimeout: () => true);
      await ad.destroy();
      return shown;
    } catch (e) {
      debugPrint('Yandex interstitial show exception: $e');
      return false;
    }
  }

  Future<bool> _showAdMob(Duration timeout) async {
    final ad = _adMob;
    if (ad == null) return false;
    _adMob = null;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdMob interstitial show failed: $error');
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('AdMob interstitial show exception: $e');
      return false;
    }
    return done.future.timeout(timeout, onTimeout: () => true);
  }

  void dispose() {
    _disposed = true;
    _adMob?.dispose();
    _adMob = null;
    unawaited(_yandexAd?.destroy() ?? Future<void>.value());
    _yandexAd = null;
  }
}
