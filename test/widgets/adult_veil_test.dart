import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/memory/adult_veil.dart';
import 'package:love_app/widgets/memory/media_strip.dart';

/// Обращение 256 (11.10.2026): «Сделайте размывание контента 18+ у миниатюр
/// тоже». В ленте размыта была только обложка записи, а плёнка остальных
/// кадров под ней, плёнка полноэкранного просмотра, превью на главной и
/// карта воспоминаний показывали те же снимки открыто.
void main() {
  Future<ui.Image> pixel() async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.red);
    return rec.endRecording().toImage(4, 4);
  }

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('кадр плёнки 18+ закрыт размытием, касание по-прежнему открывает',
      (tester) async {
    final image = await tester.runAsync(pixel);
    var taps = 0;
    await tester.pumpWidget(host(FilmFrame(
      url: 'pb://media/a/x.jpg',
      provider: _Ready(image!),
      height: 56,
      blurred: true,
      onTap: () => taps++,
    )));
    expect(find.byType(AdultVeil), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    await tester.tap(find.byType(FilmFrame));
    expect(taps, 1);
  });

  testWidgets('обычный кадр плёнки не трогаем', (tester) async {
    final image = await tester.runAsync(pixel);
    await tester.pumpWidget(host(FilmFrame(
      url: 'pb://media/a/x.jpg',
      provider: _Ready(image!),
      height: 56,
    )));
    expect(find.byType(AdultVeil), findsNothing);
  });

  testWidgets('завеса не меняет размер плитки и влезает в самую мелкую',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox(
      width: 40,
      height: 40,
      child: AdultVeil(child: ColoredBox(color: Colors.red)),
    )));
    expect(tester.getSize(find.byType(AdultVeil)), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });

  test('миниатюры 18+ закрыты во всех местах, где их видно', () {
    String src(String path) => File(path).readAsStringSync();
    // Плёнка под обложкой в ленте и на странице записи.
    expect(src('lib/screens/memory_lane_screen.dart'),
        contains('blurred: memory.isAdult'));
    expect(src('lib/screens/memory_lane/detail.dart'),
        contains('blurred: memory.isAdult'));
    // Плёнка полноэкранного просмотра идёт сквозь все записи.
    expect(src('lib/screens/memory_lane/gallery.dart'),
        contains('blurred: widget.items[i].adult'));
    expect(src('lib/screens/memory_lane_screen.dart'), contains('adult: m.isAdult'));
    // Превью ленты на главной и карта воспоминаний.
    expect(src('lib/screens/home/home_memory_preview.dart'),
        contains('AdultVeil('));
    expect(src('lib/screens/memories_map_screen.dart'), contains('AdultVeil('));
  });
}

class _Ready extends ImageProvider<_Ready> {
  _Ready(this.image);
  final ui.Image image;

  @override
  Future<_Ready> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_Ready key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: image.clone())));
}
