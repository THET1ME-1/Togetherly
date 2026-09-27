import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/config/ad_units.dart';

/// Блоки у Android и iOS разные — приложения в кабинетах заведены по
/// отдельности. Чужой блок показов не даёт, и заметить это по логам нельзя:
/// сеть просто отвечает «нет объявлений».
void main() {
  group('Яндекс', () {
    test('каждой платформе свой блок', () {
      for (final unit in [
        [AdUnits.yandexBanner(ios: true), AdUnits.yandexBanner(ios: false)],
        [AdUnits.yandexRewarded(ios: true), AdUnits.yandexRewarded(ios: false)],
        [
          AdUnits.yandexInterstitial(ios: true),
          AdUnits.yandexInterstitial(ios: false)
        ],
      ]) {
        expect(unit[0], isNot(unit[1]));
        expect(unit[0], isNotEmpty);
        expect(unit[1], isNotEmpty);
      }
    });

    test('у сундука свой блок, не общий ролик за награду', () {
      for (final ios in [true, false]) {
        expect(AdUnits.yandexRewardedChest(ios: ios), isNot(AdUnits.yandexRewarded(ios: ios)));
      }
      expect(AdUnits.yandexRewardedChest(ios: true), 'R-M-19461868-4');
      expect(AdUnits.yandexRewardedChest(ios: false), 'R-M-19386995-4');
    });

    test('iOS-блоки из приложения 19461868, Android — из 19386995', () {
      expect(AdUnits.yandexBanner(ios: true), startsWith('R-M-19461868-'));
      expect(AdUnits.yandexRewarded(ios: true), startsWith('R-M-19461868-'));
      expect(AdUnits.yandexInterstitial(ios: true), startsWith('R-M-19461868-'));
      expect(AdUnits.yandexBanner(ios: false), startsWith('R-M-19386995-'));
      expect(AdUnits.yandexRewarded(ios: false), startsWith('R-M-19386995-'));
      expect(
          AdUnits.yandexInterstitial(ios: false), startsWith('R-M-19386995-'));
    });

    test('форматы не перепутаны местами', () {
      final ios = {
        AdUnits.yandexBanner(ios: true),
        AdUnits.yandexRewarded(ios: true),
        AdUnits.yandexInterstitial(ios: true),
      };
      expect(ios.length, 3);
    });
  });

  test('AdMob из приложения убран целиком', () {
    // Стоял первым в водопаде и за месяц приносил центы против сотен долларов
    // у РСЯ, забирая при этом показы. Вернуть его можно только осознанно.
    for (final f in [
      'lib/config/ad_units.dart',
      'lib/services/rewarded_ad_service.dart',
      'lib/services/interstitial_ad_service.dart',
      'lib/widgets/common/ad_banner.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('ca-app-pub-'), isFalse, reason: '$f: блок AdMob');
      expect(src.contains("package:google_mobile_ads"), isFalse, reason: '$f: пакет AdMob');
    }
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('MobileAds.instance.initialize'), isFalse, reason: 'AdMob не инициализируется');
  });
}
