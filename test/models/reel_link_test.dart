import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/reel_link.dart';

void main() {
  group('ReelLink.parse', () {
    test('площадка из ключа, номер без площадки — Shorts', () {
      expect(ReelLink.parse('tiktok:7425816398148013344')!.source, 'tiktok');
      final old = ReelLink.parse('aqz-KE-bpKQ')!;
      expect(old.source, 'shorts');
      expect(old.key, 'shorts:aqz-KE-bpKQ');
    });

    test('битые ключи не проходят', () {
      expect(ReelLink.parse(''), isNull);
      expect(ReelLink.parse('youtube:aqz-KE-bpKQ'), isNull);
      expect(ReelLink.parse('shorts:ab'), isNull);
      expect(ReelLink.parse('shorts:<script>'), isNull);
      expect(ReelLink.parse('vk:123456789'), isNull);
    });
  });

  group('адрес ролика', () {
    test('у каждой площадки свой, а не Shorts', () {
      expect(ReelLink.parse('shorts:aqz-KE-bpKQ')!.url, 'https://youtube.com/shorts/aqz-KE-bpKQ');
      expect(ReelLink.parse('tiktok:7425816398148013344')!.url, 'https://www.tiktok.com/@/video/7425816398148013344');
      expect(ReelLink.parse('rutube:1ee26921edb653d7c94c65f9281ad20e')!.url,
          'https://rutube.ru/shorts/1ee26921edb653d7c94c65f9281ad20e/');
      expect(ReelLink.parse('vk:-220754053_456239310_abcdef0123')!.url, 'https://vk.com/clip-220754053_456239310');
      expect(ReelLink.parse('dzen:vMcd34Fq0AaS')!.url, 'https://dzen.ru/embed/vMcd34Fq0AaS');
    });

    test('страница строит те же адреса (reels.js, watchUrl)', () {
      final js = File('pocketbase/pb_public/watch/room/reels.js').readAsStringSync();
      for (final part in [
        "'https://www.tiktok.com/@/video/' + id",
        "'https://rutube.ru/shorts/' + id + '/'",
        "'https://vk.com/clip' + p[0] + '_' + p[1]",
        "'https://dzen.ru/embed/' + id",
        "'https://youtube.com/shorts/' + id",
      ]) {
        expect(js.contains(part), isTrue, reason: part);
      }
      expect(js.contains("reelsSave"), isTrue);
    });

    test('хеш ВК в адрес не попадает', () {
      expect(ReelLink.parse('vk:-1_2_deadbeef')!.url.contains('deadbeef'), isFalse);
    });

    test('обложку без запроса знает только YouTube', () {
      expect(ReelLink.parse('shorts:aqz-KE-bpKQ')!.knownThumb, 'https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg');
      expect(ReelLink.parse('rutube:1ee26921edb653d7c94c65f9281ad20e')!.knownThumb, isNull);
    });

    test('данные спрашиваем у тех, кто их отдаёт', () {
      expect(ReelLink.parse('shorts:aqz-KE-bpKQ')!.metaUri!.host, 'www.youtube.com');
      expect(ReelLink.parse('rutube:1ee26921edb653d7c94c65f9281ad20e')!.metaUri!.path,
          '/api/video/1ee26921edb653d7c94c65f9281ad20e/');
      expect(ReelLink.parse('vk:-1_2_3abc')!.metaUri, isNull);
      expect(ReelLink.parse('dzen:vMcd34Fq0AaS')!.metaUri, isNull);
    });
  });

  group('ReelMeta', () {
    test('oEmbed YouTube и TikTok', () {
      final m = ReelMeta.fromJson({
        'title': 'Big Buck Bunny',
        'author_name': 'Blender',
        'thumbnail_url': 'https://i.ytimg.com/vi/x/hqdefault.jpg',
      });
      expect(m.title, 'Big Buck Bunny');
      expect(m.author, 'Blender');
      expect(m.thumb, 'https://i.ytimg.com/vi/x/hqdefault.jpg');
    });

    test('Rutube кладёт автора объектом', () {
      final m = ReelMeta.fromJson({
        'title': 'Котик',
        'thumbnail_url': 'https://pic.rtbcdn.ru/a.jpg',
        'author': {'name': 'Канал'},
      });
      expect(m.author, 'Канал');
    });

    test('чужая форма ответа даёт пустые поля', () {
      expect(ReelMeta.fromJson('ratelimit triggered').title, isNull);
      expect(ReelMeta.fromJson({'title': '  ', 'author': 'строкой'}).title, isNull);
      expect(ReelMeta.fromJson({'author': 'строкой'}).author, isNull);
    });
  });
}
