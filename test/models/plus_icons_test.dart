import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/profile_icon.dart';

/// Togetherly+ открывает значки профиля, которые иначе стоят по 20 монет.
/// Наградные значки (Sponsor, Helper) покупка НЕ открывает: их выдают руками, и
/// если их можно будет купить, они перестанут что-либо значить.
void main() {
  group('Каталог значков', () {
    test('Покупаемые значки не включают наградные', () {
      expect(ProfileIcon.purchasable, isNotEmpty);
      expect(ProfileIcon.purchasable.every((i) => !i.grantOnly), isTrue);
    });

    test('В каталоге есть хотя бы один наградной значок', () {
      expect(ProfileIcon.all.any((i) => i.grantOnly), isTrue,
          reason: 'иначе проверять разделение не на чем');
    });

    test('ById находит значок и отличает наградной от платного', () {
      final paid = ProfileIcon.purchasable.first;
      final granted = ProfileIcon.all.firstWhere((i) => i.grantOnly);

      expect(ProfileIcon.byId(paid.id)?.grantOnly, isFalse);
      expect(ProfileIcon.byId(granted.id)?.grantOnly, isTrue);
      expect(ProfileIcon.byId('нет-такого'), isNull);
      expect(ProfileIcon.byId(null), isNull);
    });

    test('У платных значков есть цена, у наградных её быть не должно', () {
      for (final icon in ProfileIcon.purchasable) {
        expect(icon.price, greaterThan(0), reason: 'значок ${icon.id}');
      }
    });
  });
}
