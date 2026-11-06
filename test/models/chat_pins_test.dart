// Закреплённые сообщения чата: что считается закреплённым, как полоска над
// лентой перебирает их по нажатию (как в Telegram) и где в ленте встают
// строки «Вы закрепили…».
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/models/chat_pins.dart';
import 'package:pocketbase/pocketbase.dart';

ChatMsg msg(String id, int ts, {int? pinnedAt, bool deleted = false, String by = 'me'}) => ChatMsg(
      id: id,
      uid: 'me',
      name: 'Я',
      text: 'текст $id',
      ts: ts,
      deleted: deleted,
      pinnedAt: pinnedAt,
      pinnedBy: pinnedAt == null ? null : by,
    );

void main() {
  group('запись с сервера', () {
    test('ноль и пустой автор — не закреплено', () {
      final m = ChatMsg.fromPb(RecordModel({'id': 'a', 'ts': 5, 'pinned_at': 0, 'pinned_by': ''}));
      expect(m.isPinned, isFalse);
      expect(m.pinnedBy, isNull);
    });

    test('время и автор закрепления читаются', () {
      final m = ChatMsg.fromPb(RecordModel({'id': 'a', 'ts': 5, 'pinned_at': 900, 'pinned_by': 'her'}));
      expect(m.isPinned, isTrue);
      expect((m.pinnedAt, m.pinnedBy), (900, 'her'));
    });
  });

  group('список закреплённых', () {
    test('по времени сообщения, удалённые и откреплённые не входят', () {
      final r = pinnedMessages([
        msg('c', 30, pinnedAt: 31),
        msg('a', 10, pinnedAt: 99),
        msg('b', 20),
        msg('d', 40, pinnedAt: 41, deleted: true),
      ], const []);
      expect([for (final m in r) m.id], ['a', 'c']);
    });

    test('лента свежее сервера: открепили в ленте — пропало, закрепили — появилось', () {
      final server = [msg('a', 10, pinnedAt: 11), msg('b', 20, pinnedAt: 21)];
      final loaded = [msg('b', 20), msg('c', 30, pinnedAt: 31)];
      expect([for (final m in pinnedMessages(server, loaded)) m.id], ['a', 'c']);
    });
  });

  group('полоска над лентой', () {
    test('начинает с самого нового', () {
      expect(pinBarIndex(null, 4), 3);
      expect(pinBarIndex(9, 4), 3);
      expect(pinBarIndex(1, 4), 1);
      expect(pinBarIndex(null, 0), -1);
    });

    test('после перехода показывает предыдущее, с самого старого — снова новое', () {
      expect(pinBarNext(3, 4), 2);
      expect(pinBarNext(0, 4), 3);
      expect(pinBarNext(0, 1), 0);
    });
  });

  group('строки «закрепили» в ленте', () {
    test('встают перед первым сообщением, которое позже закрепления', () {
      final feed = [
        msg('a', 10),
        msg('b', 20, pinnedAt: 25),
        msg('c', 30),
        msg('d', 40, pinnedAt: 50),
      ];
      final notes = pinNotesBefore(feed);
      expect([for (final m in notes['c'] ?? const <ChatMsg>[]) m.id], ['b']);
      // Закрепили после последнего сообщения — строка в самом низу.
      expect([for (final m in notes[kPinNotesTail] ?? const <ChatMsg>[]) m.id], ['d']);
      expect(notes.containsKey('a'), isFalse);
    });

    test('несколько закреплений подряд — по времени закрепления', () {
      final feed = [msg('a', 10, pinnedAt: 60), msg('b', 20, pinnedAt: 50), msg('c', 70)];
      expect([for (final m in pinNotesBefore(feed)['c']!) m.id], ['b', 'a']);
    });

    test('удалённое сообщение строки не оставляет', () {
      expect(pinNotesBefore([msg('a', 10, pinnedAt: 11, deleted: true), msg('b', 20)]), isEmpty);
    });
  });

  test('правка закрепления: закрепить и открепить', () {
    expect(pinFields(true, 'me', 777), {'pinned_at': 777, 'pinned_by': 'me'});
    expect(pinFields(false, 'me', 777), {'pinned_at': 0, 'pinned_by': ''});
  });
}
