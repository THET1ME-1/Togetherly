import 'dart:io';

import 'package:flutter/foundation.dart';

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
}
