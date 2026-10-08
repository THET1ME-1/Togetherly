import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/season_chest.dart';
import 'package:love_app/widgets/chest/season_glitch.dart';

/// Такты сбоя кнопки сезонного сундука по кадрам, для сверки с макетом
/// «Кнопка 666». Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/season_glitch_preview.dart` →
/// `build/chest-season/glitch.png`.
Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  testWidgets('такты сбоя', (tester) async {
    // Шрифт читается с диска по-настоящему: в поддельном времени теста он ждал бы вечно.
    await tester.runAsync(() => _font('Unbounded', 'assets/fonts/Unbounded.ttf'));
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const spec = SeasonGlitchSpec(mid: '13/13', peak: '666', peakColor: Color(0xFFA3101C), onPeak: Color(0xFFFFE9E4));
    final g = SeasonGlitch(spec);
    addTearDown(g.dispose);
    final key = GlobalKey();
    const style = TextStyle(fontFamily: 'Unbounded', fontSize: 16, fontWeight: FontWeight.w700);
    // Каждый кадр — своя застывшая копия такта: надпись строится позже, когда
    // живой сбой уже кончился.
    final frozen = <SeasonGlitch>[];
    addTearDown(() {
      for (final f in frozen) {
        f.dispose();
      }
    });
    final live = g;
    Widget button() {
      final g = SeasonGlitch(spec)
        ..phase = live.phase
        ..text = live.text
        ..power = live.power
        ..frame = live.frame;
      frozen.add(g);
      final (Color bg, Color fg) = switch (g.phase) {
        GlitchPhase.dim => (Color.lerp(const Color(0xFFF0924A), Colors.black, 0.4)!, const Color(0xFF2A1A0E)),
        GlitchPhase.neg => (const Color(0xFFF6F0FF), Colors.black),
        GlitchPhase.peak => (spec.peakColor!, spec.onPeak!),
        _ => (const Color(0xFFF0924A), const Color(0xFF2A1A0E)),
      };
      final torn = g.phase == GlitchPhase.split || g.phase == GlitchPhase.peak;
      return Stack(
        children: [
          Container(
            height: 56,
            alignment: Alignment.center,
            decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
            child: GlitchLabel(
              glitch: g,
              prefix: 'Открыть за рекламу',
              real: '3/3',
              style: style.copyWith(color: fg, letterSpacing: g.phase == GlitchPhase.peak ? 2.2 : null),
            ),
          ),
          if (torn)
            const Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(100)),
                child: CustomPaint(painter: GlitchScanlines()),
              ),
            ),
        ],
      );
    }

    final shots = <Widget>[];
    void snap() => shots.add(Padding(padding: const EdgeInsets.all(8), child: Material(type: MaterialType.transparency, child: button())));
    g.addListener(() {
      if (shots.length < 14) snap();
    });
    snap();
    final done = g.play();
    // Сбой идёт 0,9 с поддельного времени; ждать его конца без прокрутки
    // времени нельзя — тест повиснет.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await done;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(color: const Color(0xFF1E1729), child: ListView(children: shots)),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/chest-season')..createSync(recursive: true);
      File('${dir.path}/glitch.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
