import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_quick_tools.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/draw/draw_tools_panel.dart';

/// Нижняя панель холста — на глаз, свёрнутая и раскрытая.
///
/// Имя без `_test`: файл для просмотра, а не сторож. Запуск:
/// `flutter test test/goldens/draw_tools_panel_preview.dart`,
/// картинки в `build/draw-panel/`.
///
/// Оба размера снимаются ОДНИМ тестом: двумя отдельными прогон вис по десять
/// минут уже после того, как снимок был записан.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  const palette = [
    Color(0xFF000000),
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFFBBF24),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ];

  testWidgets('панель рисования', (tester) async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    // Значки Material подшиваются из самого SDK: без них ряд инструментов
    // рисуется пустыми рамками, и смотреть нечего.
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    final cs = theme.scheme!;
    final fill = theme.fillColor;
    final onFill = AppThemes.onColor(fill, mode: theme.brightness);
    final dir = Directory('build/draw-panel')..createSync(recursive: true);

    // 393 — обычный телефон, 320 — самый узкий, который мы держим: там шесть
    // кнопок и восемь кружков делят строку впритык.
    for (final (dp, name) in <(double, String)>[
      (393, 'panel.png'),
      (320, 'panel-320.png'),
    ]) {
      // Размер меняем через setSurfaceSize: прямая подмена
      // `view.physicalSize` между кадрами вешала прогон на десять минут.
      await tester.binding.setSurfaceSize(Size(dp, 750));
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, colorScheme: cs),
          home: RepaintBoundary(
            key: key,
            child: Material(
              color: cs.surface,
              child: Column(
                children: [
                  // Место холста: панель показываем ровно там, где она живёт.
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(color: cs.surfaceContainerLowest),
                        ),
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: DrawToolBubble(
                            color: const Color(0xFFF97316),
                            icon: Icons.brush_rounded,
                            fill: fill,
                            onFill: onFill,
                            onTap: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                  DrawToolsSheet(
                    tool: DrawQuickTool.brush,
                    tools: const [
                      DrawQuickTool.brush,
                      DrawQuickTool.eraser,
                      DrawQuickTool.fill,
                      DrawQuickTool.shapes,
                      DrawQuickTool.layers,
                      DrawQuickTool.image,
                      DrawQuickTool.palm,
                      DrawQuickTool.clear,
                    ],
                    color: const Color(0xFFF97316),
                    width: 24,
                    minWidth: 1,
                    maxWidth: 40,
                    palette: palette,
                    fill: fill,
                    onFill: onFill,
                    labelThickness: 'Толщина',
                    labelColor: 'Цвет',
                    toolLabels: const {
                      DrawQuickTool.brush: 'Кисть',
                      DrawQuickTool.eraser: 'Ластик',
                      DrawQuickTool.fill: 'Заливка',
                      DrawQuickTool.shapes: 'Фигуры',
                      DrawQuickTool.layers: 'Слои',
                      DrawQuickTool.image: 'Фото',
                      DrawQuickTool.palm: 'Ладонь',
                      DrawQuickTool.background: 'Фон',
                      DrawQuickTool.clear: 'Очистить',
                      DrawQuickTool.replay: 'Как рисовали',
                    },
                    onTool: (_) {},
                    onWidth: (_) {},
                    onColor: (_) {},
                    onMoreColors: () {},
                    onEyedropper: () {},
                    eyedropperLabel: 'Пипетка',
                    onBrushSettings: () {},
                    brushSettingsLabel: 'Кисть',
                    symmetryOn: false,
                    closeLabel: 'Свернуть',
                    onClose: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Снимок только внутри runAsync: второй `toImage` за прогон без него не
      // возвращается вовсе — тест висит до таймаута, уже записав первый кадр.
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      stdout.writeln('снимок: build/draw-panel/$name');
    }

    // Телефон лёжа: панель уходит в колонку справа.
    await tester.binding.setSurfaceSize(const Size(780, 393));
    final sideKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorScheme: cs),
        home: RepaintBoundary(
          key: sideKey,
          child: Material(
            color: cs.surface,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(color: cs.surfaceContainerLowest),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: DrawToolsSheet(
                    tool: DrawQuickTool.brush,
                    tools: const [
                      DrawQuickTool.brush,
                      DrawQuickTool.eraser,
                      DrawQuickTool.fill,
                      DrawQuickTool.shapes,
                      DrawQuickTool.layers,
                      DrawQuickTool.image,
                      DrawQuickTool.palm,
                      DrawQuickTool.clear,
                    ],
                    color: const Color(0xFFF97316),
                    width: 24,
                    minWidth: 1,
                    maxWidth: 40,
                    palette: palette,
                    fill: fill,
                    onFill: onFill,
                    labelThickness: 'Толщина',
                    labelColor: 'Цвет',
                    toolLabels: const {
                      DrawQuickTool.brush: 'Кисть',
                      DrawQuickTool.eraser: 'Ластик',
                      DrawQuickTool.fill: 'Заливка',
                      DrawQuickTool.shapes: 'Фигуры',
                      DrawQuickTool.layers: 'Слои',
                      DrawQuickTool.image: 'Фото',
                      DrawQuickTool.palm: 'Ладонь',
                      DrawQuickTool.background: 'Фон',
                      DrawQuickTool.clear: 'Очистить',
                      DrawQuickTool.replay: 'Как рисовали',
                    },
                    onTool: (_) {},
                    onWidth: (_) {},
                    onColor: (_) {},
                    onMoreColors: () {},
                    onEyedropper: () {},
                    eyedropperLabel: 'Пипетка',
                    onBrushSettings: () {},
                    brushSettingsLabel: 'Кисть',
                    symmetryOn: false,
                    closeLabel: 'Свернуть',
                    onClose: () {},
                    side: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final sideBoundary =
        sideKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await sideBoundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${dir.path}/panel-side.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    stdout.writeln('снимок: build/draw-panel/panel-side.png');
  });
}
