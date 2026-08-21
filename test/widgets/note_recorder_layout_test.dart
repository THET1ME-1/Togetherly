import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/widgets/chat/note_recorder_overlay.dart';
import 'package:love_app/widgets/chat/note_shapes.dart';

/// Экран съёмки фигурки на узких телефонах.
///
/// Кнопки стоят по краям от кадра, а сам кадр считался долей ширины — и на
/// обычном телефоне сумма «кнопка + форма + кнопка» вылезала за экран: пауза
/// уезжала за правый край и нажать её было нечем.
Future<void> _pump(WidgetTester tester, Size screen) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
    home: Scaffold(
      body: NoteRecorderOverlay(
        controller: null,
        shape: kNoteShapes.first,
        onShape: (_) {},
        elapsed: ValueNotifier<Duration>(Duration.zero),
        recording: true,
        paused: false,
        locked: true,
        cancelling: false,
        mirrored: false,
        torchOn: false,
        canFlip: true,
        canTorch: true,
        plusGate: PlusGate.open,
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
}

void main() {
  for (final screen in const [
    Size(393, 873), // обычный телефон, на нём баг и поймали
    Size(320, 640), // самый узкий, который мы держим
    Size(412, 915),
  ]) {
    testWidgets('кнопки помещаются на экране ${screen.width.toInt()} dp',
        (tester) async {
      await _pump(tester, screen);

      expect(tester.takeException(), isNull,
          reason: 'переполнение ряда роняет вёрстку в лог и режет кнопки');

      final pause = tester.getRect(find.byIcon(Icons.pause_rounded));
      expect(pause.right, lessThanOrEqualTo(screen.width),
          reason: 'пауза уехала за правый край');

      final flip = tester.getRect(find.byIcon(Icons.cameraswitch_rounded));
      expect(flip.left, greaterThanOrEqualTo(0.0),
          reason: 'переключение камеры уехало за левый край');
    });
  }
}
