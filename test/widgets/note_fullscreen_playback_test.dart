import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/widgets/chat/note_bubble.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../support/fake_note_player.dart';

/// Открытая на весь экран фигурка не должна замолкать из-за ленты под ней.
///
/// Так уже было: просмотр запускал видео, `VisibilityDetector` в ленте через
/// полсекунды сообщал «меня не видно», и бабл звал `stop` по ТОМУ ЖЕ id,
/// который только что открыл просмотр. На весь экран оставалась пустая форма
/// с замершим ободом — выглядело как зависшее приложение.
ChatMsg _note() => ChatMsg(
      id: 'm1',
      uid: 'her',
      name: 'Аня',
      text: '',
      ts: DateTime(2026, 8, 21, 14, 31).millisecondsSinceEpoch,
      noteUrl: '/tmp/note.mp4',
      noteMs: 9000,
      noteShape: 'circle',
    );

void main() {
  setUpAll(() {
    // Без этого детектор видимости молчит и колбэки не приходят вовсе.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('лента не забирает плеер у экрана, открытого поверх неё',
      (tester) async {
    final player = FakeNotePlayer();
    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: Center(
          child: NoteBubble(
            msg: _note(),
            isMine: false,
            size: 200,
            partnerReadTs: 0,
            autoplay: false,
            player: player,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // Фигурку открыли на весь экран: плеер теперь у верхнего маршрута.
    await player.open(messageId: 'm1', url: '/tmp/note.mp4');
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SizedBox.expand()),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(player.stops, isEmpty,
        reason: 'лента под чужим маршрутом не хозяйка плееру');
    expect(player.state.messageId, 'm1',
        reason: 'видео должно продолжать играть на верхнем экране');
  });
}
