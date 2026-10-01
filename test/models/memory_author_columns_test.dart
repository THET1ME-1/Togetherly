import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/models/memory.dart';

/// Салют из подарков (`gifts.pb.js`) до 01.10.2026 клал автора только в
/// колонку `author_uid`, а приложение читает его из json `data`. Запись
/// показывалась от «?», и удалить её не мог никто: проверка «автор = я» не
/// проходила ни у кого (обращение 219). Колонка — запасной источник автора.
void main() {
  RecordModel salute({String authorUid = 'xsu4phxpjp55ogk'}) => RecordModel({
        'id': 'r8e5769ef9ac62f',
        'group_id': '74zgucs1ewo83xo',
        'author_uid': authorUid,
        'author_name': 'Ульяна',
        'author_avatar': 'pb://media/xw09ma03d1eman4/profile_z85c5stiwy.jpg',
        'created_at': '2026-08-31 12:44:58.916Z',
        'data': jsonEncode({
          'type': 'gift',
          'giftKey': 'salute',
          'title': 'Салют',
          'createdAt': '2026-08-31T12:44:58.916Z',
        }),
      });

  test('автор без json берётся из колонок', () {
    final m = Memory.fromPb(salute());
    expect(m.authorUid, 'xsu4phxpjp55ogk');
    expect(m.authorName, 'Ульяна');
    expect(m.authorAvatar, 'pb://media/xw09ma03d1eman4/profile_z85c5stiwy.jpg');
  });

  test('автор из json главнее колонки', () {
    final rec = RecordModel({
      'id': 'm31vr0s1bt0vecn',
      'author_uid': 'column_uid',
      'author_name': 'Колонка',
      'data': jsonEncode({
        'type': 'photo',
        'authorUid': 'json_uid',
        'authorName': 'санечка',
        'createdAt': '2026-08-02T19:29:46.960243',
      }),
    });
    final m = Memory.fromPb(rec);
    expect(m.authorUid, 'json_uid');
    expect(m.authorName, 'санечка');
  });

  test('пустая колонка не затирает автора пустотой', () {
    final m = Memory.fromPb(salute(authorUid: ''));
    expect(m.authorUid, '');
    expect(m.authorName, 'Ульяна');
  });
}
