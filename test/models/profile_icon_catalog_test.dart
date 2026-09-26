import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/profile_icon.dart';

/// Значки профиля серверные: строка каталога (`catalog_items`, kind='badge')
/// превращается в [ProfileIcon]. Новый значок добавляется записью на сервере,
/// поэтому разбор обязан переживать неполные и чужие строки, а не падать.
Map<String, dynamic> row({
  String key = 'Fish',
  int price = 0,
  bool grantOnly = true,
  bool enabled = true,
  String kind = 'badge',
  int sort = 920,
  Map<String, String>? name,
}) =>
    {
      'id': 'badge_fish',
      'kind': kind,
      'price': price,
      'sort': sort,
      'enabled': enabled,
      'data': {
        'key': key,
        'rarity': grantOnly ? 'award' : 'common',
        'grantOnly': grantOnly,
        'name': name ?? {'ru': 'Рыбка', 'en': 'Fish', 'de': 'Fischlein'},
        'desc': {'ru': 'За вклад', 'en': 'For help'},
        'sm': 'https://x/sm.webp',
        'lg': 'https://x/lg.webp',
        'still': 'https://x/still.png',
      },
    };

void main() {
  group('Значок из строки каталога', () {
    test('разбирает ключ, цену, наградной флаг и адреса', () {
      final i = ProfileIcon.fromCatalog(row(key: 'Paw', price: 20, grantOnly: false))!;
      expect(i.id, 'Paw');
      expect(i.price, 20);
      expect(i.grantOnly, isFalse);
      expect(i.rarity, 'common');
      expect(i.smUrl, 'https://x/sm.webp');
      expect(i.lgUrl, 'https://x/lg.webp');
      expect(i.stillUrl, 'https://x/still.png');
    });

    test('чужой вид строки — не значок', () {
      expect(ProfileIcon.fromCatalog(row(kind: 'mood_pack')), isNull);
    });

    test('без ключа или без картинок значка нет', () {
      final noKey = row()..['data'] = {...(row()['data'] as Map), 'key': ''};
      expect(ProfileIcon.fromCatalog(noKey), isNull);
      final noPics = row();
      (noPics['data'] as Map).remove('sm');
      (noPics['data'] as Map).remove('lg');
      (noPics['data'] as Map).remove('still');
      expect(ProfileIcon.fromCatalog(noPics), isNull);
    });

    test('у наградного значка цены нет, даже если в записи она стоит', () {
      final i = ProfileIcon.fromCatalog(row(price: 50, grantOnly: true))!;
      expect(i.price, 0);
    });

    test('название на языке человека, иначе английское, иначе русское, иначе ключ', () {
      final i = ProfileIcon.fromCatalog(row())!;
      expect(i.nameIn('de'), 'Fischlein');
      expect(i.nameIn('fr'), 'Fish');
      final ruOnly = ProfileIcon.fromCatalog(row(name: {'ru': 'Рыбка'}))!;
      expect(ruOnly.nameIn('fr'), 'Рыбка');
      final none = ProfileIcon.fromCatalog(row(name: {}))!;
      expect(none.nameIn('ru'), 'Fish');
    });

    test('мелкий показ берёт маленькую анимацию, крупный — большую', () {
      final i = ProfileIcon.fromCatalog(row())!;
      expect(i.urlFor(38), 'https://x/sm.webp');
      expect(i.urlFor(64), 'https://x/sm.webp');
      expect(i.urlFor(120), 'https://x/lg.webp');
      expect(i.urlFor(38, animated: false), 'https://x/still.png');
    });

    test('нет нужного размера — берётся тот, что есть', () {
      final r = row();
      (r['data'] as Map).remove('sm');
      final i = ProfileIcon.fromCatalog(r)!;
      expect(i.urlFor(38), 'https://x/lg.webp');
    });
  });

  group('Каталог значков целиком', () {
    test('порядок по sort, выключенные не попадают', () {
      final list = ProfileIcon.parseCatalog([
        row(key: 'Fish', sort: 920),
        row(key: 'Paw', price: 20, grantOnly: false, sort: 10),
        row(key: 'Old', price: 20, grantOnly: false, sort: 5, enabled: false),
        {'kind': 'mood_pack', 'data': {}},
        'мусор',
      ]);
      expect(list.map((i) => i.id), ['Paw', 'Fish']);
    });
  });
}
