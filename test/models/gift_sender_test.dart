// Кем подписан подарок на полке.
//
// Жалоба 14 августа 2026: «приложение показывает мой подарок партнёру так,
// будто это он мне его отправил, у него наоборот». Подпись держалась на одном
// сравнении с моим uid, а он бывает пустым — полумёртвая сессия отдаёт пустую
// личность, и любой подарок становился «от партнёра».
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/partner_profile.dart';

void main() {
  const me = 'uid-me';
  const partner = 'uid-partner';

  group('личность известна', () {
    test('мой подарок подписан мной', () {
      expect(
        giftSenderOf(senderUid: me, myUid: me, shelfOwnerUid: partner),
        GiftSender.me,
      );
    });

    test('подарок партнёра подписан партнёром', () {
      expect(
        giftSenderOf(senderUid: partner, myUid: me, shelfOwnerUid: me),
        GiftSender.counterpart,
      );
    });
  });

  group('своя личность потерялась', () {
    test('на полке партнёра отправитель — я', () {
      expect(
        giftSenderOf(senderUid: me, myUid: '', shelfOwnerUid: partner),
        GiftSender.me,
        reason: 'полка чужая, а дарил не её владелец — значит дарил я',
      );
    });

    test('на своей полке гадать не берёмся', () {
      expect(
        giftSenderOf(senderUid: partner, myUid: '', shelfOwnerUid: partner),
        GiftSender.unknown,
      );
    });

    test('без владельца полки тоже не гадаем', () {
      expect(
        giftSenderOf(senderUid: partner, myUid: ''),
        GiftSender.unknown,
      );
    });
  });

  test('запись без отправителя подписывается обезличенно', () {
    expect(
      giftSenderOf(senderUid: '', myUid: me, shelfOwnerUid: partner),
      GiftSender.unknown,
    );
  });
}
