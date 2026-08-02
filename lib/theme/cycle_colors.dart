import 'package:flutter/material.dart';

/// Цвета отметок цикла.
///
/// Календарей на экране два — свой и партнёрский, один под другим, — поэтому
/// метка месячных обязана называть владельца сама. Пока цвет был один на обе
/// сетки, пара из двух девушек различала их только по заголовку карточки, а он
/// уезжает вверх при первой же прокрутке.
///
/// Цвета разведены по тону, а не по яркости: два оттенка одного тона при
/// цветовой слепоте сливаются. Одного цвета мало и этого, поэтому в календаре
/// метки ещё и стоят по разным краям клетки — свои снизу, партнёрские сверху.
abstract final class CycleColors {
  /// Привычный красный своих дней. Он стоял в календаре до разделения, и
  /// менять его не за чем: новый цвет получает партнёрша.
  static const Color _mineLight = Color(0xFFD32F2F);
  static const Color _mineDark = Color(0xFFFF8A80);

  /// Сливовый партнёрши: далеко от красного по тону и уживается с розовой
  /// гаммой приложения.
  static const Color _hersLight = Color(0xFF7A3E9D);
  static const Color _hersDark = Color(0xFFD9A6F5);

  /// Цвет дня месячных. [partner] — сетка партнёрши.
  static Color period(Brightness brightness, {required bool partner}) {
    final dark = brightness == Brightness.dark;
    if (partner) return dark ? _hersDark : _hersLight;
    return dark ? _mineDark : _mineLight;
  }
}
