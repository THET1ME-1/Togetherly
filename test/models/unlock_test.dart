import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/level.dart';

/// Требование разблокировки элемента каталога.
///
/// Смысл всей затеи — платный персонаж должен заводиться ОДНОЙ записью в
/// каталоге и продаваться сразу, без новой сборки приложения. Поэтому цена
/// приходит из манифеста, а не живёт списком в коде.
void main() {
  group('Разбор из манифеста', () {
    test('Пусто и незнакомое — бесплатно', () {
      expect(Unlock.fromJson(null).isFree, isTrue);
      expect(Unlock.fromJson({'type': 'колдовство'}).isFree, isTrue);
    });

    test('По уровню', () {
      final u = Unlock.fromJson({'type': 'level', 'level': 7});
      expect(u.requiredLevel, 7);
      expect(u.isUnlocked(level: 6, owned: false, plus: false), isFalse);
      expect(u.isUnlocked(level: 7, owned: false, plus: false), isTrue);
    });

    test('За монеты — цена приходит из каталога', () {
      final u = Unlock.fromJson({'type': 'premium', 'price': 120});
      expect(u.isPremium, isTrue);
      expect(u.price, 120);
    });

    test('Премиум без цены не продаётся, но и не притворяется бесплатным', () {
      // Цену забыли положить в каталог: показывать «купить за 0» нельзя, а
      // отдавать даром — тем более.
      final u = Unlock.fromJson({'type': 'premium'});
      expect(u.isPremium, isTrue);
      expect(u.price, 0);
      expect(u.isForSale, isFalse);
    });

    test('Открывается по Togetherly+', () {
      final u = Unlock.fromJson({'type': 'premium', 'price': 120, 'plus': true});
      expect(u.plusIncluded, isTrue);
    });

    test('Битая цена не пускает элемент в продажу', () {
      expect(Unlock.fromJson({'type': 'premium', 'price': 'дорого'}).price, 0);
      expect(Unlock.fromJson({'type': 'premium', 'price': -5}).isForSale, isFalse);
    });
  });

  group('Кому открыт платный элемент', () {
    final paid = Unlock.fromJson({'type': 'premium', 'price': 120});

    test('Не купил — закрыт', () {
      expect(paid.isUnlocked(level: 99, owned: false, plus: false), isFalse);
    });

    test('Купил — открыт', () {
      expect(paid.isUnlocked(level: 1, owned: true, plus: false), isTrue);
    });

    test('Togetherly+ сам по себе платный элемент не открывает', () {
      // Иначе любой платный персонаж достался бы подписчикам даром, а это
      // решается в каталоге флагом, а не по умолчанию.
      expect(paid.isUnlocked(level: 1, owned: false, plus: true), isFalse);
    });

    test('А с флагом в каталоге — открывает', () {
      final withPlus =
          Unlock.fromJson({'type': 'premium', 'price': 120, 'plus': true});
      expect(withPlus.isUnlocked(level: 1, owned: false, plus: true), isTrue);
      expect(withPlus.isUnlocked(level: 1, owned: false, plus: false), isFalse);
    });

    test('Купленное остаётся у человека и без Плюса', () {
      final withPlus =
          Unlock.fromJson({'type': 'premium', 'price': 120, 'plus': true});
      expect(withPlus.isUnlocked(level: 1, owned: true, plus: false), isTrue);
    });
  });

  group('Ключ владения', () {
    test('Маскот подписывается своим видом', () {
      // Владение лежит в общем `owned_features`, поэтому ключ обязаннести вид
      // элемента: иначе маскот и пак с одинаковым id смешались бы.
      expect(Unlock.featureKey('mascot', 'kuku'), 'mascot:kuku');
    });
  });
}
