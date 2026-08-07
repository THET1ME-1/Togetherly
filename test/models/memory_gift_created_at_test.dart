import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/models/memory.dart';

/// Хук подарков (`pocketbase/pb_hooks/gifts.pb.js`) кладёт в `data.createdAt`
/// миллисекунды числом и не заполняет колонку `created_at`. Такая запись не
/// должна ронять разбор — иначе одна «салютная» строка обнуляет всю ленту.
void main() {
  RecordModel gift() => RecordModel({
        'id': 'ix9cmybz6ur506n',
        'group_id': '74zgucs1ewo83xo',
        'author_uid': 'xsu4phxpjp55ogk',
        'created_at': '',
        'data': jsonEncode({
          'type': 'gift',
          'giftKey': 'salute',
          'title': 'Салют',
          'createdAt': 1785702332438,
        }),
      });

  RecordModel photo() => RecordModel({
        'id': 'm31vr0s1bt0vecn',
        'group_id': '74zgucs1ewo83xo',
        'author_uid': 'xsu4phxpjp55ogk',
        'created_at': '2026-08-02 19:29:46.960Z',
        'data': jsonEncode({
          'type': 'photo',
          'authorName': 'санечка',
          'createdAt': '2026-08-02T19:29:46.960243',
        }),
      });

  test('запись подарка с миллисекундами разбирается без исключения', () {
    final m = Memory.fromPb(gift());
    expect(m.id, 'ix9cmybz6ur506n');
    expect(m.createdAt.millisecondsSinceEpoch, 1785702332438);
  });

  test('одна запись подарка не роняет разбор всей ленты', () {
    final feed = [gift(), photo()].map(Memory.fromPb).toList();
    expect(feed.length, 2);
  });
}
