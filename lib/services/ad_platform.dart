import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as admob;

import 'age_signals.dart';

/// Реклама Яндекса есть только на телефоне.
///
/// Сервисы рекламы выходят на первой строке, если телефона нет. Тест ставит
/// [debugOverride], чтобы прогнать путь SDK на ноутбуке с подменённым
/// каналом платформы.
class AdPlatform {
  AdPlatform._();

  @visibleForTesting
  static bool? debugOverride;

  static bool get supported =>
      debugOverride ?? (Platform.isAndroid || Platform.isIOS);

  /// Тест выключает запасной AdMob: его канал на ноутбуке не отвечает вовсе,
  /// и каскад ждал бы его до срока.
  @visibleForTesting
  static bool admobOff = false;

  /// Сколько раз водопад дошёл до AdMob — по нему тест видит порядок сетей.
  @visibleForTesting
  static int admobAttempts = 0;

  /// Каскад дошёл до запасного AdMob. false — AdMob выключен тестом.
  static bool admobTurn() {
    admobAttempts++;
    return !admobOff;
  }

  /// Запрос AdMob. Ребёнку, подростку и человеку без подтверждённого возраста
  /// в зоне закона — без подстройки под интересы (`npa=1`): COPPA и
  /// бразильский ECA Digital запрещают профилировать несовершеннолетних под
  /// рекламу. Сам возраст в сеть не уходит: условия Google Play Age Signals
  /// запрещают отдавать его третьим лицам.
  static admob.AdRequest admobRequest() =>
      admob.AdRequest(nonPersonalizedAds: AgeSignals.instance.restrictedAds);

  /// Яндекс в каскаде. Без подстройки под интересы он умеет работать только
  /// по флагу «пользователь младше 18» (`setAgeRestricted`), а это и есть
  /// возраст, отданный чужой сети. Поэтому тем, кому подстройка запрещена,
  /// каскад начинается сразу с AdMob в режиме `npa`.
  ///
  /// Ждёт первую проверку возраста за запуск: на самом первом запуске
  /// сохранённого ответа ещё нет. Срок у проверки свой, здесь — страховка.
  static Future<bool> yandexAllowed() async {
    await AgeSignals.instance.settled
        .timeout(const Duration(seconds: 15), onTimeout: () {});
    return !AgeSignals.instance.restrictedAds;
  }
}
