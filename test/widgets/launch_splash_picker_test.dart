import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';
import 'package:love_app/services/launch_splash_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/launch_splash/launch_splash_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ряд «Заставка при запуске» в «Оформлении»: влезает на 320 точек с
/// крупным шрифтом, нажатие выбирает заставку и скачивает её.
void main() {
  final splash = LaunchSplash.fromCatalog({
    'kind': 'splash',
    'data': {
      'key': 'hw_key',
      'ms': 1800,
      'step': 20,
      'until': '2099-01-01',
      'name': {'ru': 'Хэллоуин', 'en': 'Halloween', 'de': 'Halloween'},
      'window': {
        'path': 'M0,19 C-10,10 -20,0 -18,-10 C-14,-18 -4,-16 0,-10 Z',
        'track': [
          [180, 372, 0],
        ],
      },
      'sprites': {
        'door': {
          'frames': ['door'],
          'box': [0, 0, 360, 780],
        },
      },
      'layers': [
        {'sprite': 'door', 'fill': true, 'under': true},
      ],
      'files': {'door': 'https://x/door_a.webp', 'still': 'https://x/still_a.webp'},
    },
  })!;

  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('picker');
    LaunchSplashService.instance.debugReset();
    LaunchSplashService.rootDir = () async => root;
    LaunchSplashService.fetch = (url) async => [1, 2, 3];
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, AppLanguage lang, {double width = 320, double scale = 1.3}) async {
    LocaleService.instance.setLanguage(lang);
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: LaunchSplashPicker(splashes: [splash]),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final lang in const [AppLanguage.ru, AppLanguage.de, AppLanguage.zh]) {
    testWidgets('на 320 точках с шрифтом 1.3 без переполнений (${lang.code})', (tester) async {
      await pump(tester, lang);
      expect(tester.takeException(), isNull);
      expect(find.byType(LaunchSplashPicker), findsOneWidget);
    });
  }

  testWidgets('без выбора отмечен кадр «Без заставки»', (tester) async {
    await pump(tester, AppLanguage.ru);
    expect(find.text('Без заставки'), findsOneWidget);
    expect(find.text('Хэллоуин'), findsOneWidget);
    expect(find.text('1,8 с'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final check = tester.getCenter(find.byIcon(Icons.check_rounded));
    expect(tester.getRect(find.text('Без заставки')).left, lessThan(check.dx), reason: 'галочка на первом кадре');
  });

  testWidgets('нажатие выбирает заставку и скачивает её', (tester) async {
    await pump(tester, AppLanguage.ru);
    await tester.tap(find.byKey(const ValueKey('splash-tile-hw_key')));
    final manifest = File('${root.path}/hw_key/splash.json');
    // У скачивания много шагов, и каждому нужен кадр.
    final next = find.text('Сыграет при следующем запуске');
    for (var i = 0; i < 100 && next.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(LaunchSplashService.instance.selected, 'hw_key');
    expect(manifest.existsSync(), isTrue, reason: 'заставка не скачалась');
    expect(next, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('splash-tile-none')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(LaunchSplashService.instance.selected, '');
  });
}
