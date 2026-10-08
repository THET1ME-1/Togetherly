import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest_pending.dart';

void main() {
  final now = DateTime(2026, 9, 29, 22, 0);

  test('круг «записали — прочитали» сохраняет номер и вид открытия', () {
    final item = ChestPending(openId: 'abcdefghijklmn0', fromJar: true, at: now.subtract(const Duration(hours: 1)));
    final back = ChestPending.fromJson(item.toJson(), now: now)!;
    expect(back.openId, 'abcdefghijklmn0');
    expect(back.fromJar, isTrue);
    expect(back.at, item.at);
  });

  test('кривая, чужая по формату и протухшая запись не считаются', () {
    expect(ChestPending.fromJson(null, now: now), isNull);
    expect(ChestPending.fromJson('abc', now: now), isNull);
    expect(ChestPending.fromJson({'id': 'ABC', 'at': now.millisecondsSinceEpoch}, now: now), isNull,
        reason: 'сервер принимает только 15 строчных букв и цифр');
    final old = now.subtract(ChestPending.keep + const Duration(minutes: 1));
    expect(ChestPending.fromJson({'id': 'abcdefghijklmn0', 'at': old.millisecondsSinceEpoch}, now: now), isNull);
    final future = now.add(const Duration(hours: 2));
    expect(ChestPending.fromJson({'id': 'abcdefghijklmn0', 'at': future.millisecondsSinceEpoch}, now: now), isNull,
        reason: 'часы телефона убежали — запись не наша');
  });

  test('экран кладёт досмотренный ролик на диск и чистит его по итогу', () {
    final src = File('lib/screens/chest_screen.dart').readAsStringSync();
    expect(src.contains('ChestPendingStore.write'), isTrue, reason: 'ролик снова пропадёт при уходе с экрана');
    expect(src.contains('ChestPendingStore.clear'), isTrue, reason: 'открытый сундук предлагался бы снова');
    // У каждого сундука ленты своё недосмотренное открытие.
    expect(src.contains('_restorePending(main)'), isTrue, reason: 'сохранённое открытие не поднимается при заходе');
    expect(src.contains('_restorePending(slot)'), isTrue, reason: 'у сезонного сундука открытие не поднимается');
    // Итог фиксируется до проверки mounted: экран мог закрыться, пока шёл запрос.
    final clear = src.indexOf('ChestPendingStore.clear');
    final mounted = src.indexOf('if (!mounted) return;', src.indexOf('final res = await request;'));
    expect(clear, lessThan(mounted));
    expect(src.contains('chestOpenId: openId'), isTrue, reason: 'сервер не свяжет ролик с открытием');
  });
}
