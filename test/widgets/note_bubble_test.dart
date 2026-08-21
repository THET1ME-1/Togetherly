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
    /// Тап и удержание — РАЗНЫЕ действия на одной кнопке, и запись обязана
    /// ждать удержания. Пока она начиналась от касания, каждый тап поднимал
    /// микрофон или камеру: переключение режима не срабатывало (экран считал,
    /// что запись ещё идёт), а камера падала на занятом микрофоне.
    Future<void> pumpButton(
      WidgetTester tester, {
      required void Function() onToggle,
      required void Function() onStart,
      required void Function({required bool cancelled, required bool locked})
          onEnd,
      required void Function(VoiceGesture) onGesture,
    }) =>
        _pump(
          tester,
          SendMicButton(
            hasText: false,
            editing: false,
            noteMode: true,
            noteShape: kNoteShapes.first,
            onModeToggle: onToggle,
            handsFree: true,
            primary: Colors.pink,
            onPrimary: Colors.white,
            idleBackground: Colors.grey,
            idleForeground: Colors.black,
            onSend: () {},
            onRecordStart: onStart,
            onRecordGesture: onGesture,
            onRecordEnd: onEnd,
          ),
        );

    testWidgets('тап меняет режим и НЕ трогает камеру с микрофоном',
        (tester) async {
      var toggled = 0, started = 0, ended = 0;
      await pumpButton(
        tester,
        onToggle: () => toggled++,
        onStart: () => started++,
        onEnd: ({required cancelled, required locked}) => ended++,
        onGesture: (_) {},
      );

      await tester.tap(find.byType(SendMicButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      expect(started, 0, reason: 'тап не должен начинать запись');
      expect(ended, 0, reason: 'заканчивать нечего');
      expect(toggled, 1);
    });

    testWidgets('удержание начинает съёмку, а палец можно убрать',
        (tester) async {
      var toggled = 0, started = 0;
      bool? endedCancelled;
      bool? endedLocked;
      await pumpButton(
        tester,
        onToggle: () => toggled++,
        onStart: () => started++,
        onEnd: ({required cancelled, required locked}) {
          endedCancelled = cancelled;
          endedLocked = locked;
        },
        onGesture: (_) {},
      );

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(SendMicButton)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(started, 1, reason: 'после порога удержания съёмка уже идёт');
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));

      expect(toggled, 0, reason: 'удержание — это съёмка, а не переключение');
      expect(endedCancelled, isFalse);
      expect(endedLocked, isTrue,
          reason: 'палец убрали, а съёмка продолжается — отправят кнопкой');
    });

    testWidgets('запись не начинается раньше порога', (tester) async {
      var started = 0;
      await pumpButton(
        tester,
        onToggle: () {},
        onStart: () => started++,
        onEnd: ({required cancelled, required locked}) {},
        onGesture: (_) {},
      );

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(SendMicButton)));
      await tester.pump(const Duration(milliseconds: 120));
      expect(started, 0, reason: 'сто двадцать миллисекунд — это ещё тап');
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));
    });

    testWidgets('увод пальца влево отменяет снятое', (tester) async {
      var toggled = 0;
      bool? endedCancelled;
      final gestures = <VoiceGesture>[];
      await pumpButton(
        tester,
        onToggle: () => toggled++,
        onStart: () {},
        onEnd: ({required cancelled, required locked}) =>
            endedCancelled = cancelled,
        onGesture: gestures.add,
      );

      final center = tester.getCenter(find.byType(SendMicButton));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveTo(center - const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));

      expect(gestures, contains(VoiceGesture.cancelling));
      expect(endedCancelled, isTrue);
      expect(toggled, 0);
    });
  });
}
