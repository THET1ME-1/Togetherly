import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cloud_mascot.dart';
import 'package:love_app/models/mascot.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/models/mascot_sleep.dart';
import 'package:love_app/services/mascot_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/active_mascot_widget.dart';
import 'package:love_app/widgets/mascot/cloud_mascot_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Двойной тап по Ту на главной — кувырок (жалоба владельца на сборке 261:
// «не делает сальто, как бы я ни нажимал»).
/// Ту на пустом экране, уже появившийся и готовый к касаниям.
Future<void> pumpTu(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'mascot_onboarding_shown': true});
  mascotTapClock = () => tester.binding.clock.now();
  addTearDown(() => mascotTapClock = DateTime.now);
  final service = MascotService();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          ActiveMascotWidget(
            mascotService: service,
            theme: buildAppTheme(kPalettes[0], Brightness.light),
            onOpenGallery: () {},
            sleepOf: (_) => const SleepWindow(from: 0, to: 0, enabled: false),
          ),
        ]),
      ),
    ));
    await tester.pump();
    service.debugSetState(const GroupMascotState(activeMascotId: kCloudMascotId, positionX: 0.5, positionY: 0.5));
    tester.binding.scheduleFrame();
    // Появление Ту — пружинка с нуля: даём ей дойти по кадрам, иначе первый
    // тап попадёт в ещё крошечного Ту.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
}

bool _isTouchMark(Widget w) => w is CustomPaint && w.painter.runtimeType.toString() == '_TouchMarkPainter';

void main() {
  testWidgets('два тапа подряд по Ту — кувырок', (tester) async {
    await pumpTu(tester);
    final tu = find.byType(GestureDetector).first;
    await tester.tap(tu);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(tu);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final cloud = find.byType(CloudMascotView);

    expect(tester.widget<CloudMascotView>(cloud).anim, MascotAnimState.grow);
  });

  testWidgets('кружок касания там, куда ткнули, и тает после отпускания', (tester) async {
    await pumpTu(tester);
    final box = tester.getRect(find.byType(GestureDetector).first);
    final point = box.center + const Offset(12, -18);
    final finger = await tester.startGesture(point);
    await tester.pump();
    final mark = find.byWidgetPredicate(_isTouchMark);
    expect(mark, findsOneWidget);
    expect(tester.getRect(mark).contains(point), isTrue);
    await finger.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.byWidgetPredicate(_isTouchMark), findsNothing);
  });
}
