import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chat/bottom_stick.dart';

/// Лента как в чате: `ListView.builder` без переворота, низ — `maxScrollExtent`.
/// Высоты рядов и экрана меняются снаружи — так догружаются фото и
/// открывается клавиатура.
Widget _feed({
  required ScrollController controller,
  required ValueNotifier<List<double>> heights,
  required ValueNotifier<double> viewport,
  BottomStick? stick,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: ValueListenableBuilder<double>(
        valueListenable: viewport,
        builder: (_, h, _) => SizedBox(
          width: 360,
          height: h,
          child: ValueListenableBuilder<List<double>>(
            valueListenable: heights,
            builder: (_, hs, _) {
              final list = ListView.builder(
                controller: controller,
                itemCount: hs.length,
                itemBuilder: (_, i) =>
                    SizedBox(height: hs[i], child: Text('ряд $i')),
              );
              return stick == null ? list : stick.wrap(list);
            },
          ),
        ),
      ),
    ),
  );
}

/// То, что делает чат на первой отрисовке: прыжок в оценку низа.
Future<void> _openAtBottom(
  WidgetTester tester,
  ScrollController controller,
  BottomStick? stick,
) async {
  stick?.active = true;
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

bool _atBottom(ScrollController c) =>
    c.position.maxScrollExtent - c.position.pixels < 0.5;

/// 180 коротких строк, а последние 20 — фото и голосовые, вчетверо выше
/// средней строки. Оценка низа по первым рядам выходит сильно меньше настоящей.
List<double> _tallTail() => [
      for (var i = 0; i < 180; i++) 40.0,
      for (var i = 0; i < 20; i++) 300.0,
    ];

void main() {
  late ScrollController controller;
  late ValueNotifier<List<double>> heights;
  late ValueNotifier<double> viewport;

  setUp(() {
    controller = ScrollController();
    heights = ValueNotifier(_tallTail());
    viewport = ValueNotifier(500);
  });

  tearDown(() {
    controller.dispose();
    heights.dispose();
    viewport.dispose();
  });

  testWidgets('без держателя прыжок в оценку не доезжает до низа',
      (tester) async {
    // Так чат открывался до правки: последние сообщения оставались ниже экрана.
    await tester.pumpWidget(
      _feed(controller: controller, heights: heights, viewport: viewport),
    );
    await _openAtBottom(tester, controller, null);
    expect(_atBottom(controller), isFalse);
    expect(find.text('ряд 199'), findsNothing);
  });

  testWidgets('открытие встаёт к последнему сообщению, хоть ряды у низа выше',
      (tester) async {
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    await _openAtBottom(tester, controller, stick);
    expect(_atBottom(controller), isTrue);
    expect(find.text('ряд 199'), findsOneWidget);
  });

  testWidgets('догрузилась картинка — лента остаётся у низа', (tester) async {
    heights.value = [for (var i = 0; i < 30; i++) 60.0];
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    await _openAtBottom(tester, controller, stick);
    final before = controller.position.pixels;

    heights.value = [...heights.value.take(27), 420, 420, 420];
    await tester.pumpAndSettle();

    expect(controller.position.pixels, greaterThan(before));
    expect(_atBottom(controller), isTrue);
    expect(find.text('ряд 29'), findsOneWidget);
  });

  testWidgets('лента короче экрана выросла — низ всё равно держится',
      (tester) async {
    heights.value = [for (var i = 0; i < 4; i++) 60.0];
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    // Прыгать некуда, флаг ставит сам экран.
    await _openAtBottom(tester, controller, stick);

    heights.value = [60, 60, 60, 420, 420];
    await tester.pumpAndSettle();

    expect(_atBottom(controller), isTrue);
    expect(find.text('ряд 4'), findsOneWidget);
  });

  testWidgets('клавиатура сжала ленту — последнее сообщение на виду',
      (tester) async {
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    await _openAtBottom(tester, controller, stick);

    viewport.value = 260;
    await tester.pumpAndSettle();

    expect(_atBottom(controller), isTrue);
    expect(find.text('ряд 199'), findsOneWidget);
  });

  testWidgets('человек отлистал вверх — догрузка его не дёргает',
      (tester) async {
    heights.value = [for (var i = 0; i < 40; i++) 60.0];
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    await _openAtBottom(tester, controller, stick);

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(stick.active, isFalse);
    final reading = controller.position.pixels;

    heights.value = [...heights.value.take(37), 420, 420, 420];
    await tester.pumpAndSettle();

    expect(controller.position.pixels, reading);
    expect(_atBottom(controller), isFalse);
  });

  testWidgets('вернулся рукой к низу — низ снова держится', (tester) async {
    heights.value = [for (var i = 0; i < 40; i++) 60.0];
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    await _openAtBottom(tester, controller, stick);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(stick.active, isTrue);

    heights.value = [...heights.value.take(37), 420, 420, 420];
    await tester.pumpAndSettle();
    expect(_atBottom(controller), isTrue);
  });

  testWidgets('прыжок к цитате отпускает низ', (tester) async {
    heights.value = [for (var i = 0; i < 40; i++) 60.0];
    final stick = BottomStick(controller);
    await tester.pumpWidget(_feed(
      controller: controller,
      heights: heights,
      viewport: viewport,
      stick: stick,
    ));
    await _openAtBottom(tester, controller, stick);

    controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(stick.active, isFalse);

    heights.value = [...heights.value.take(37), 420, 420, 420];
    await tester.pumpAndSettle();
    expect(controller.position.pixels, 300);
  });
}
