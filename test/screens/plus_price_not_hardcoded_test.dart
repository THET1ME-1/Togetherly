import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dict/chat.dart';

/// Цену Togetherly+ называет магазин, а не словарь.
///
/// Подпись кнопки складывается из строки и цены от StoreKit/Play. Пока в самой
/// строке стояло «Купить за $10», на кнопке выходило «Купить за $10 · 9,99 $» —
/// две цены подряд, да ещё и разные (снимок из TestFlight, 19.08.2026). У
/// Apple и Google свои валюты, округления и налоги в каждой стране, поэтому
/// число в словаре врёт всем, кроме США.
void main() {
  test('в подписи кнопки покупки нет своей цены', () {
    final line = chatStrings['plusBuy'];
    expect(line, isNotNull, reason: 'Строка кнопки на месте');
    final digits = RegExp(r'\d');
    line!.forEach((lang, text) {
      expect(digits.hasMatch(text), isFalse,
          reason: 'Цена зашита в перевод «$lang»: $text');
      expect(text.contains(r'$'), isFalse,
          reason: 'Валюта зашита в перевод «$lang»: $text');
    });
  });

  test('строка с ценой ждёт подстановку, а не своё число', () {
    final line = chatStrings['plusBuyFor'];
    expect(line, isNotNull, reason: 'Строка с ценой заведена');
    expect(line!.keys.length, 7, reason: 'Семь языков');
    line.forEach((lang, text) {
      expect(text.contains('{price}'), isTrue,
          reason: 'В переводе «$lang» нет места под цену: $text');
      expect(RegExp(r'\d').hasMatch(text.replaceAll('{price}', '')), isFalse,
          reason: 'Своё число в переводе «$lang»: $text');
    });
  });

  test('цена берётся у магазина', () {
    final source = File('lib/screens/plus_screen.dart').readAsStringSync();
    expect(source.contains('priceLabel(kPlusProductId)'), isTrue,
        reason: 'Подпись собирается из цены магазина');
  });
}
