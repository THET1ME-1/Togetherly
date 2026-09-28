import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/widgets/chat/note_recorder_overlay.dart';
import 'package:love_app/widgets/chat/note_shape_view.dart';
import 'package:love_app/widgets/chat/note_shapes.dart';

/// Лента форм на экране съёмки. Круг бесплатный, остальные девять идут с
/// Togetherly+ — и человек должен видеть это ДО того, как выберет форму и
/// упрётся в отказ.
Future<void> _pump(WidgetTester tester, PlusGate gate,
    {bool open = true, ValueChanged<NoteShape>? onShape}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
    home: Scaffold(
      body: NoteRecorderOverlay(
        controller: null,
        shape: kNoteShapes.first,
        onShape: onShape ?? (_) {},
        elapsed: ValueNotifier<Duration>(Duration.zero),
        recording: false,
        paused: false,
        locked: false,
        cancelling: false,
        mirrored: false,
        torchOn: false,
        canFlip: false,
        canTorch: false,
        plusGate: gate,
        error: null,
        onRetry: () {},
        onFlip: () {},
        onTorch: () {},
        onMirror: () {},
        onPauseToggle: () {},
        onCancel: () {},
        onSend: () {},
        onClose: () {},
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  if (open) {
    await tester.tap(find.byIcon(Icons.expand_less_rounded));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  final paidCount = kNoteShapes.length - 1;

  testWidgets('без Plus заперты все формы, кроме круга', (tester) async {
    await _pump(tester, PlusGate.locked);
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(paidCount));
  });

  testWidgets('с Plus замков нет', (tester) async {
    await _pump(tester, PlusGate.open);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('там, где Plus не продаётся, замков тоже нет', (tester) async {
    await _pump(tester, PlusGate.hidden);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('лента свёрнута в одну кнопку, пока её не раскрыли', (tester) async {
    await _pump(tester, PlusGate.locked, open: false);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
  });

  testWidgets('выбор открытой формы сворачивает ленту обратно', (tester) async {
    NoteShape? got;
    await _pump(tester, PlusGate.open, onShape: (s) => got = s);
    await tester.tap(find.byType(NoteShapeGlyph).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(got, isNotNull);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
  });
}
