import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/tu_wear.dart';

TuWear _w(String key, String src, {int price = 0, String cat = 'outfit', int sort = 500}) =>
    TuWear(key: key, cat: cat, src: src, nameRu: key, nameEn: key, iconKey: '', layers: const {}, price: price, sort: sort);

/// Гардероб с примеркой (макет «Б. Примерка», 09.11.2026,
/// https://claude.ai/artifact/VAPbaGHZRu2nxWKP7PWUu8): чипы-фильтры,
/// порядок «что можно взять сейчас — первым» и наряд для примерки.
void main() {
  final suit = _w('suit', 'chest');
  final hoodie = _w('hoodie', 'coins', price: 180);
  final breton = _w('breton', 'coins', price: 150);
  final leather = _w('leather', 'coins', price: 250);
  final bow = _w('bow', 'ad');
  final mine = _w('mine', 'coins', price: 100);
  final all = [suit, leather, hoodie, bow, breton, mine];

  test('порядок: своё, за ролик, по карману по цене, дорогое, сундук', () {
    final order = wardrobeOrder(all, owned: {'mine'}, coins: 200);
    expect([for (final w in order) w.key], ['mine', 'bow', 'breton', 'hoodie', 'leather', 'suit']);
  });

  test('фильтры: мои, за монеты, за ролики', () {
    List<String> keys(WearFilter f, {bool plus = false}) =>
        [for (final w in wardrobeFilter(all, f, owned: {'mine'}, plus: plus)) w.key];
    expect(keys(WearFilter.all), hasLength(6));
    expect(keys(WearFilter.mine), ['mine']);
    expect(keys(WearFilter.coins), ['leather', 'hoodie', 'breton']);
    // Вещь за монеты берётся и роликами; с Плюсом роликов нет, остаются
    // только вещи «за ролик», они ему бесплатны.
    expect(keys(WearFilter.ads), ['leather', 'hoodie', 'bow', 'breton']);
    expect(keys(WearFilter.ads, plus: true), ['bow']);
  });

  test('гардероб показывает примерку на живом Ту и сортирует вещи', () {
    final src = File('lib/screens/tu_wardrobe_screen.dart').readAsStringSync();
    expect(src, contains('tryOn: trying == null ? null : wearTryOn('));
    expect(src, contains('wardrobeOrder('));
    expect(src, contains('wardrobeFilter('));
  });

  test('примерка заменяет вещь своего раздела, остальное надетое остаётся', () {
    final outfit = {'outfit': 'breton', 'glasses': 'specs'};
    expect(wearTryOn(outfit, hoodie), {'outfit': 'hoodie', 'glasses': 'specs'});
    expect(outfit['outfit'], 'breton');
  });
}
