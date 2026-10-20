import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_view.dart';

/// Заставка «Ключ» на настоящих рисунках из мастерской: пока ключ летит и
/// поворачивается, приложение закрыто ночью; к концу окно-сердце открывает
/// его целиком на любом экране.
void main() {
  final dir = Directory('${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_splash/hw_key');
  final ok = dir.existsSync();
  const app = Color(0xFF00C853);
  const shot = ValueKey('shot');

  late LaunchSplash splash;

  setUpAll(() {
    if (!ok) return;
    final spec = jsonDecode(File('${dir.path}/splash.json').readAsStringSync()) as Map<String, dynamic>;
    final files = {
      for (final f in dir.listSync().whereType<File>())
        if (!f.path.endsWith('.json')) f.uri.pathSegments.last.split('.').first: f.path,
    };
    splash = LaunchSplash.fromJson({...spec, 'files': files})!;
  });

  Future<Map<String, ui.Image>> decode(WidgetTester tester) async {
    final images = <String, ui.Image>{};
    await tester.runAsync(() async {
      for (final name in splash.fileNames) {
        final codec = await ui.instantiateImageCodec(File(splash.files[name]!).readAsBytesSync());
        images[name] = (await codec.getNextFrame()).image;
      }
    });
    return images;
  }

  Future<Color> pixel(WidgetTester tester, Offset at) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shot));
    late Color color;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = ((at.dy.toInt() * image.width) + at.dx.toInt()) * 4;
      color = Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      image.dispose();
    });
    return color;
  }

  for (final screen in const [Size(360, 780), Size(412, 915), Size(800, 1280)]) {
    testWidgets('на ${screen.width.toInt()}×${screen.height.toInt()} закрывает приложение и открывает его окном',
        (tester) async {
      if (!ok) return;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final images = await decode(tester);
      var done = 0;
      await tester.pumpWidget(RepaintBoundary(
        key: shot,
        child: Stack(
          textDirection: TextDirection.ltr,
          children: [
            const Positioned.fill(child: ColoredBox(color: app)),
            Positioned.fill(child: LaunchSplashView(splash: splash, images: images, onDone: () => done++)),
          ],
        ),
      ));
      final center = Offset(screen.width / 2, screen.height / 2);
      final corner = Offset(screen.width * 0.08, screen.height * 0.08);

      await tester.pump(const Duration(milliseconds: 300));
      expect(await pixel(tester, center), isNot(app), reason: 'на 300 мс приложение должно быть закрыто');
      expect(await pixel(tester, corner), isNot(app), reason: 'ночь закрывает и края экрана');

      await tester.pump(const Duration(milliseconds: 1490));
      expect(await pixel(tester, center), app, reason: 'к концу окно открыло приложение');
      expect(await pixel(tester, corner), app, reason: 'окно к концу шире экрана');
      expect(done, 0);

      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 40));
      expect(done, 1, reason: 'конец сообщается один раз');
    });
  }
}
