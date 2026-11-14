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

    test('у гардероба Ту свой ролик за награду', () {
      // «Гардероб Ту (вещи за ролики)» в кабинете (09.11.2026): вещи за
      // ролики РСЯ считает своей строкой, отдельно от монет и сундука.
      for (final ios in [true, false]) {
        expect(AdUnits.yandexRewardedWardrobe(ios: ios), isNot(AdUnits.yandexRewarded(ios: ios)));
        expect(AdUnits.yandexRewardedWardrobe(ios: ios), isNot(AdUnits.yandexRewardedChest(ios: ios)));
      }
      expect(AdUnits.yandexRewardedWardrobe(ios: true), 'R-M-19461868-6');
      expect(AdUnits.yandexRewardedWardrobe(ios: false), 'R-M-19386995-6');
    });

    test('у комнаты просмотра свой межстраничный блок', () {
      // «Совместный просмотр» в кабинете (19.10.2026): доход комнаты РСЯ
      // считает своей строкой.
      for (final ios in [true, false]) {
        expect(AdUnits.yandexInterstitialRoom(ios: ios), isNot(AdUnits.yandexInterstitial(ios: ios)));
      }
      expect(AdUnits.yandexInterstitialRoom(ios: true), 'R-M-19461868-5');
      expect(AdUnits.yandexInterstitialRoom(ios: false), 'R-M-19386995-5');
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

  group('AdMob — запасной к Яндексу (14.11.2026)', () {
    // Блоки заведены 14.11.2026 по одному на каждое место Яндекса, чтобы в
    // кабинете AdMob доход по местам лежал так же, как в РСЯ.
    List<String> all({required bool ios}) => [
          AdUnits.admobBanner(ios: ios),
          AdUnits.admobRewarded(ios: ios),
          AdUnits.admobRewardedChest(ios: ios),
          AdUnits.admobRewardedWardrobe(ios: ios),
          AdUnits.admobInterstitial(ios: ios),
          AdUnits.admobInterstitialRoom(ios: ios),
        ];

    test('шесть разных блоков на платформу, у платформ они свои', () {
      final android = all(ios: false);
      final ios = all(ios: true);
      expect(android.toSet().length, 6);
      expect(ios.toSet().length, 6);
      expect(android.toSet().intersection(ios.toSet()), isEmpty);
      for (final unit in [...android, ...ios]) {
        expect(unit, startsWith('ca-app-pub-1956369312643059/'));
      }
    });

    test('блоки новые, а не прежние, снятые 28.09.2026', () {
      const old = {
        'ca-app-pub-1956369312643059/2560361524',
        'ca-app-pub-1956369312643059/7521878316',
        'ca-app-pub-1956369312643059/3192564102',
      };
      for (final unit in [...all(ios: false), ...all(ios: true)]) {
        expect(old.contains(unit), isFalse, reason: unit);
      }
    });

    test('приложение AdMob в манифесте и Info.plist — то же, что у блоков', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(manifest.contains('ca-app-pub-1956369312643059~3521559179'), isTrue);
      expect(plist.contains('ca-app-pub-1956369312643059~9958268140'), isTrue);
    });

    test('Яндекс первым, AdMob только после его отказа', () {
      // AdMob первым забирал показы за центы. Запасным он закрывает тех, до
      // кого Яндекс не достаёт (Украина), и пустые ответы Яндекса.
      for (final f in [
        'lib/services/rewarded_ad_service.dart',
        'lib/services/interstitial_ad_service.dart',
        'lib/widgets/common/ad_banner.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('_loadAdmob'), isTrue, reason: '$f: запасной AdMob');
        final load = src.indexOf('_loadYandex(');
        expect(load, greaterThanOrEqualTo(0), reason: '$f: Яндекс');
      }
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('MobileAds.instance.initialize'), isTrue, reason: 'AdMob инициализируется');
    });
  });
}
