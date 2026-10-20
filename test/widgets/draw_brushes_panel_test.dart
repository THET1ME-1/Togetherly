import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_quick_tools.dart';
import 'package:love_app/models/stroke_brush.dart';
import 'package:love_app/widgets/draw/draw_tools_panel.dart';

/// Панель холста по макету «Кисти и ластик», вариант «А. Ряд образцов»:
/// под инструментами пять плиток с мазком, под рядом имя и строка, чем кисть
/// хороша. У ластика свой ряд режимов, своя толщина и нет раздела цвета.
const _names = {
  StrokeBrush.pen: 'Перо',
  StrokeBrush.marker: 'Маркер',
  StrokeBrush.pencil: 'Карандаш',
  StrokeBrush.airbrush: 'Аэрограф',
  StrokeBrush.calligraphy: 'Каллиграфия',
};
const _notes = {
  StrokeBrush.pen: 'Ровная круглая линия',
  StrokeBrush.marker: 'Плоский и прозрачный, наложения темнее',
  StrokeBrush.pencil: 'Тонкий, с зерном бумаги',
  StrokeBrush.airbrush: 'Мягкое напыление без края',
  StrokeBrush.calligraphy: 'Тонко или толсто по направлению',
};
const _eraserNames = {
  EraserMode.hard: 'Твёрдый',
  EraserMode.soft: 'Мягкий',
  EraserMode.whole: 'Линия целиком',
};

Widget _panel({
  DrawQuickTool tool = DrawQuickTool.brush,
  StrokeBrush brush = StrokeBrush.marker,
  bool pixel = false,
  EraserMode eraserMode = EraserMode.hard,
  ValueChanged<StrokeBrush>? onBrush,
  ValueChanged<EraserMode>? onEraserMode,
  Brightness brightness = Brightness.light,
  double width = 320,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B), brightness: brightness),
    ),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: DrawToolsSheet(
                tool: tool,
                tools: const [
                  DrawQuickTool.brush,
                  DrawQuickTool.eraser,
                  DrawQuickTool.fill,
                  DrawQuickTool.shapes,
                  DrawQuickTool.layers,
                  DrawQuickTool.image,
                  DrawQuickTool.select,
                  DrawQuickTool.palm,
                  DrawQuickTool.clear,
                ],
                color: const Color(0xFFE8475F),
                width: tool == DrawQuickTool.eraser ? 24 : 9,
                minWidth: 1,
                maxWidth: tool == DrawQuickTool.eraser ? 60 : 40,
                palette: const [
                  Color(0xFFE8475F),
                  Color(0xFF22191A),
                  Color(0xFFFFFFFF),
                  Color(0xFF3A6FD8),
                  Color(0xFF2E9E5B),
                  Color(0xFFF2B233),
                  Color(0xFF9B59D0),
                ],
                fill: const Color(0xFFFF7E8B),
                onFill: const Color(0xFFFFFFFF),
                labelThickness: 'Толщина',
                labelEraserThickness: 'Толщина ластика',
                labelColor: 'Цвет',
                toolLabels: const {DrawQuickTool.brush: 'Кисть', DrawQuickTool.eraser: 'Ластик'},
                onTool: (_) {},
                onWidth: (_) {},
                onColor: (_) {},
                onMoreColors: () {},
                onEyedropper: () {},
                eyedropperLabel: 'Пипетка',
                onBrushSettings: () {},
                brushSettingsLabel: 'Настройки кисти',
                symmetryOn: false,
                closeLabel: 'Свернуть',
                onClose: () {},
                brush: brush,
                brushes: pixel ? null : StrokeBrush.values,
                brushNames: _names,
                brushNotes: _notes,
                onBrush: onBrush ?? (_) {},
                eraserMode: eraserMode,
                eraserModes: pixel
                    ? const [EraserMode.hard, EraserMode.whole]
                    : EraserMode.values,
                eraserNames: _eraserNames,
                onEraserMode: onEraserMode ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('у кисти ряд из пяти образцов, под ним имя и подпись', (tester) async {
    StrokeBrush? picked;
    await tester.pumpWidget(_panel(onBrush: (b) => picked = b));
    for (final brush in StrokeBrush.values) {
      expect(find.byKey(ValueKey('brush-${brush.name}')), findsOneWidget);
    }
    expect(find.textContaining('Маркер'), findsOneWidget);
    expect(find.textContaining('Плоский и прозрачный'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('brush-pencil')));
    expect(picked, StrokeBrush.pencil);
  });

  testWidgets('у ластика свои режимы и толщина, цвета нет', (tester) async {
    EraserMode? picked;
    await tester.pumpWidget(_panel(tool: DrawQuickTool.eraser, onEraserMode: (m) => picked = m));
    expect(find.byKey(const ValueKey('brush-pen')), findsNothing);
    for (final mode in EraserMode.values) {
      expect(find.byKey(ValueKey('eraser-${mode.name}')), findsOneWidget);
    }
    expect(find.text('Линия целиком'), findsOneWidget);
    expect(find.text('ТОЛЩИНА ЛАСТИКА'), findsOneWidget);
    expect(find.text('ЦВЕТ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('eraser-whole')));
    expect(picked, EraserMode.whole);
  });

  testWidgets('на пиксельном холсте нет ряда кистей и мягкого ластика', (tester) async {
    await tester.pumpWidget(_panel(pixel: true));
    expect(find.byKey(const ValueKey('brush-pen')), findsNothing);
    await tester.pumpWidget(_panel(pixel: true, tool: DrawQuickTool.eraser));
    expect(find.byKey(const ValueKey('eraser-soft')), findsNothing);
    expect(find.byKey(const ValueKey('eraser-whole')), findsOneWidget);
  });

  testWidgets('у остальных инструментов ряда кистей нет, цвет на месте', (tester) async {
    await tester.pumpWidget(_panel(tool: DrawQuickTool.fill));
    expect(find.byKey(const ValueKey('brush-pen')), findsNothing);
    expect(find.text('ЦВЕТ'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320 точек, шрифт 1,3, ${brightness.name}: всё влезает', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final tool in [DrawQuickTool.brush, DrawQuickTool.eraser]) {
        await tester.pumpWidget(_panel(
          tool: tool,
          brush: StrokeBrush.calligraphy,
          brightness: brightness,
          textScale: 1.3,
        ));
        expect(tester.takeException(), isNull, reason: tool.name);
      }
    });
  }
}
