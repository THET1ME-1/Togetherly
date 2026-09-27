import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Жалоба 28.09.2026: «посмотрел рекламу — и никакого итога». Итог после
// ролика ложился под закрывающийся экран рекламы, а незасчитанный ролик не
// говорил ничего. Сторож: после каждого `show(` ролика в экранах —
// `showAdNotEarned` на провал и `untilAppVisible` перед итогом.
void main() {
  const screens = {
    'lib/screens/gifts/gift_shop_screen.dart': 1,
    'lib/screens/draw_screen.dart': 1,
    'lib/screens/widget_screen.dart': 1,
    'lib/screens/profile_screen.dart': 2,
    'lib/screens/home_screen.dart': 1,
  };
  for (final e in screens.entries) {
    test('${e.key}: ролик не молчит и итог виден', () {
      final src = File(e.key).readAsStringSync();
      expect(RegExp(r'showAdNotEarned\(').allMatches(src).length, greaterThanOrEqualTo(e.value),
          reason: 'незасчитанный ролик обязан сказать об этом');
      expect(src.contains('untilAppVisible()'), isTrue, reason: 'итог — после закрытия рекламы');
    });
  }

  test('подарок и значок подтверждаются листом с самой вещью', () {
    final src = File('lib/screens/gifts/gift_shop_screen.dart').readAsStringSync();
    expect(src.contains("trKey('giftSentTitle')"), isTrue);
    expect(src.contains("trKey('badgeObtainedTitle')"), isTrue);
  });
}
