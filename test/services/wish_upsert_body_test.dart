import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/services/pb_data_service.dart';

/// Вещь в списке желаний обязана доезжать до сервера целиком.
///
/// Жалоба 8 августа 2026: «не работает добавление ссылки, иконка вб появлялась
/// и сразу пропадала». `Wish.toMap` клал `kind`, `price`, `currency`, `url`,
/// `image`, `shop`, а тело запроса собиралось отдельно и все шесть полей
/// теряло. Желание сохранялось локально со ссылкой (в списке загоралась
/// стрелка), на сервер уходило без неё, и первый же живой снимок затирал
/// ссылку пустотой. Форма правки после этого открывалась с пустым полем.
void main() {
  final wish = Wish(
    id: 'w1',
    authorUid: 'u1',
    title: 'Одеяло тяжёлое',
    categoryId: 'other',
    isItem: true,
    price: 4990,
    currency: 'RUB',
    url: 'https://www.wildberries.ru/catalog/247807538/detail.aspx',
    image: 'pb://media/abc/photo.webp',
    shop: 'Wildberries',
    createdAt: DateTime.utc(2026, 8, 8),
  );

  test('поля вещи есть в теле запроса', () {
    final body = PbDataService.wishUpsertBody('g1', wish.toMap(groupId: 'g1'));

    expect(body['kind'], 'item');
    expect(body['price'], 4990);
    expect(body['currency'], 'RUB');
    expect(body['url'], wish.url);
    expect(body['image'], wish.image);
    expect(body['shop'], 'Wildberries');
  });

  test('дело остаётся делом и цену не выдумывает', () {
    final deed = Wish(
      id: 'w2',
      authorUid: 'u1',
      title: 'Сходить в кино',
      categoryId: 'movie',
      createdAt: DateTime.utc(2026, 8, 8),
    );
    final body = PbDataService.wishUpsertBody('g1', deed.toMap(groupId: 'g1'));

    expect(body['kind'], 'deed');
    expect(body['price'], 0);
    expect(body['url'], '');
    expect(body['image'], '');
  });

  test('стёртая ссылка стирается и на сервере', () {
    // Пустая строка обязана доехать: иначе снятую ссылку не убрать, как это уже
    // было с фото в виджетах.
    final cleared = wish.copyWith(url: '', image: '', shop: '');
    final body =
        PbDataService.wishUpsertBody('g1', cleared.toMap(groupId: 'g1'));

    expect(body.containsKey('url'), isTrue);
    expect(body['url'], '');
    expect(body['image'], '');
    expect(body['shop'], '');
  });

  test('прежние поля никуда не делись', () {
    final body = PbDataService.wishUpsertBody('g1', wish.toMap(groupId: 'g1'));

    expect(body['group_id'], 'g1');
    expect(body['author_uid'], 'u1');
    expect(body['title'], 'Одеяло тяжёлое');
    expect(body['category'], 'other');
    expect(body['done'], false);
  });
}
