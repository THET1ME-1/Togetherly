import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/models/gift_art.dart';

/// Рисунок подарка приезжает серверным каталогом (`catalog_items`, вид
/// `gift`), а без сети остаётся неподвижный кадр из сборки. Кривая строка
/// каталога не должна ломать магазин, а у каждого подарка кадр обязан лежать.
Map<String, dynamic> row({String kind = 'gift', bool enabled = true, Map<String, dynamic>? data}) => {
      'id': 'gift_cake',
      'kind': kind,
      'enabled': enabled,
      'data': data ?? {'key': 'cake', 'sm': 'https://x/sm.webp', 'lg': 'https://x/lg.webp', 'still': 'https://x/still.png'},
    };

void main() {
  test('разбирает ключ и три адреса', () {
    final a = GiftArt.fromCatalog(row())!;
    expect(a.key, 'cake');
    expect(a.urlFor(46), 'https://x/sm.webp');
    expect(a.urlFor(170), 'https://x/lg.webp');
    expect(a.urlFor(170, animated: false), 'https://x/still.png');
  });

  test('чужой вид, выключенная запись, пустой ключ, нет картинок — null', () {
    expect(GiftArt.fromCatalog(row(kind: 'badge')), isNull);
    expect(GiftArt.fromCatalog(row(enabled: false)), isNull);
    expect(GiftArt.fromCatalog(row(data: {'key': '', 'sm': 'https://x'})), isNull);
    expect(GiftArt.fromCatalog(row(data: {'key': 'cake'})), isNull);
  });

  test('нет нужного размера — берётся тот, что есть', () {
    final a = GiftArt.fromCatalog(row(data: {'key': 'cake', 'lg': 'https://x/lg.webp'}))!;
    expect(a.urlFor(40), 'https://x/lg.webp');
  });

  test('у каждого подарка в сборке лежит неподвижный кадр, у торта — и без огня', () {
    for (final g in GiftCatalog.all) {
      expect(File(g.asset).existsSync(), isTrue, reason: g.asset);
    }
    expect(File('assets/images/gifts/cake_out.webp').existsSync(), isTrue);
  });
}
