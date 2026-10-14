import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_sticker.dart';

MemorySticker _s(String id, String uid,
        {double x = .5, double y = .5, int at = 0}) =>
    MemorySticker(
      id: id,
      uid: uid,
      image: 'assets/images/mood_packs/bunny/love.webp',
      pack: 'bunny',
      mood: 'love',
      x: x,
      y: y,
      at: at,
    );

void main() {
  group('разбор', () {
    test('карта id → наклейка читается и сортируется по времени', () {
      final list = parseStickers({
        'b': _s('b', 'u2', at: 200).toJson(),
        'a': _s('a', 'u1', at: 100).toJson(),
      });
      expect(list.map((s) => s.id), ['a', 'b']);
      expect(list.first.uid, 'u1');
      expect(list.first.pack, 'bunny');
    });

    test('круг toJson → parseStickers сохраняет всё', () {
      final s = MemorySticker(
        id: 'k1',
        uid: 'u1',
        image: 'https://togetherly.day/api/files/catalog_items/dog/love_l1f07p337t.webp',
        pack: 'dog',
        mood: 'love',
        x: .25,
        y: .75,
        size: .4,
        angle: .5,
        at: 1700000000000,
      );
      final back = parseStickers(stickersToJson([s])).single;
      expect(back.id, 'k1');
      expect(back.image, s.image);
      expect(back.x, .25);
      expect(back.y, .75);
      expect(back.size, .4);
      expect(back.angle, .5);
      expect(back.at, 1700000000000);
    });

    test('битая наклейка выбрасывается, остальные остаются', () {
      final list = parseStickers({
        'ok': _s('ok', 'u1').toJson(),
        'no-uid': {..._s('no-uid', '').toJson()},
        'bad-img': {..._s('bad-img', 'u1').toJson(), 'img': 'file:///etc/passwd'},
        'junk': 'строка вместо карты',
      });
      expect(list.map((s) => s.id), ['ok']);
    });

    test('не карта — пустой список, лента не падает', () {
      expect(parseStickers(null), isEmpty);
      expect(parseStickers('x'), isEmpty);
      expect(parseStickers([1, 2]), isEmpty);
    });

    test('значения за пределами прижимаются', () {
      final s = parseStickers({
        'a': {
          ..._s('a', 'u1').toJson(),
          'x': 3.0,
          'y': -2.0,
          's': 9.0,
          'r': 7.0,
        },
      }).single;
      expect(s.x, 1.0);
      expect(s.y, 0.0);
      expect(s.size, kStickerMaxSize);
      expect(s.angle, closeTo(7.0 - 2 * math.pi, 1e-9));
    });
  });

  group('картинка', () {
    test('берутся ассеты сборки и картинки каталога', () {
      expect(stickerImageAllowed('assets/images/new emodji/Счастье.webp'), isTrue);
      expect(
          stickerImageAllowed(
              'https://togetherly.day/api/files/catalog_items/moti/love_uethoqf2ox.webp'),
          isTrue);
      expect(
          stickerImageAllowed(
              'https://togetherly.duckdns.org/api/files/catalog_items/dog/love_l1f07p337t.webp'),
          isTrue);
    });

    test('чужие адреса и выход из папки не берутся', () {
      expect(stickerImageAllowed(''), isFalse);
      expect(stickerImageAllowed('https://evil.example/a.webp'), isFalse);
      expect(stickerImageAllowed('assets/../secret'), isFalse);
      expect(
          stickerImageAllowed('https://togetherly.day/api/files/media/x/y.webp'),
          isFalse);
      expect(stickerImageAllowed('assets/images/${'a' * 400}'), isFalse);
    });
  });

  group('права и предел', () {
    test('своих наклеек до трёх на запись', () {
      final list = [_s('1', 'me'), _s('2', 'me'), _s('3', 'partner')];
      expect(canAddSticker(list, 'me'), isTrue);
      expect(canAddSticker([...list, _s('4', 'me')], 'me'), isFalse);
      expect(canAddSticker([...list, _s('4', 'me')], 'partner'), isTrue);
      expect(canAddSticker(list, ''), isFalse);
    });

    test('переставить можно только свою', () {
      expect(canMoveSticker(_s('1', 'me'), 'me'), isTrue);
      expect(canMoveSticker(_s('1', 'partner'), 'me'), isFalse);
    });

    test('убрать можно свою, а на своём пине и чужую', () {
      expect(canRemoveSticker(_s('1', 'me'), uid: 'me', authorUid: 'partner'),
          isTrue);
      expect(
          canRemoveSticker(_s('1', 'partner'), uid: 'me', authorUid: 'me'),
          isTrue);
      expect(
          canRemoveSticker(_s('1', 'partner'),
              uid: 'me', authorUid: 'partner'),
          isFalse);
      expect(canRemoveSticker(_s('1', 'me'), uid: '', authorUid: ''), isFalse);
    });
  });

  group('карта в data записи', () {
    test('наклейка добавляется и убирается, чужие на месте', () {
      final data = <String, dynamic>{
        'stickers': stickersToJson([_s('p', 'partner', at: 1)]),
      };
      final added = withSticker(data, _s('m', 'me', at: 2));
      expect(parseStickers(added['stickers']).map((s) => s.id), ['p', 'm']);
      final removed = withoutSticker(added, 'p');
      expect(parseStickers(removed['stickers']).map((s) => s.id), ['m']);
      // Исходная карта не тронута: кэш правится копией.
      expect(parseStickers(data['stickers']).map((s) => s.id), ['p']);
    });
  });

  test('Memory читает наклейки из json и кладёт обратно', () {
    final m = Memory.fromJson({
      'id': 'mem',
      'type': 'photo',
      'createdAt': '2026-10-14T10:00:00.000Z',
      'stickers': stickersToJson([_s('a', 'u1', x: .2, y: .3)]),
    });
    expect(m.stickers.single.x, .2);
    final back = Memory.fromJson(m.toJson());
    expect(back.stickers.single.id, 'a');
    expect(back.stickers.single.y, .3);
  });
}
