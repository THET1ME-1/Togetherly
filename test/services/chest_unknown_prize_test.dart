import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/models/gift.dart';
import 'package:love_app/services/chest_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Подарки сезона приложение узнаёт из каталога сервера. Открыли сундук
/// раньше, чем каталог доехал, — выпавший подарок для приложения был
/// «неизвестным», и человек видел «Сундук не открылся», хотя сервер приз уже
/// выдал и положил в запас. За сутки до 19.10.2026 так «не открылось» пять
/// хэллоуинских сундуков (`unknown_prize` в Bugsink), жалоба в чате: «а почему
/// сундуки не работают? у меня уже просто не первый раз такое».
void main() {
  late Future<void> Function() original;

  setUp(() {
    original = ChestService.catalogRefresh;
    GiftCatalog.registerSeasonal(const {});
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'ok': true,
              'repeated': false,
              'prize': {'key': 'cocoa', 'kind': 'gift', 'amount': 0},
              'left': 2,
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    ));
  });

  tearDown(() {
    ChestService.catalogRefresh = original;
    GiftCatalog.registerSeasonal(const {});
  });

  test('подарок сезона до каталога не превращает открытие в отказ', () async {
    var refreshed = 0;
    ChestService.catalogRefresh = () async {
      refreshed++;
      GiftCatalog.registerSeasonal({
        'cocoa': const Gift(
          key: 'cocoa',
          price: 0,
          engine: GiftEngine.response,
          titleRu: 'Какао',
          titleEn: 'Cocoa',
        ),
      });
    };

    final res = await ChestService.instance.open(openId: 'abcdefghijklmno', groupId: 'g');

    expect(res.ok, isTrue, reason: 'Сервер приз выдал — «не открылся» здесь врёт');
    expect(res.prize?.key, 'cocoa');
    expect(refreshed, 1);
  });

  test('подарка нет и в свежем каталоге — приложение честно говорит о сбое', () async {
    ChestService.catalogRefresh = () async {};

    final res = await ChestService.instance.open(openId: 'abcdefghijklmno', groupId: 'g');

    expect(res.ok, isFalse);
    expect(res.error, 'unknown_prize');
  });
}
