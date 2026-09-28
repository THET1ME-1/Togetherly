import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/models/note_autoplay.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/note_send_status.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/widgets/chat/note_bubble.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../support/fake_note_player.dart';

ChatMsg _note(String id, {String uid = 'her', int ts = 1000, int seenAt = 0}) =>
    ChatMsg(
      id: id,
      uid: uid,
      name: 'Аня',
      text: '',
      ts: ts,
      noteUrl: '/tmp/$id.mp4',
      noteMs: 9000,
      noteShape: 'circle',
      noteSeenAt: seenAt == 0 ? null : seenAt,
    );

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
    home: Scaffold(body: Center(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  group('подпись отправки своего кружка', () {
    test('провал главнее всего, живая работа главнее очереди', () {
      const c = NoteSendState(NoteSendPhase.compressing, .4);
      expect(noteSendView(mine: true, pending: true, poisoned: true, active: c),
          NoteSendView.failed);
      expect(noteSendView(mine: true, pending: true, poisoned: false, active: c),
          NoteSendView.compressing);
      expect(
          noteSendView(
              mine: true,
              pending: true,
              poisoned: false,
              active: const NoteSendState(NoteSendPhase.uploading)),
          NoteSendView.uploading);
      expect(noteSendView(mine: true, pending: true, poisoned: false, active: null),
          NoteSendView.waiting);
      expect(noteSendView(mine: true, pending: false, poisoned: false, active: null),
          NoteSendView.none);
      expect(noteSendView(mine: false, pending: true, poisoned: true, active: c),
          NoteSendView.none);
    });

    test('кружку и голосовому очередь даёт время на сжатие и загрузку', () {
      // Общие 20 секунд обрывали почти каждый кружок: кодек жмёт дольше.
      expect(outboxOpTimeout('chatNote'), greaterThanOrEqualTo(const Duration(minutes: 5)));
      expect(outboxOpTimeout('chatVoice'), greaterThan(const Duration(seconds: 20)));
      expect(outboxOpTimeout('chatUpsert'), const Duration(seconds: 20));
    });

    testWidgets('пока жмётся — проценты вместо галочек', (t) async {
      addTearDown(() => NoteSendStatus.instance.clear('mine1'));
      NoteSendStatus.instance
          .set('mine1', const NoteSendState(NoteSendPhase.compressing, .4));
      await _pump(
        t,
        NoteBubble(
          msg: _note('mine1', uid: 'me'),
          isMine: true,
          size: 200,
          partnerReadTs: 0,
          autoplay: false,
          player: FakeNotePlayer(),
        ),
      );
      expect(find.text('Сжимаю · 40%'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsNothing);
      NoteSendStatus.instance.set('mine1', const NoteSendState(NoteSendPhase.uploading));
      await t.pump();
      expect(find.text('Отправляю…'), findsOneWidget);
      NoteSendStatus.instance.clear('mine1');
      await t.pump();
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    });
  });

  testWidgets('«развернуть» и подсказка звука — только у включённого кружка',
      (t) async {
    final player = FakeNotePlayer();
    await _pump(
      t,
      NoteBubble(
        msg: _note('n1', seenAt: 5),
        isMine: false,
        size: 200,
        partnerReadTs: 0,
        autoplay: false,
        player: player,
        onOpenFull: () {},
      ),
    );
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    expect(find.text('Коснитесь — звук'), findsNothing);
    await player.open(messageId: 'n1', url: '/tmp/n1.mp4', auto: true);
    await t.pump();
    // Играет молча — сперва подсказка про звук, «развернуть» на её месте
    // появляется, когда звук включили.
    expect(find.text('Коснитесь — звук'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    await player.toggleSound();
    await t.pump();
    expect(find.text('Коснитесь — звук'), findsNothing);
    expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
  });

  group('следующий кружок после досмотренного', () {
    final msgs = [
      _note('a', ts: 100),
      _note('mine', uid: 'me', ts: 150),
      _note('b', ts: 200),
      _note('c', ts: 300, seenAt: 1),
      _note('d', ts: 400),
    ];

    test('берём ближайший новее непросмотренный кружок партнёра', () {
      expect(nextUnseenNote(msgs, finishedId: 'a', myUid: 'me')?.id, 'b');
      expect(nextUnseenNote(msgs, finishedId: 'b', myUid: 'me')?.id, 'd');
    });

    test('свои и уже просмотренные пропускаем, в прошлое не уходим', () {
      expect(nextUnseenNote(msgs, finishedId: 'd', myUid: 'me'), isNull);
      expect(
          nextUnseenNote(msgs,
              finishedId: 'a', myUid: 'me', seenLocally: {'b'})?.id,
          'd');
      expect(nextUnseenNote(msgs, finishedId: 'нет', myUid: 'me'), isNull);
    });
  });

  group('следующее голосовое после дослушанного', () {
    ChatMsg v(String id, {String uid = 'her', int ts = 0, int heard = 0}) =>
        ChatMsg(
          id: id,
          uid: uid,
          name: 'Аня',
          text: '',
          ts: ts,
          voiceUrl: '/tmp/$id.m4a',
          voiceMs: 5000,
          voiceHeardAt: heard == 0 ? null : heard,
        );
    final msgs = [
      v('a', ts: 100),
      _note('n', ts: 150),
      v('mine', uid: 'me', ts: 160),
      v('b', ts: 200, heard: 1),
      v('c', ts: 300),
    ];

    test('кружки, свои и прослушанные пропускаем', () {
      expect(nextUnheardVoice(msgs, finishedId: 'a', myUid: 'me')?.id, 'c');
      expect(nextUnheardVoice(msgs, finishedId: 'c', myUid: 'me'), isNull);
    });

    test('цепочки не смешиваются: после кружка голосовое не включаем', () {
      expect(nextUnseenNote(msgs, finishedId: 'a', myUid: 'me')?.id, 'n');
      expect(nextUnseenNote(msgs, finishedId: 'n', myUid: 'me'), isNull);
    });
  });
}
