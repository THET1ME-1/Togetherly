import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as admob;

import '../../services/ad_platform.dart';
import '../../services/analytics_service.dart';
import '../../services/plus_service.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import '../../config/ad_units.dart';

/// Отказ баннера из-за сети, а не из-за отсутствия объявления: «Ad request
/// failed with network error» в журнале обращения 231. Только по тексту: номер
/// кода у сетевой ошибки и у «нет объявления» в разных версиях SDK разный, а
/// принять «нет объявления» за сеть значит отключить баннеры тем, у кого всё
/// в порядке.
@visibleForTesting
bool bannerFailIsNetwork(String description) =>
    description.toLowerCase().contains('network');

/// Демо-блок Яндекса для отладочной сборки, в релизе — наш блок.
const String _demoYandexBannerUnit = 'demo-banner-yandex';

/// Баннер между содержимым: грузится один раз, сам себя убирает.
///
/// Водопад: сперва Яндекс, после его отказа AdMob. AdMob стоял первым до
/// 28.09.2026 и забирал показы за центы; с 14.11.2026 он запасной — для тех,
/// до кого Яндекс не достаёт (Украина), и на пустые ответы Яндекса.
/// Нет объявления ни там, ни там — места под рекламу не держим.
///
/// Реклама заказывается НЕ при создании виджета, а когда блок впервые попал на
/// экран. Списки строят элементы заранее, за краем экрана, и прежде запрос
/// уходил в сеть за баннер, которого никто не увидит: в РСЯ на 4,9 тысячи
/// запросов приходилось 1,5 тысячи показов. Холостые запросы не только не
/// приносят денег — сети считают долю показанных объявлений качеством площадки
/// и платят по ней.
class AdBanner extends StatefulWidget {
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
    this.height = 50,
    this.framed = false,
    this.label = '',
    this.slot = '',
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  /// Сколько раз баннер упал с ошибкой сети за этот запуск.
  ///
  /// Где Яндекс недоступен, каждый новый экран создавал платформенный вид
  /// баннера, ловил «network error» и убирал его — раз в полминуты, весь
  /// сеанс (обращение 231, Realme 10 Pro, 04.10.2026: после любого действия
  /// приложение переставало принимать нажатия и прокрутку). Вид Android,
  /// который создают и тут же убирают посреди перехода, — главный подозреваемый.
  /// После второго такого отказа баннеры до перезапуска не создаём вовсе.
  static int _networkFails = 0;
  static const int _maxNetworkFails = 2;

  /// Отказы AdMob подряд за запуск: после третьего баннеры до перезапуска не
  /// создаём — та же защита от вида, который рождается и тут же убирается.
  static int _admobFails = 0;
  static const int _maxAdmobFails = 3;

  admob.BannerAd? _admobAd;
  bool _admobReady = false;
  bool _admobFailed = false;

  yandex.BannerAd? _yandexAd;
  StreamSubscription<yandex.BannerAdLoadState>? _yandexState;
  bool _yandexFailed = false;

  /// `load` SDK 8 собрал платформенный вид: его можно ставить на экран.
  bool _yandexReady = false;

  /// Натив ответил на загрузку, значит его каналы живы и `destroy` дойдёт.
  /// До ответа каналов у него нет, и `destroy` падал бы ошибкой мимо всех try.
  bool _yandexAnswered = false;

  /// Запрос уже отправляли: второй раз при возврате в зону видимости не шлём.
  bool _requested = false;

  /// Страховка на случай, если детектор видимости промолчал.
  Timer? _fallback;

  /// Сколько места под баннер на самом деле. Раньше у Яндекса просили ширину
  /// всего экрана, и в карточке с отступами (главная) приходил баннер шире
  /// доступного места — платформенный вид схлопывался, оставляя пустую
  /// полосу. В ленте баннер во всю ширину, поэтому там расхождения не было.
  double _slotWidth = 0;

  @override
  void initState() {
    super.initState();
    // Детектор видимости в бою оказался ненадёжен: событий показа не пришло
    // ни одного — ни с главной, ни из ленты, — и баннер молча ждал разрешения
    // загрузиться. Ждём его три секунды, дальше грузим сами. Ленивость от
    // этого почти не страдает: когда блок на экране, детектор отвечает за
    // полсекунды, и до страховки дело не доходит.
    _fallback = Timer(const Duration(seconds: 3), () {
      if (!mounted || _requested) return;
      _requested = true;
      _loadAd();
    });
  }

