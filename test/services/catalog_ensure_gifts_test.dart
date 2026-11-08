import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
