import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/avatar_frame.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Подарок осеннего сундука, которого нет в каталоге на телефоне, догружается
/// одной записью, а не всем каталогом. Весь каталог — 5,6 тысячи записей и
/// 2,5 МБ, на плохой сети он за 8 секунд не приходил: в 1.41 за неделю 189
/// открытий «не открылось» с `unknown_prize` (сервер приз выдал), а в запасе
/// сундука такие подарки не показывались вовсе — отзыв в App Store 26.10.2026
/// «вещи из сундука просто пропадают».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <Uri>[];

  Map<String, dynamic> giftRow(String key) => {
        'id': 'gift_$key',
        'collectionId': 'c',
        'collectionName': 'catalog_items',
        'kind': 'gift',
        'enabled': true,
        'name_ru': 'Пирог',
        'name_en': 'Pie',
        'data': {'key': key, 'set': 'autumn', 'rarity': 'common', 'sm': 'https://x/$key.webp'},
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
    GiftCatalog.registerSeasonal(const {});
    CatalogService.instance.debugApply([
      {
        'id': 'splash_love',
        'kind': 'splash',
        'data': {
          'key': 'love',
          'ms': 1800,
          'step': 20,
          'until': '',
          'sort': 1,
          'window': {
            'path': 'M0,0 Z',
            'track': [
              [180, 372, 0],
            ],
          },
          'sprites': {
            'door': {
              'frames': ['door'],
              'box': [0, 0, 360, 780],
            },
          },
          'layers': [
            {'sprite': 'door', 'fill': true, 'under': true},
          ],
          'files': {'door': 'https://x/door.webp', 'still': 'https://x/still.webp'},
        },
      },
    ]);
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        requests.add(req.url);
        final filter = req.url.queryParameters['filter'] ?? '';
        final items = [
          if (filter.contains("'gift_au_pie'")) giftRow('au_pie'),
          if (filter.contains("'frame_au_books'"))
            {
              'id': 'frame_au_books',
              'collectionId': 'c',
              'collectionName': 'catalog_items',
              'kind': 'frame',
              'enabled': true,
              'data': {
                'key': 'au_books',
                'name': {'ru': 'Книги'},
                'lg': 'https://x/au_books.webp',
              },
            },
          for (final k in ['chest_idle2', 'chest_open2', 'chest_hold2'])
            if (filter.contains("'art_$k'"))
              {
                'id': 'art_$k',
                'collectionId': 'c',
                'collectionName': 'catalog_items',
                'kind': 'art',
                'enabled': true,
                'data': {'key': k, 'lg': 'https://x/$k.webp'},
              },
        ];
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'page': 1,
            'perPage': 50,
            'totalItems': items.length,
            'totalPages': 1,
            'items': items,
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ));
  });

  tearDown(() => GiftCatalog.registerSeasonal(const {}));

  test('незнакомый подарок приходит одной записью', () async {
    expect(GiftCatalog.byKey('au_pie'), isNull);

    await CatalogService.instance.ensureGifts({'au_pie'});

    expect(GiftCatalog.byKey('au_pie')?.titleRu, 'Пирог');
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['filter'], contains("'gift_au_pie'"));
  });

  test('остальной каталог при этом не теряется', () async {
    await CatalogService.instance.ensureGifts({'au_pie'});

    expect(CatalogService.instance.splashesOn(DateTime(2026, 11, 8)).map((s) => s.key), ['love']);
  });

  test('знакомые подарки — без похода на сервер', () async {
    await CatalogService.instance.ensureGifts({'rose'});

    expect(requests, isEmpty);
  });

  // Обращение 653: рамка из сундука выходила подписью «Рамка au_books», а
  // обычный сундук стоял закрытым — каталог целиком на телефон не дошёл.
  test('незнакомая рамка приходит одной записью', () async {
    expect(AvatarFrame.byKey('au_books'), isNull);

    await CatalogService.instance.ensureFrames({'au_books'});

    expect(AvatarFrame.byKey('au_books')?.names['ru'], 'Книги');
    expect(requests, hasLength(1));
    await CatalogService.instance.ensureFrames({'au_books'});
    expect(requests, hasLength(1));
  });

  test('картинки обычного сундука дотягиваются, когда их нет', () async {
    expect(CatalogService.instance.giftArt('chest_open2'), isNull);

    await CatalogService.instance.ensureChestArt();

    expect(CatalogService.instance.giftArt('chest_open2')?.lgUrl, 'https://x/chest_open2.webp');
    expect(CatalogService.instance.giftArt('chest_idle2')?.lgUrl, isNotNull);
    expect(requests, hasLength(1));
    await CatalogService.instance.ensureChestArt();
    expect(requests, hasLength(1));
  });
}
