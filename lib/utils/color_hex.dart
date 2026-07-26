import 'package:flutter/painting.dart';

/// HEX-цвет: разбор введённой руками строки и запись обратно.
///
/// Отдельный файл, потому что запись цвета была раскидана по проекту в пяти
/// вариантах `toRadixString(16)`, а разбора не было вовсе — колор-пикеру он
/// нужен, и нужен снисходительный: человек печатает и с решёткой, и без, и в
/// нижнем регистре, и тремя знаками.
abstract final class ColorHex {
  /// Разбирает строку в цвет. null — строка ещё не цвет (незаконченный ввод,
  /// лишние знаки): поле ввода на этом не ругается, а просто ждёт.
  ///
  /// Понимает `#RGB`, `#RRGGBB`, `#AARRGGBB` — решётка необязательна.
  static Color? parse(String raw) {
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;

    switch (hex.length) {
      case 3:
        // Короткая запись: каждый знак удваивается (f80 → ff8800).
        hex = hex.split('').map((c) => '$c$c').join();
        hex = 'FF$hex';
      case 6:
        hex = 'FF$hex';
      case 8:
        break;
      default:
        return null;
    }
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  /// Записывает цвет как `#RRGGBB` в верхнем регистре. Прозрачность
  /// отбрасывается: кисть рисует непрозрачным, и лишние два знака в поле ввода
  /// только сбивают.
  static String format(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
