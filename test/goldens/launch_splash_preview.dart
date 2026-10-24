// Кадры заставки «Ключ» для сверки глазами с макетом:
//   flutter test test/goldens/launch_splash_preview.dart
// Пишет build/launch-splash/<мс>.png: настоящий рисовальщик приложения поверх
// снимка главной из макета. Нужны out_splash/hw_key в мастерской значков и
// img/home_hw.webp в папке макета.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_view.dart';

void main() {
  final home = Platform.environment['HOME'];
  final dir = Directory('$home/Projects/GitHub/togetherly-badges-hand/out_splash/hw_key');
  final under = File('$home/Projects/GitHub/togetherly-splash-mockup/img/home_hw.webp');

  testWidgets('кадры заставки', (tester) async {
    if (!dir.existsSync() || !under.existsSync()) return;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final spec = jsonDecode(File('${dir.path}/splash.json').readAsStringSync()) as Map<String, dynamic>;
    final files = {
      for (final f in dir.listSync().whereType<File>())
        if (!f.path.endsWith('.json')) f.uri.pathSegments.last.split('.').first: f.path,
    };
    final splash = LaunchSplash.fromJson({...spec, 'files': files})!;
    final images = <String, ui.Image>{};
    late ui.Image app;
    await tester.runAsync(() async {
      for (final name in splash.fileNames) {
        final codec = await ui.instantiateImageCodec(File(splash.files[name]!).readAsBytesSync());
        images[name] = (await codec.getNextFrame()).image;
      }
      final codec = await ui.instantiateImageCodec(under.readAsBytesSync());
      app = (await codec.getNextFrame()).image;
    });
    const shot = ValueKey('shot');
    await tester.pumpWidget(RepaintBoundary(
      key: shot,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          Positioned.fill(child: RawImage(image: app, fit: BoxFit.cover)),
          Positioned.fill(child: LaunchSplashView(splash: splash, images: images)),
        ],
      ),
    ));
    final out = Directory('build/launch-splash')..createSync(recursive: true);
    var now = 0;
    for (final ms in const [0, 150, 400, 700, 900, 1000, 1100, 1250, 1400, 1600, 1760]) {
      await tester.pump(Duration(milliseconds: ms - now));
      now = ms;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shot));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/${ms.toString().padLeft(4, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
