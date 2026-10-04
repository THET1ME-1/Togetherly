import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// Баннер Яндекса между содержимым: грузится один раз, сам себя убирает.
///
/// AdMob убран из приложения 28.09.2026: стоял первым в водопаде и за месяц
/// приносил центы против сотен долларов у РСЯ, при этом забирал показы.
/// Нет объявления — места под рекламу не держим.
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

  yandex.BannerAd? _yandexAd;
  bool _yandexFailed = false;

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
    super.dispose();
  }

  void _loadAd() => _loadYandex();

  /// Баннер Яндекса: платформенный вид грузится сам при создании, мы только
  /// рисуем его и слушаем отказ.
  void _loadYandex() {
    if (!mounted || _yandexAd != null || _yandexFailed) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_networkFails >= _maxNetworkFails) {
      setState(() => _yandexFailed = true);
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
      adUnitId: unit,
      adSize: yandex.BannerAdSize.inline(
        width: width,
        maxHeight: widget.height.truncate(),
      ),
      onAdFailedToLoad: (error) {
        debugPrint('Yandex banner failed: ${error.code} ${error.description}');
        if (bannerFailIsNetwork(error.description)) _networkFails++;
        if (mounted) setState(() => _yandexFailed = true);
      },
    );
    setState(() => _yandexAd = banner);
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
    if (_yandexAd != null && !_yandexFailed) {
      return _frame(
        Container(
          height: widget.height,
          alignment: Alignment.center,
          child: yandex.AdWidget(bannerAd: _yandexAd!),
        ),
      );
    }
    // Сеть отказала — места под рекламу не держим.
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
