import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/avatar_frame.dart';

/// Рамки приезжают серверным каталогом, запись заводит `upload_badges.py`
/// по `frame.json`. Кривая строка, заведённая руками, не имеет права ронять
/// магазин, а ключ владения обязан совпадать с тем, что кладёт сундук
/// (`chest.pb.js`: `"frame:" + id записи`).
void main() {
  Map<String, dynamic> row({Object? kind = 'frame', Object? data, Object? enabled = true}) => {
        'id': 'frame_cat',
        'kind': kind,
        'enabled': enabled,
        'price': 0,
        'sort': 90,
        'data': data ??
            {
              'key': 'cat',
              'rarity': 'legendary',
              'name': {'ru': 'Котик', 'en': 'Kitty'},
              'desc': {'ru': 'Ушки дёргаются'},
              'sm': 'https://x/sm.webp',
              'lg': 'https://x/lg.webp',
              'still': 'https://x/still.png',
            },
      };

  test('рамка из строки каталога — без цены, она не продаётся', () {
    final f = AvatarFrame.fromCatalog(row())!;
    expect(f.key, 'cat');
    expect(f.rarity, 'legendary');
    expect(f.nameIn('ru'), 'Котик');
    expect(f.nameIn('de'), 'Kitty', reason: 'нет языка — английский');
    expect(f.descriptionIn('fr'), 'Ушки дёргаются', reason: 'дальше русский');
  });

  test('ключ владения тот же, что кладёт сундук', () {
    expect(AvatarFrame.catalogIdOf('cat'), 'frame_cat');
    expect(AvatarFrame.featureKeyOf('cat'), 'frame:frame_cat');
  });

  test('кривые строки пропускаются, а не роняют разбор', () {
    final rows = [
      row(),
      row(kind: 'badge'),
      row(enabled: false),
      row(data: {'key': '', 'sm': 'https://x'}),
      row(data: {'key': 'nopic'}),
      row(data: 'не карта'),
    ];
    expect(AvatarFrame.parseCatalog(rows).map((f) => f.key), ['cat']);
  });

  test('размер картинки под место на экране', () {
    final f = AvatarFrame.fromCatalog(row())!;
    expect(f.urlFor(64), 'https://x/sm.webp');
    expect(f.urlFor(200), 'https://x/lg.webp');
    expect(f.urlFor(200, animated: false), 'https://x/still.png');
  });

  test('заглушка из сборки есть у первых девяти, у новых её нет', () {
    expect(AvatarFrame.assetFor('cat'), 'assets/images/frames/cat.webp');
    expect(AvatarFrame.assetFor('new_one'), isNull);
  });
}
