import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/plus_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

/// Test ad unit IDs from Google for development.
/// Replace [adUnitId] with your real AdMob unit ID before release.
const String _testBannerAdUnit = 'ca-app-pub-3940256099942544/6300978111';

/// Yandex banner block id (waterfall fallback when AdMob has no fill).
/// Debug uses Yandex's official demo unit; release uses our real block.
const String _prodYandexBannerUnit = 'R-M-19386995-1';
const String _demoYandexBannerUnit = 'demo-banner-yandex';

/// A self-disposing banner ad that loads once and shows between content.
///
/// Waterfall: tries AdMob first; if AdMob reports no ad
/// ([BannerAdListener.onAdFailedToLoad]), falls back to a Yandex banner. Shows
/// nothing on web/desktop or when both networks fail.
///
/// Реклама заказывается НЕ при создании виджета, а когда блок впервые попал на
/// экран. Списки строят элементы заранее, за краем экрана, и прежде запрос
/// уходил в сеть за баннер, которого никто не увидит: в РСЯ на 4,9 тысячи
/// запросов приходилось 1,5 тысячи показов. Холостые запросы не только не
/// приносят денег — сети считают долю показанных объявлений качеством площадки
/// и платят по ней.
class AdBanner extends StatefulWidget {
  final String adUnitId;

  /// The ad unit ID for this banner. Leave empty to use the test unit.
  final double height;

  /// Обернуть баннер карточкой с подписью «Реклама». Обёртка появляется вместе
  /// с самим объявлением: пустой карточки в макете не бывает.
  final bool framed;

  /// Подпись над баннером в обёртке. Передаётся из локализации.
  final String label;

  /// Место показа для статистики: `home`, `memlane`, `widgets`.
  final String slot;

  const AdBanner({
    super.key,
    this.adUnitId = '',
    this.height = 50,
    this.framed = false,
    this.label = '',
    this.slot = '',
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  String? _errorText;

  // Yandex fallback (used only after AdMob reports no fill).
  yandex.BannerAd? _yandexAd;
  bool _yandexFailed = false;

  /// Запрос уже отправляли: второй раз при возврате в зону видимости не шлём.
  bool _requested = false;

  void _onVisible(VisibilityInfo info) {
    if (_requested || info.visibleFraction <= 0) return;
    _requested = true;
    // Свой счёт показов рядом с кабинетом сети: по нему видно, какое место
    // теряет показы, а какое отрабатывает.
    if (widget.slot.isNotEmpty) {
      AnalyticsService.instance.logAdShown(widget.slot);
    }
    _loadAd();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _loadAd() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final unitId = widget.adUnitId.isNotEmpty
        ? widget.adUnitId
        : (kDebugMode ? _testBannerAdUnit : '');

    if (unitId.isEmpty) {
      // No AdMob unit configured for this build → go straight to Yandex.
      _loadYandex();
      return;
    }

    BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // AdMob has no fill → fall back to Yandex.
          debugPrint('AdMob banner failed (${error.code}), trying Yandex');
          _loadYandex();
        },
      ),
    ).load();
  }

  /// Builds the Yandex banner; its platform view auto-loads on creation, so we
  /// just render it and react to its load callbacks.
  void _loadYandex() {
    if (!mounted || _yandexAd != null || _yandexFailed) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final unit = kDebugMode ? _demoYandexBannerUnit : _prodYandexBannerUnit;
    final width = MediaQuery.of(context).size.width.truncate();

    final banner = yandex.BannerAd(
      adUnitId: unit,
      adSize: yandex.BannerAdSize.inline(
        width: width,
        maxHeight: widget.height.truncate(),
      ),
      onAdFailedToLoad: (error) {
        debugPrint('Yandex banner failed: ${error.code} ${error.description}');
        if (mounted) setState(() => _yandexFailed = true);
      },
    );
    setState(() => _yandexAd = banner);
  }

  @override
  Widget build(BuildContext context) {
    // Togetherly+ снимает рекламу целиком: не прячет уже загруженный баннер, а
    // не занимает под него место. Проверка здесь одна на все пять мест показа.
    if (PlusService.instance.active) return const SizedBox.shrink();
    if (_loaded && _ad != null) {
      return _frame(
        Container(
          height: widget.height,
          alignment: Alignment.center,
          child: AdWidget(ad: _ad!),
        ),
      );
    }
    if (_yandexAd != null && !_yandexFailed) {
      return _frame(
        Container(
          height: widget.height,
          alignment: Alignment.center,
          child: yandex.AdWidget(bannerAd: _yandexAd!),
        ),
      );
    }
    if (kDebugMode && _errorText != null) {
      return Container(
        height: widget.height,
        color: Colors.red.shade100,
        alignment: Alignment.center,
        child: Text(_errorText!, style: const TextStyle(fontSize: 10, color: Colors.red)),
      );
    }
    // Обе сети отказали — места под рекламу не держим.
    if (_yandexFailed) return const SizedBox.shrink();

    // Ждём появления на экране. Место держим: у виджета нулевой высоты видимой
    // доли не бывает, и детектор не сработал бы никогда.
    return VisibilityDetector(
      key: ValueKey('ad_slot_${identityHashCode(this)}'),
      onVisibilityChanged: _onVisible,
      child: SizedBox(height: widget.height),
    );
  }

  /// Карточка с подписью «Реклама» вокруг объявления. Рисуется только когда
  /// объявление есть: пустая рамка в макете выглядела бы поломкой.
  Widget _frame(Widget child) {
    if (!widget.framed) return child;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
