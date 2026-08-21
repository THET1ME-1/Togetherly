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

  group('AdMob', () {
    test('межстраничные заведены на обеих платформах и они разные', () {
      final ios = AdUnits.admobInterstitial(ios: true);
      final android = AdUnits.admobInterstitial(ios: false);
      expect(ios, isNotEmpty);
      expect(android, isNotEmpty);
      expect(ios, isNot(android));
    });

    test('где блока нет — пустая строка, а не чужой идентификатор', () {
      // Пустая строка выводит сеть из водопада молча; чужой unit сыпал бы
      // отказами загрузки и не давал показов.
      expect(AdUnits.admobBanner(ios: true), isEmpty);
      expect(AdUnits.admobRewarded(ios: true), isEmpty);
    });

    test('андроидные блоки на месте', () {
      expect(AdUnits.admobBanner(ios: false), contains('1956369312643059'));
      expect(AdUnits.admobRewarded(ios: false), contains('1956369312643059'));
    });
  });
}
