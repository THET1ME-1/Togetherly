import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_vessel.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/mood/mood_vessel.dart';

/// Сосуд месяца — на глаз, в светлой и тёмной теме.
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

List<VesselDay> _august() {
  const moods = [
    Color(0xFFFF7E8B), Color(0xFFFFB05C), Color(0xFF7C6CF0),
    Color(0xFF4CC38A), Color(0xFF3B82F6),
  ];
  final rnd = math.Random(7);
  return [
    for (var d = 1; d <= 31; d++)
      () {
        final roll = rnd.nextInt(10);
        final mine = roll > 1 ? moods[rnd.nextInt(moods.length)] : null;
        final partner = roll > 3 ? moods[rnd.nextInt(moods.length)] : null;
        return VesselDay(
          date: DateTime(2026, 8, d),
          mineMood: mine,
          partnerMood: partner,
          intimacy: roll == 9,
          period: d >= 6 && d <= 9,
          partnerPeriod: d >= 20 && d <= 22,
        );
      }(),
  ];
}

void main() {
  testWidgets('сосуд месяца', (tester) async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dir = Directory('build/vessel')..createSync(recursive: true);
    final days = _august();

    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.binding.setSurfaceSize(const Size(393, 460));
      final theme = buildAppTheme(kPalettes[0], brightness);
      final cs = theme.scheme!;
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(cs),
          home: Scaffold(
            backgroundColor: cs.surface,
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: MoodVessel(
                    days: days,
                    columns: 6,
                    height: 320,
                    previousLevel: 9,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Даём кладке долететь.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 3));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/vessel-${brightness.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      stdout.writeln('снимок: build/vessel/vessel-${brightness.name}.png');
    }
  });
}
