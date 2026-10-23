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
}
