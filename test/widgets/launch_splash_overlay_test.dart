import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';
import 'package:love_app/services/launch_splash_service.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_overlay.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_view.dart';

/// Заставка при запуске играет с первого кадра (картинки разжаты до
/// runApp), закрывает приложение, не пропускает к нему касаний и уходит
/// целиком. Без заставки приложение доступно сразу.
void main() {
  final dir = Directory('${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_splash/hw_key');
  final ok = dir.existsSync();

  LaunchSplash splash() {
    final spec = jsonDecode(File('${dir.path}/splash.json').readAsStringSync()) as Map<String, dynamic>;
    final files = {
      for (final f in dir.listSync().whereType<File>())
        if (!f.path.endsWith('.json')) f.uri.pathSegments.last.split('.').first: f.path,
    };
    return LaunchSplash.fromJson({...spec, 'files': files})!;
  }

  Future<LaunchSplashReady> ready(WidgetTester tester) async {
    final s = splash();
    late Map<String, ui.Image> images;
    await tester.runAsync(() async => images = await LaunchSplashService.decode(s));
    return LaunchSplashReady(s, images);
  }

  Widget app(void Function() onTap) => MaterialApp(
        builder: (context, child) => LaunchSplashOverlay(child: child!),
        home: Scaffold(body: Center(child: ElevatedButton(onPressed: onTap, child: const Text('приложение')))),
      );

  tearDown(() => LaunchSplashOverlay.pending = null);

  testWidgets('играет с первого кадра, держит касания и уходит целиком', (tester) async {
    if (!ok) return;
    var taps = 0;
    LaunchSplashOverlay.pending = await ready(tester);
    await tester.pumpWidget(app(() => taps++));
    expect(find.byType(LaunchSplashView), findsOneWidget, reason: 'сцена с первого кадра, без пустой ночи');

    await tester.tap(find.text('приложение'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 0, reason: 'касание прошло сквозь заставку');

    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.byType(LaunchSplashView), findsNothing, reason: 'заставка обязана уйти целиком');
    await tester.tap(find.text('приложение'));
    expect(taps, 1);
  });

  testWidgets('заставка играет один раз: второй оверлей её не берёт', (tester) async {
    if (!ok) return;
    LaunchSplashOverlay.pending = await ready(tester);
    await tester.pumpWidget(app(() {}));
    expect(LaunchSplashOverlay.pending, isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('без заставки приложение доступно сразу', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(() => taps++));
    expect(find.byType(LaunchSplashView), findsNothing);
    await tester.tap(find.text('приложение'));
    expect(taps, 1);
  });
}
