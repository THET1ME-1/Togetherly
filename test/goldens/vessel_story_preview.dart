import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/mood_vessel.dart';
import 'package:love_app/models/vessel_sharing.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/mood/vessel_story_card.dart';

/// Три направления карточки для сторис — на глаз, в 1080×1920.
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
        return VesselDay(
          date: DateTime(2026, 8, d),
          mineMood: roll > 1 ? moods[rnd.nextInt(moods.length)] : null,
          partnerMood: roll > 3 ? moods[rnd.nextInt(moods.length)] : null,
          intimacy: roll == 9,
          period: d >= 6 && d <= 9,
          partnerPeriod: d >= 20 && d <= 22,
          chatted: roll > 4,
          memories: [
            for (var i = 0; i < rnd.nextInt(3); i++)
              MemoryType.values[rnd.nextInt(MemoryType.values.length)],
          ],
        );
      }(),
  ];
}

void main() {
  testWidgets('карточка сосуда для сторис', (tester) async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dir = Directory('build/vessel')..createSync(recursive: true);
    // В картинку уходит то, что человек отметил на экране экспорта.
    final days = vesselForSharing(_august(), show: kDefaultSharedFloors);

    {
      await tester.binding
          .setSurfaceSize(const Size(kStoryWidth, kStoryHeight));
      final theme = buildAppTheme(kPalettes[0], Brightness.light);
      final cs = theme.scheme!;
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(cs),
          home: RepaintBoundary(
            key: key,
            child: VesselStoryCard(
              days: days,
              columns: 6,
              title: 'Август 2026',
              daysCaption: 'дней вместе в этом сосуде',
              hint: 'Один блок — день, плашки внутри — что вы в этот день сделали',
              scheme: cs,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/story.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      stdout.writeln('снимок: build/vessel/story.png');
    }
  });
}
