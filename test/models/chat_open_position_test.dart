import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_open_position.dart';

void main() {
  ChatOpenPosition call({
    double? saved,
    bool nearBottom = false,
    bool unread = false,
    bool newMessages = false,
  }) =>
      chatOpenPosition(
        savedOffset: saved,
        savedWasNearBottom: nearBottom,
        hasUnread: unread,
        newMessagesSinceExit: newMessages,
      );

  test('непрочитанные важнее всего', () {
    expect(call(unread: true), ChatOpenPosition.unreadMarker);
    expect(call(saved: 500, unread: true), ChatOpenPosition.unreadMarker);
    expect(call(saved: 500, unread: true, newMessages: true),
        ChatOpenPosition.unreadMarker);
  });

  test('без сохранённой позиции открываем внизу', () {
    expect(call(), ChatOpenPosition.bottom);
    expect(call(saved: 0), ChatOpenPosition.bottom);
  });

  test('читал у низа — открываем внизу', () {
    expect(call(saved: 1200, nearBottom: true), ChatOpenPosition.bottom);
  });

  test('пришли новые — старые пиксели указывают мимо, идём вниз', () {
    // Ровно та жалоба: чат открывался посреди старой переписки.
    expect(call(saved: 1200, newMessages: true), ChatOpenPosition.bottom);
  });

  test('листал старое и с тех пор тихо — возвращаем туда же', () {
    expect(call(saved: 1200), ChatOpenPosition.savedOffset);
  });
}
