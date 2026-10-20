import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_overlay.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_view.dart';

/// Заставка при запуске закрывает приложение, пока играет, не пропускает к
/// нему касаний и уходит целиком. Без заставки и при «уменьшить движение»
/// приложение доступно сразу.
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

  Widget app(void Function() onTap, {bool calm = false}) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: calm),
          child: LaunchSplashOverlay(child: child!),
        ),
        home: Scaffold(body: Center(child: ElevatedButton(onPressed: onTap, child: const Text('приложение')))),
      );

  // Картинки разжимаются настоящим кодеком: ему нужно живое время, а каждому
  // шагу разжатия — кадр.
  Future<void> settleDecode(WidgetTester tester) async {
    for (var i = 0; i < 300 && find.byType(LaunchSplashView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  tearDown(() => LaunchSplashOverlay.pending = null);

  testWidgets('пока заставка играет, приложение не нажимается, потом заставки нет', (tester) async {
    if (!ok) return;
    var taps = 0;
    LaunchSplashOverlay.pending = splash();
    await tester.pumpWidget(app(() => taps++));
    await settleDecode(tester);
    expect(find.byType(LaunchSplashView), findsOneWidget);

    await tester.tap(find.text('приложение'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 0, reason: 'касание прошло сквозь заставку');

    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.byType(LaunchSplashView), findsNothing, reason: 'заставка обязана уйти целиком');
    await tester.tap(find.text('приложение'));
    expect(taps, 1);
  });

  testWidgets('пока картинки разжимаются, приложение закрыто ночью', (tester) async {
    if (!ok) return;
    LaunchSplashOverlay.pending = splash();
    await tester.pumpWidget(app(() {}));
    final night = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((b) => b.color);
    expect(night, contains(const Color(0xFF1E1729)));
    await settleDecode(tester);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('при «уменьшить движение» заставки нет', (tester) async {
    if (!ok) return;
    var taps = 0;
    LaunchSplashOverlay.pending = splash();
    await tester.pumpWidget(app(() => taps++, calm: true));
    await settleDecode(tester);
    expect(find.byType(LaunchSplashView), findsNothing);
    await tester.tap(find.text('приложение'));
    expect(taps, 1);
  });

  testWidgets('без заставки приложение доступно сразу', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(() => taps++));
    expect(find.byType(LaunchSplashView), findsNothing);
    await tester.tap(find.text('приложение'));
    expect(taps, 1);
  });
}
