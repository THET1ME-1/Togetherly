import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish.dart';

void main() {
  test('снятая галочка оставляет вещь вещью', () {
    final item = Wish(
      id: 'w1',
      title: 'Куртка',
      authorUid: 'u1',
      isItem: true,
      price: 12990,
      currency: '₽',
      url: 'https://example.com/k',
      image: 'pb://media/abc/k.webp',
      shop: 'example.com',
      createdAt: DateTime(2026, 9, 1),
    ).markDone(by: 'u2', at: DateTime(2026, 9, 20));

    final back = item.undone();

    expect(back.done, isFalse);
    expect(back.doneAt, isNull);
    expect(back.doneBy, isEmpty);
    expect(back.isItem, isTrue);
    expect(back.price, 12990);
    expect(back.currency, '₽');
    expect(back.url, 'https://example.com/k');
    expect(back.image, 'pb://media/abc/k.webp');
    expect(back.shop, 'example.com');
    expect(back.toMap(groupId: 'g')['kind'], 'item');
  });
}
