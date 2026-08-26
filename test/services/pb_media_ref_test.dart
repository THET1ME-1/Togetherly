import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pb_media_ref.dart';

/// Голый адрес защищённого файла возвращается к схеме `pb://`.
///
/// Коллекция `media` защищённая: без `?token=` сервер отвечает 404. Токен
/// подставлялся только к ссылкам `pb://`, а в записях с давних пор лежат и
/// готовые `https://togetherly.day/api/files/media/…` — за две недели 152
/// таких запроса ушли в пустоту, и картинка у человека не открывалась.
void main() {
  group('pbRefFromUrl', () {
    test('наш адрес файла переводится в pb-ссылку', () {
      expect(
        pbRefFromUrl('https://togetherly.day/api/files/media/abc123/photo.jpg'),
        'pb://media/abc123/photo.jpg',
      );
    });

    test('легаси-домен понимается так же', () {
      // Ссылки с duckdns разосланы людьми и живут в старых записях.
      expect(
        pbRefFromUrl('https://togetherly.duckdns.org/api/files/media/x1/y.webp'),
        'pb://media/x1/y.webp',
      );
    });

    test('хвост с токеном отбрасывается — токен всё равно протух', () {
      expect(
        pbRefFromUrl('https://togetherly.day/api/files/media/a/b.png?token=old'),
        'pb://media/a/b.png',
      );
    });

    test('другие коллекции тоже наши', () {
      expect(
        pbRefFromUrl('https://togetherly.day/api/files/catalog_items/i/f.webp'),
        'pb://catalog_items/i/f.webp',
      );
    });

    test('чужой домен не трогаем', () {
      expect(pbRefFromUrl('https://example.com/api/files/media/a/b.jpg'), isNull);
    });

    test('не файловый путь не трогаем', () {
      expect(pbRefFromUrl('https://togetherly.day/watch/room/'), isNull);
      expect(pbRefFromUrl('https://togetherly.day/api/collections/media/records'),
          isNull);
    });

    test('обрезанный путь не превращается в мусорную ссылку', () {
      expect(pbRefFromUrl('https://togetherly.day/api/files/media/only-id'), isNull);
      expect(pbRefFromUrl('https://togetherly.day/api/files/'), isNull);
    });

    test('уже pb-ссылку не трогаем', () {
      expect(pbRefFromUrl('pb://media/a/b.jpg'), isNull);
    });

    test('пустое и локальные пути мимо', () {
      expect(pbRefFromUrl(''), isNull);
      expect(pbRefFromUrl('/data/user/0/files/photo.jpg'), isNull);
      expect(pbRefFromUrl(null), isNull);
    });
  });
}
