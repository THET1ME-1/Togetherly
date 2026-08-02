import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/partner_profile.dart';

/// Что осталось от подарка после вручения.
///
/// Записка, ответ, место и дата встречи лежат в самой записи `gifts` и никуда
/// не деваются — до 1 августа их показывали ровно один раз, в листе получения,
/// и человек, закрывший лист не читая, терял письмо навсегда. Полка в профиле
/// теперь открывает их заново, поэтому разбор записи покрыт тестами.
void main() {
  Map<String, dynamic> rec({
    String key = 'letter',
    String created = '2026-07-14 10:00:00.000Z',
    String sender = 'u1',
    String note = '',
    String reply = '',
    String place = '',
    Object? date,
    String state = 'reacted',
  }) =>
      {
        'gift_key': key,
        'created': created,
        'sender_uid': sender,
        'note': note,
        'reply': reply,
        'place': place,
        if (date != null) 'date': date,
        'state': state,
      };

  group('Отбор по подарку', () {
    final records = [
      rec(key: 'letter', created: '2026-07-14 10:00:00.000Z', note: 'Первое'),
      rec(key: 'star', created: '2026-07-15 10:00:00.000Z'),
      rec(key: 'letter', created: '2026-07-20 10:00:00.000Z', note: 'Второе'),
    ];

    test('Берём только выбранный подарок', () {
      final memos = memosOfKey(records, 'letter');
      expect(memos.length, 2);
      expect(memos.every((m) => m.giftKey == 'letter'), isTrue);
    });

    test('Свежее сверху', () {
      expect(memosOfKey(records, 'letter').map((m) => m.note),
          ['Второе', 'Первое']);
    });

    test('Незнакомый подарок отдаёт пустой список, а не падает', () {
      expect(memosOfKey(records, 'нет-такого'), isEmpty);
    });
  });

  group('Разбор записи', () {
    test('Записка, ответ и место доезжают целиком', () {
      final memo = memosOfKey(
        [
          rec(
            note: 'Люблю тебя',
            reply: 'И я',
            place: 'Кофейня на углу',
          )
        ],
        'letter',
      ).single;

      expect(memo.note, 'Люблю тебя');
      expect(memo.reply, 'И я');
      expect(memo.place, 'Кофейня на углу');
      expect(memo.sentAt, DateTime.parse('2026-07-14 10:00:00.000Z').toLocal());
    });

    test('Пустые поля не притворяются содержимым', () {
      final memo = memosOfKey([rec()], 'letter').single;
      expect(memo.hasText, isFalse);
      expect(memo.note, isEmpty);
      expect(memo.reply, isEmpty);
    });

    test('Есть записка или ответ — значит, есть что перечитать', () {
      expect(memosOfKey([rec(note: 'Привет')], 'letter').single.hasText, isTrue);
      expect(memosOfKey([rec(reply: 'Ага')], 'letter').single.hasText, isTrue);
      expect(
          memosOfKey([rec(place: 'Парк')], 'letter').single.hasText, isTrue);
    });

    test('Дата свидания приходит числом миллисекунд', () {
      final ms = DateTime(2026, 8, 9, 19).millisecondsSinceEpoch;
      final memo = memosOfKey([rec(date: ms)], 'letter').single;
      expect(memo.date, DateTime(2026, 8, 9, 19));
    });

    test('Битая дата не роняет разбор', () {
      final memo =
          memosOfKey([rec(created: 'позавчера', date: 'завтра')], 'letter')
              .single;
      expect(memo.date, isNull);
      expect(memo.sentAt, isNull);
    });
  });

  group('Сколько всего с текстом', () {
    test('Считаем записи, которые есть смысл открывать', () {
      final records = [
        rec(note: 'раз'),
        rec(),
        rec(key: 'star', reply: 'два'),
      ];
      expect(countWithText(records), 2);
    });
  });
}