  void _onVisible(VisibilityInfo info) {
    if (_requested || info.visibleFraction <= 0) return;
    _requested = true;
    _fallback?.cancel();
    // Свой счёт показов рядом с кабинетом сети: по нему видно, какое место
    // теряет показы, а какое отрабатывает.
    if (widget.slot.isNotEmpty) {
      AnalyticsService.instance.logAdShown(widget.slot);
    }
    _loadAd();
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _yandexState?.cancel();
    // Сам вид натив убирает вместе с экраном, `destroy` снимает его каналы.
    if (_yandexAnswered) {
      unawaited(_yandexAd?.destroy() ?? Future<void>.value());
    }
    unawaited(_admobAd?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _loadAd() => _loadYandex();

  /// Яндекс отказал — баннер AdMob на то же место.
  void _yandexGaveUp() {
    if (!mounted) return;
    setState(() => _yandexFailed = true);
    _loadAdmob();
  }

  /// Запасной баннер AdMob: ставится, только когда Яндекс отказал.
  void _loadAdmob() {
    if (!mounted || _admobAd != null || _admobFailed) return;
    if (!AdPlatform.supported || _admobFails >= _maxAdmobFails || !AdPlatform.admobTurn()) {
      setState(() => _admobFailed = true);
      return;
    }
    final unit = kDebugMode
        ? AdUnits.admobTestBanner(ios: Platform.isIOS)
        : AdUnits.admobBanner(ios: Platform.isIOS);
    final width = (_slotWidth > 0
            ? _slotWidth
            : MediaQuery.of(context).size.width)
        .truncate();
    final banner = admob.BannerAd(
      adUnitId: unit,
      size: admob.AdSize.getInlineAdaptiveBannerAdSize(
        width,
        widget.height.truncate(),
      ),
      request: const admob.AdRequest(),
      listener: admob.BannerAdListener(
        onAdLoaded: (_) {
          _admobFails = 0;
          if (mounted) setState(() => _admobReady = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob banner failed: ${error.code} ${error.message}');
          unawaited(ad.dispose());
          _admobFails++;
          _admobAd = null;
          if (mounted) setState(() => _admobFailed = true);
        },
      ),
    );
    _admobAd = banner;
    banner.load().catchError((Object e) {
      debugPrint('AdMob banner load exception: $e');
      _admobAd = null;
      if (mounted) setState(() => _admobFailed = true);
    });
  }

  /// Баннер Яндекса. В SDK 8 `load` собирает платформенный вид, а запрос
  /// уходит, когда вид встал на экран; итог приходит потоком состояний.
  void _loadYandex() {
    if (!mounted || _yandexAd != null || _yandexFailed) return;
    if (!AdPlatform.supported) return;
    // Яндекс дважды не дошёл по сети (так в Украине) — сразу AdMob.
    if (_networkFails >= _maxNetworkFails) {
      _yandexGaveUp();
      return;
    }

    final unit = kDebugMode
        ? _demoYandexBannerUnit
        : AdUnits.yandexBanner(ios: Platform.isIOS);
    final width = (_slotWidth > 0
            ? _slotWidth
            : MediaQuery.of(context).size.width)
        .truncate();

    final banner = yandex.BannerAd(
      adSize: yandex.BannerAdSize.inline(
        width: width,
        maxHeight: widget.height.truncate(),
      ),
    );
    _yandexAd = banner;
    _yandexState = banner.loadStateStream.listen((state) {
      if (state is yandex.BannerAdLoadStateLoaded) _yandexAnswered = true;
      if (state is! yandex.BannerAdLoadStateError) return;
      _yandexAnswered = true;
      final error = state.error;
      debugPrint('Yandex banner failed: ${error.code} ${error.description}');
      if (bannerFailIsNetwork(error.description)) _networkFails++;
      _yandexGaveUp();
    });
    unawaited(_startYandex(banner, unit));
  }

  /// Вид появляется к концу `load`; поставить [yandex.AdWidget] раньше —
  /// значит поставить пустое место, которое никогда не загрузится.
  Future<void> _startYandex(yandex.BannerAd banner, String unit) async {
    try {
      await banner.load(yandex.AdRequest(adUnitId: unit));
    } catch (e) {
      debugPrint('Yandex banner load exception: $e');
      _yandexGaveUp();
      return;
    }
    if (mounted) setState(() => _yandexReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
        _slotWidth = constraints.maxWidth;
      }
      return _content(context);
    });
  }

  Widget _content(BuildContext context) {
    // Togetherly+ снимает рекламу целиком: не прячет уже загруженный баннер, а
    // не занимает под него место. Проверка здесь одна на все пять мест показа.
    if (PlusService.instance.active) return const SizedBox.shrink();
    if (_yandexAd != null && _yandexReady && !_yandexFailed) {
      return _frame(
        Container(
          height: widget.height,
          alignment: Alignment.center,
          child: yandex.AdWidget(bannerAd: _yandexAd!),
        ),
      );
    }
    if (_admobAd != null && _admobReady) {
      return _frame(
        Container(
          height: widget.height,
          alignment: Alignment.center,
          child: admob.AdWidget(ad: _admobAd!),
        ),
      );
    }
    if (_yandexFailed) {
      // Обе сети отказали — места под рекламу не держим. Пока грузится
      // запасной AdMob, место держим, чтобы содержимое не прыгало дважды.
      if (_admobFailed) return const SizedBox.shrink();
      return SizedBox(height: widget.height);
    }

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
