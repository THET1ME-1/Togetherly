import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/models/gift.dart';
import 'package:love_app/services/chest_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// TOG-10: «первый подарок из сундука у меня не отобразился». Подарок, по
/// которому не выбрали «Подарить» или «Оставить себе», лежит в запасе. Запас
/// пропускал подарки, которых сборка ещё не знает: сезонные она узнаёт из
/// каталога, и до его приезда подарок молча пропадал из виду.
void main() {
  late Future<void> Function() original;

  void serverStash(List<Map<String, dynamic>> items) {
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'page': 1,
              'perPage': 100,
              'totalItems': items.length,
              'totalPages': 1,
              'items': [
                for (final i in items) {'collectionId': 'c', 'collectionName': 'chest_opens', 'state': 'stash', ...i},
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    ));
  }

  const cocoa = Gift(key: 'cocoa', price: 0, engine: GiftEngine.response, titleRu: 'Какао', titleEn: 'Cocoa');

  setUp(() {
    original = ChestService.catalogRefresh;
    GiftCatalog.registerSeasonal(const {});
  });

  tearDown(() {
    ChestService.catalogRefresh = original;
    GiftCatalog.registerSeasonal(const {});
  });

  test('подарок сезона до каталога не пропадает из запаса', () async {
    serverStash([
      {'id': 'aaaaaaaaaaaaaa1', 'prize': 'cocoa', 'day': 'hw|2026-10-20'},
      {'id': 'aaaaaaaaaaaaaa2', 'prize': 'rose', 'day': '2026-10-21'},
    ]);
    var refreshed = 0;
    ChestService.catalogRefresh = () async {
      refreshed++;
      GiftCatalog.registerSeasonal({'cocoa': cocoa});
    };

    final items = await ChestService.instance.stash();

    expect([for (final i in items) i.giftKey], ['cocoa', 'rose']);
    expect(refreshed, 1);
  });

  test('знакомые подарки — без похода за каталогом', () async {
    serverStash([
      {'id': 'aaaaaaaaaaaaaa2', 'prize': 'rose', 'day': '2026-10-21'},
    ]);
    var refreshed = 0;
    ChestService.catalogRefresh = () async => refreshed++;

    final items = await ChestService.instance.stash();

    expect([for (final i in items) i.giftKey], ['rose']);
    expect(refreshed, 0);
  });

  test('каждый подарок знает свой сундук', () async {
    serverStash([
      {'id': 'aaaaaaaaaaaaaa1', 'prize': 'rose', 'day': 'hw|2026-10-20'},
      {'id': 'aaaaaaaaaaaaaa2', 'prize': 'teddy', 'day': '+hw|2026-10-20'},
      {'id': 'aaaaaaaaaaaaaa3', 'prize': 'potion', 'day': '2026-10-21'},
      {'id': 'aaaaaaaaaaaaaa4', 'prize': 'record', 'day': 'b2026-10-21'},
    ]);

    final items = await ChestService.instance.stash();

    expect([for (final i in items) i.chest], ['hw', 'hw', null, null]);
  });

  test('подарка нет и в свежем каталоге — пропускаем только его', () async {
    serverStash([
      {'id': 'aaaaaaaaaaaaaa1', 'prize': 'gift_from_next_year', 'day': '2026-10-20'},
      {'id': 'aaaaaaaaaaaaaa2', 'prize': 'rose', 'day': '2026-10-21'},
    ]);
    ChestService.catalogRefresh = () async {};

    final items = await ChestService.instance.stash();

    expect([for (final i in items) i.giftKey], ['rose']);
  });
}
