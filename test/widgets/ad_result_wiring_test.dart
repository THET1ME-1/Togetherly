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
    'lib/screens/chest_screen.dart': 1,
  };
  for (final e in screens.entries) {
    test('${e.key}: ролик не молчит и итог виден', () {
      final src = File(e.key).readAsStringSync();
      expect(RegExp(r'showAdNotEarned\(').allMatches(src).length, greaterThanOrEqualTo(e.value),
          reason: 'незасчитанный ролик обязан сказать об этом');
      expect(src.contains('untilAppVisible()'), isTrue, reason: 'итог — после закрытия рекламы');
    });
  }

  test('ролика нет — «реклама не готова», а не «не засчитан»', () {
    for (final f in ['lib/screens/draw_screen.dart', 'lib/screens/widget_screen.dart', 'lib/screens/profile_screen.dart']) {
      expect(File(f).readAsStringSync().contains('ensureAdReady('), isTrue, reason: f);
    }
  });

  test('проба фона из листа говорит поверх листа', () {
    final src = File('lib/screens/draw_screen.dart').readAsStringSync();
    expect(src.contains('showAdNotEarned(context, overSheet: true)'), isTrue);
  });

  test('копии ожидания экрана нет: одна на всё приложение', () {
    expect(File('lib/screens/chest_screen.dart').readAsStringSync().contains('Future<void> _untilVisible'), isFalse);
    expect(File('lib/screens/gifts/gift_shop_screen.dart').readAsStringSync().contains('Future<void> _untilVisible'), isFalse);
  });

  test('подарок и значок подтверждаются листом с самой вещью', () {
    final src = File('lib/screens/gifts/gift_shop_screen.dart').readAsStringSync();
    expect(src.contains("trKey('giftSentTitle')"), isTrue);
    expect(src.contains("trKey('badgeObtainedTitle')"), isTrue);
  });
}
