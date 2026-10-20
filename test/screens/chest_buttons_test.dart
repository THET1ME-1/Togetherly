import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_jar.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pair_jar_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Снимок владельца 20.10.2026: под сундуком две одинаковые кнопки
/// «Открываем…». У кнопки за рекламу и у кнопки копилки одна занятость на
/// двоих, и при ней обе писали «Открываем…». Пишет только нажатая, вторая
/// остаётся со своей надписью.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    PairJarService.instance.debugReset();
    PairJarService.instance.apply(const PairJar(bonus: 1));
  });
  tearDown(() => PairJarService.instance.debugReset());

  testWidgets('нажали копилку — «Открываем…» пишет только она', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ChestSound.instance.load());
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: ChestScreen(theme: t, groupId: 'g', debugSeasons: const []),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    final jar = find.ancestor(of: find.textContaining('копилки'), matching: find.byType(FilledButton));
    expect(jar, findsOneWidget, reason: 'кнопки копилки нет, а открытие в ней есть');
    // Надпись кнопки сейчас сменится, поэтому кнопку узнаём по месту.
    final jarPlace = tester.getRect(jar);
    await tester.tap(jar);
    await tester.pump();

    expect(find.text('Открываем…'), findsOneWidget, reason: 'две одинаковые кнопки «Открываем…»');
    expect(jarPlace.contains(tester.getCenter(find.text('Открываем…'))), isTrue,
        reason: '«Открываем…» обязана писать нажатая кнопка');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
