import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/screens/draw_replay_screen.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Экран повтора — на глаз. Имя без `_test`: смотреть, а не стеречь.
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

DrawStroke _arc(int index, int color) => DrawStroke(
      id: '$index',
      userId: 'u',
      colorValue: color,
      strokeWidth: 8,
      points: List.generate(24, (i) {
        final a = (i / 24) * math.pi + index * 0.4;
        return DrawPoint(0.5 + 0.32 * math.cos(a), 0.5 + 0.32 * math.sin(a));
      }),
      isEraser: false,
      isFilledShape: false,
      orderIndex: index,
    );

void main() {
  testWidgets('повтор рисования', (tester) async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(393, 780));

    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: DrawReplayScreen(
            strokes: [
              _arc(0, 0xFFEF4444),
              _arc(1, 0xFFF97316),
              _arc(2, 0xFF3B82F6),
              _arc(3, 0xFF22C55E),
            ],
            theme: theme,
          ),
        ),
      ),
    );
    // Даём повтору дорисовать примерно половину.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 800));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final dir = Directory('build/draw-panel')..createSync(recursive: true);
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${dir.path}/replay.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    stdout.writeln('снимок: build/draw-panel/replay.png');
  });
}
