import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/widgets/chat/note_bubble.dart';
import 'package:love_app/widgets/chat/send_mic_button.dart';
import 'package:love_app/widgets/chat/note_shapes.dart';
import 'package:visibility_detector/visibility_detector.dart';

ChatMsg _note({
  String id = 'm1',
  String uid = 'her',
  int seenAt = 0,
  String shape = 'heart',
}) =>
    ChatMsg(
      id: id,
      uid: uid,
      name: 'Аня',
      text: '',
      ts: DateTime(2026, 8, 21, 14, 31).millisecondsSinceEpoch,
      noteUrl: '/tmp/note.mp4',
      noteMs: 9000,
      noteShape: shape,
      noteSeenAt: seenAt == 0 ? null : seenAt,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() {
    // Без этого детектор видимости молчит и колбэки не приходят вовсе.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('чужая непросмотренная фигурка показывает точку и длительность',
      (tester) async {
    await _pump(
      tester,
      NoteBubble(
        msg: _note(),
        isMine: false,
        size: 200,
        partnerReadTs: 0,
        autoplay: false,
      ),
    );
    expect(find.text('0:09'), findsOneWidget);
    expect(find.text('14:31'), findsOneWidget);
    // Точка непросмотренного — маленький круг рядом со временем.
    final dots = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle;
    });
    expect(dots, isNotEmpty);
  });

  testWidgets('просмотренная чужая фигурка точку не показывает',
      (tester) async {
    await _pump(
      tester,
      NoteBubble(
        msg: _note(seenAt: 123),
        isMine: false,
        size: 200,
        partnerReadTs: 0,
        autoplay: false,
      ),
    );
    final dots = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle;
    });
    expect(dots, isEmpty);
  });

  testWidgets('у своей фигурки галочка доставки', (tester) async {
    final msg = _note(uid: 'me');
    await _pump(
      tester,
      NoteBubble(
        msg: msg,
        isMine: true,
        size: 200,
        partnerReadTs: msg.ts + 1,
        autoplay: false,
      ),
    );
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });

  testWidgets('незнакомая форма не роняет фигурку', (tester) async {
    await _pump(
      tester,
      NoteBubble(
        msg: _note(shape: 'форма-из-будущего'),
        isMine: false,
        size: 180,
        partnerReadTs: 0,
        autoplay: false,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('кнопка справа от поля', () {
    testWidgets('короткое касание меняет режим и не записывает',
        (tester) async {
      var toggled = 0;
      var started = 0;
      var ended = 0;
      var cancelled = false;

      await _pump(
        tester,
        SendMicButton(
          hasText: false,
          editing: false,
          noteMode: true,
          noteShape: kNoteShapes.first,
          onModeToggle: () => toggled++,
          primary: Colors.pink,
          onPrimary: Colors.white,
          idleBackground: Colors.grey,
          idleForeground: Colors.black,
          onSend: () {},
          onRecordStart: () => started++,
          onRecordGesture: (_) {},
          onRecordEnd: ({required cancelled, required locked}) {
            ended++;
            if (cancelled) {
              // Быстрое касание обязано отменить начатую запись, иначе в чат
              // улетит пустой файл.
            }
          },
        ),
      );

      await tester.tap(find.byType(SendMicButton));
      await tester.pump(const Duration(milliseconds: 60));

      expect(toggled, 1, reason: 'режим не переключился');
      expect(started, 1, reason: 'касание всегда поднимает запись');
      expect(ended, 1);
      expect(cancelled, isFalse);
    });

    testWidgets('удержание пишет и режим не трогает', (tester) async {
      var toggled = 0;
      var started = 0;
      var cancelledEnd = true;

      await _pump(
        tester,
        SendMicButton(
          hasText: false,
          editing: false,
          noteMode: true,
          noteShape: kNoteShapes.first,
          onModeToggle: () => toggled++,
          primary: Colors.pink,
          onPrimary: Colors.white,
          idleBackground: Colors.grey,
          idleForeground: Colors.black,
          onSend: () {},
          onRecordStart: () => started++,
          onRecordGesture: (_) {},
          onRecordEnd: ({required cancelled, required locked}) =>
              cancelledEnd = cancelled,
        ),
      );

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(SendMicButton)));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));

      expect(started, 1);
      expect(toggled, 0, reason: 'долгое нажатие — это запись, а не переключение');
      expect(cancelledEnd, isFalse, reason: 'снятое должно уйти в отправку');
    });
  });
}
