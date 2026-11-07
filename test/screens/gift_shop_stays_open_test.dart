import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Магазин подарков остаётся открытым после подарка (TOG-69, 07.11.2026).
///
/// Из комментариев канала: «когда я захожу в раздел „подарки“, оно
/// автоматически выходит после дарения, и это не очень удобно… особенно, когда
/// нужно сделать по несколько подарков за раз». После листа «отправлено»
/// магазин закрывал сам себя.
void main() {
  test('после листа «отправлено» магазин не закрывается', () {
    final src = File('lib/screens/gifts/gift_shop_screen.dart').readAsStringSync();
    final after = src.split('await _showSent(gift, byAd: byAd);')[1].split('\n  }\n')[0];
    expect(after, isNot(contains('pop(')), reason: after);
  });
}
