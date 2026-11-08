import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/tu_wear.dart';

TuWear _item(String src, int price) =>
    TuWear(key: 'bow', cat: 'neck', src: src, nameRu: 'Бант', nameEn: 'Bow', iconKey: '', layers: const {}, price: price);

/// Вещь за монеты можно забрать и роликами (09.11.2026): ролик на каждые
/// 50 монет цены, с округлением вверх. Сервер считает просмотры сам и
/// выдаёт вещь на последнем, поэтому правило живёт и в `wear.pb.js`.
void main() {
  test('ролик на каждые 50 монет, с округлением вверх', () {
    expect(wearAdsNeeded(50), 1);
    expect(wearAdsNeeded(60), 2);
    expect(wearAdsNeeded(100), 2);
    expect(wearAdsNeeded(110), 3);
    expect(wearAdsNeeded(150), 3);
    expect(wearAdsNeeded(200), 4);
    expect(wearAdsNeeded(250), 5);
    expect(wearAdsNeeded(0), 0);
  });

  test('роликами берутся вещи за монеты и за ролик, сундучные нет', () {
    expect(_item('coins', 140).adsNeeded, 3);
    expect(_item('ad', 0).adsNeeded, 1);
    expect(_item('chest', 0).adsNeeded, 0);
    expect(_item('coins', 0).adsNeeded, 0);
  });

  test('досмотренные ролики читаются из записи аккаунта', () {
    final raw = {
      'bow': {'n': 2, 'at': 1794177355000},
      'tie': {'n': 'мусор'},
    };
    expect(wearAdProgress(raw, 'bow'), 2);
    expect(wearAdProgress(raw, 'tie'), 0);
    expect(wearAdProgress(raw, 'halo'), 0);
    expect(wearAdProgress(null, 'bow'), 0);
    expect(wearAdProgress('[]', 'bow'), 0);
  });

  test('сервер считает ролики тем же правилом и хранит их в закрытом поле', () {
    final hook = File('pocketbase/pb_hooks/wear.pb.js').readAsStringSync();
    expect(hook, contains('Math.ceil(price / 50)'));
    expect(hook, contains('wear_ad_views'));
    final guard = File('pocketbase/pb_hooks/users_guard.pb.js').readAsStringSync();
    // Список защищённых полей повторён в двух обработчиках: правка и создание.
    expect('"wear_ad_views"'.allMatches(guard).length, greaterThanOrEqualTo(2));
    final schema = File('pocketbase/apply_schema.py').readAsStringSync();
    expect(schema, contains('jsonf("wear_ad_views")'));
  });
}
