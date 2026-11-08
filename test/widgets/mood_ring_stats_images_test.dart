import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/mood/mood_ring_stats.dart';
import 'package:love_app/widgets/mood_image.dart';

/// «Эмоции в статистике и выбранные на дне разные. На дне факт» (08.11.2026):
/// у пака котиков настроения называются как у стандартного (`laugh`, `love`),
/// и статистика рисовала жёлтые смайлы вместо выбранных котиков.
void main() {
  testWidgets('статистика рисует картинку из отметок, а не стандартного пака', (t) async {
    final cs = ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MoodRingStats(
          counts: const {'laugh': 1, 'love': 1},
          images: const {'laugh': 'kitty/laugh.webp', 'love': 'kitty/love.webp'},
          scheme: cs,
        ),
      ),
    ));
    final paths = t.widgetList<MoodImage>(find.byType(MoodImage)).map((m) => m.imagePath).toSet();
    expect(paths, {'kitty/laugh.webp', 'kitty/love.webp'});
  });
}
