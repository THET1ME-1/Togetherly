// Продажа подарка из запаса сундука (обращение 244, задача 7 плана сундука):
// ненужный подарок не исчезает впустую, а меняется на монеты по редкости.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/services/chest_service.dart';

Map<String, String> _table(String src, String name) {
  final block = RegExp('const $name = \\{([^}]*)\\}').firstMatch(src);
  expect(block, isNotNull, reason: 'в chest.pb.js нет таблицы $name');
  return {
    for (final m in RegExp(r'(\w+)\s*:\s*"?(\w+)"?').allMatches(block!.group(1)!))
      m.group(1)!: m.group(2)!,
  };
}

void main() {
  final src = File('pocketbase/pb_hooks/chest.pb.js').readAsStringSync();

  test('цены продажи совпадают с сервером', () {
    final server = _table(src, 'SELL');
    expect({for (final e in kChestSellPrice.entries) e.key: '${e.value}'}, server);
  });

  test('ярусы для продажи совпадают с подарками сундука', () {
    final gifts = {
      for (final m in RegExp(r'\["(\w+)", "(\w+)"\]').allMatches(
          RegExp(r'const GIFTS = \[(.*?)\];', dotAll: true).firstMatch(src)!.group(1)!))
        m.group(1)!: m.group(2)!,
    };
    expect(_table(src, 'SELL_TIER'), gifts);
  });

  test('цена подарка по редкости', () {
    expect(chestSellPrice('teddy'), kChestSellPrice['common']);
    expect(chestSellPrice('record'), kChestSellPrice['rare']);
    expect(chestSellPrice('rings'), kChestSellPrice['legendary']);
    // Сезонный подарок: редкость приходит из каталога
    expect(chestSellPrice('hw_pumpkin', rarity: 'rare'), kChestSellPrice['rare']);
    expect(chestSellPrice('hw_pumpkin'), kChestSellPrice['common']);
    expect(chestSellPrice('hw_pumpkin', rarity: 'мусор'), kChestSellPrice['common']);
  });

  test('ответ продажи', () {
    final sale = parseChestSale({'ok': true, 'price': 5, 'coins': 125})!;
    expect(sale.price, 5);
    expect(sale.coins, 125);
    expect(sale.repeated, isFalse);
    expect(parseChestSale({'ok': true, 'repeated': true, 'coins': 120})!.repeated, isTrue);
    expect(parseChestSale({'ok': false, 'error': 'already_used'}), isNull);
    expect(parseChestSale('мусор'), isNull);
  });
}
