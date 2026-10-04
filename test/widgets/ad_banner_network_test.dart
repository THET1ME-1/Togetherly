// Обращение 231 (04.10.2026): где Яндекс недоступен, баннер раз в полминуты
// создавал платформенный вид, ловил «network error» и убирал его — весь сеанс.
// После двух сетевых отказов баннеры до перезапуска не создаются.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/ad_banner.dart';

void main() {
  test('сетевой отказ узнаётся по тексту', () {
    expect(bannerFailIsNetwork('Ad request failed with network error'), isTrue);
    expect(bannerFailIsNetwork('Ad request completed successfully, but there are no ads available.'), isFalse);
    expect(bannerFailIsNetwork(''), isFalse);
  });

  test('после двух сетевых отказов новые баннеры не создаются', () {
    final src = File('lib/widgets/common/ad_banner.dart').readAsStringSync();
    final guard = src.indexOf('if (_networkFails >= _maxNetworkFails)');
    final create = src.indexOf('yandex.BannerAd(');
    expect(guard, greaterThan(0), reason: 'проверки нет');
    expect(guard, lessThan(create), reason: 'проверять надо до создания вида');
    expect(src, contains('static const int _maxNetworkFails = 2;'));
  });
}
