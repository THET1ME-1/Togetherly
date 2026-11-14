import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as admob;
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import '../config/ad_units.dart';
import 'ad_cover_watch.dart';
import 'ad_platform.dart';

/// Межстраничный ролик: показывается на переходе между экранами, награды за
/// него нет.
///
/// Отдельно от [RewardedAdService] не по прихоти: rewarded обе сети разрешают
/// показывать ТОЛЬКО по выбору человека — он сам жмёт «посмотреть ролик за
/// монеты». Показ такого ролика без спроса нарушает правила и AdMob, и Яндекса,
/// а за это снимают аккаунт целиком. Обязательный показ бывает только
/// межстраничным, и кнопку закрытия внутри рисует сама сеть.
///
/// Водопад: сперва Яндекс, после его отказа AdMob (вернулся 14.11.2026
/// запасным). Нет объявления ни там, ни там — нет и показа.
class InterstitialAdService {
  InterstitialAdService({this.room = false});

  /// Ролик после комнаты совместного просмотра: свой блок Яндекса, чтобы
  /// доход комнаты лежал в РСЯ отдельной строкой.
  final bool room;

  // Яндекс. В отладке — демо-блок из документации.
  static const String _demoYandexUnit = 'demo-interstitial-yandex';

  yandex.InterstitialAd? _yandexAd;
  yandex.InterstitialAdLoader? _yandexLoader;
  admob.InterstitialAd? _admobAd;
  bool _isLoading = false;
  bool _isShowing = false;
  bool _disposed = false;

  String get _yandexUnit => kDebugMode
      ? _demoYandexUnit
      : room
          ? AdUnits.yandexInterstitialRoom(ios: Platform.isIOS)
          : AdUnits.yandexInterstitial(ios: Platform.isIOS);

  String get _admobUnit => kDebugMode
      ? AdUnits.admobTestInterstitial(ios: Platform.isIOS)
      : room
          ? AdUnits.admobInterstitialRoom(ios: Platform.isIOS)
          : AdUnits.admobInterstitial(ios: Platform.isIOS);

  /// Ролик загружен хоть из одной сети.
  bool get isReady => _yandexAd != null || _admobAd != null;

  /// Предзагрузка. Звать заранее — на входе в экран, а не в момент показа:
  /// загрузка занимает секунды, и ждать её человеку не за чем.
  Future<void> load() async {
    if (_disposed || _isLoading || isReady) return;
    if (!AdPlatform.supported) return;
    _isLoading = true;
    try {
      await _loadYandex();
      if (!_disposed && _yandexAd == null) await _loadAdmob();
    } finally {
      _isLoading = false;
    }
  }

  /// Запасной AdMob: грузится, только когда Яндекс отказал.
  Future<void> _loadAdmob() async {
    if (!AdPlatform.admobTurn()) return;
    final answered = Completer<void>();
    try {
      await admob.InterstitialAd.load(
        adUnitId: _admobUnit,
        request: const admob.AdRequest(),
        adLoadCallback: admob.InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              unawaited(ad.dispose());
            } else {
              _admobAd = ad;
            }
            if (!answered.isCompleted) answered.complete();
          },
          onAdFailedToLoad: (error) {
            debugPrint('AdMob interstitial failed: ${error.code} ${error.message}');
            if (!answered.isCompleted) answered.complete();
          },
        ),
      );
      await answered.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    } catch (e) {
      debugPrint('AdMob interstitial load exception: $e');
    }
  }

  Future<void> _loadYandex() async {
    if (_yandexUnit.isEmpty) return;
    // SDK 8 отдаёт объявление из `loadAd`, а отказ бросает AdRequestError.
    try {
      final loader = _yandexLoader ??= yandex.InterstitialAdLoader();
      final ad = await loader.loadAd(
        adRequest: yandex.AdRequest(adUnitId: _yandexUnit),
      );
      if (_disposed) {
        unawaited(ad.destroy());
      } else {
        _yandexAd = ad;
      }
    } on yandex.AdRequestError catch (error) {
      debugPrint('Yandex interstitial failed: ${error.code} '
          '${error.description}');
      _yandexAd = null;
    } catch (e) {
      debugPrint('Yandex interstitial load exception: $e');
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
      return await _showAdmob(timeout);
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
      // На iPhone плагин кладёт ролик прозрачным контроллером поверх Flutter,
      // и событие «закрыто» теряется: конец ролика видно по стопке
      // контроллеров. Там же убирается пустой слой плагина, если он остался
      // держать касания (TOG-37).
      final cover = AdCoverWatch()..start();
      unawaited(cover.closed.then((_) {
        if (!done.isCompleted) done.complete(true);
      }));
      final bool shown;
      try {
        shown = await done.future.timeout(timeout, onTimeout: () => true);
      } finally {
        cover.stop();
      }
      await ad.destroy();
      return shown;
    } catch (e) {
      debugPrint('Yandex interstitial show exception: $e');
      return false;
    }
  }

  Future<bool> _showAdmob(Duration timeout) async {
    final ad = _admobAd;
    if (ad == null) return false;
    _admobAd = null;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = admob.FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdMob interstitial show failed: $error');
        unawaited(ad.dispose());
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('AdMob interstitial show exception: $e');
      unawaited(ad.dispose());
      return false;
    }
    return done.future.timeout(timeout, onTimeout: () => true);
  }

  void dispose() {
    _disposed = true;
    unawaited(_admobAd?.dispose() ?? Future<void>.value());
    _admobAd = null;
    unawaited(_yandexAd?.destroy() ?? Future<void>.value());
    _yandexAd = null;
    _yandexLoader?.destroy();
    _yandexLoader = null;
  }
}
