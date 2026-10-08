import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/models/gift_art.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лента сундуков на живом экране (жалоба с телефона 08.10.2026): у сундука
/// не было анимации, а «Хэллоуин →» проигрывал занавес и оставлял на месте
/// обычный сундук — уже в ночных цветах.
void main() {
  final dir = '${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_season/hw';
  final ok = File('$dir/chest.json').existsSync();

  late SeasonChest season;

  setUp(() {
    if (!ok) return;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    final spec = jsonDecode(File('$dir/chest.json').readAsStringSync()) as Map<String, dynamic>;
    final files = <String, String>{};
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.json')) continue;
      files[name.split('.').first] = 'hw://$name';
      ChestFrames.debugPut('hw://$name', f.readAsBytesSync());
    }
    season = SeasonChest.fromJson({...spec, 'files': files})!;
    // покой обычного сундука — любой живой файл
    ChestFrames.debugPut('main://idle', File('$dir/idle.webp').readAsBytesSync());
  });

  Future<void> run(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget screen() {
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    return MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: ChestScreen(theme: t, groupId: 'g', debugSeasons: [season]),
    );
  }

  Set<int> shownFrames(WidgetTester tester) => {
    for (final r in tester.widgetList<RawImage>(find.byType(RawImage))) identityHashCode(r.image),
  };

  test('лента сундуков не лежит в выгружающем списке', () {
    // ListView выгружал ушедшую за край ленту, и после просмотра призов внизу
    // экран возвращался к обычному сундуку (жалоба с 1.35.0+245).
    final src = File('lib/screens/chest_screen.dart').readAsStringSync();
    final body = src.substring(src.indexOf('body: _shake('), src.indexOf('_pagerView(base)'));
    expect(body.contains('ListView('), isFalse);
    expect(body.contains('SingleChildScrollView('), isTrue);
  });

  testWidgets('сундук оживает, даже если каталог доехал после открытия экрана', (tester) async {
    if (!ok) return;
    phone(tester);
    await tester.runAsync(() => ChestSound.instance.load());
    CatalogService.instance.debugSetGiftArt(const []);
    await tester.pumpWidget(screen());
    await run(tester, 3);
    CatalogService.instance.debugSetGiftArt(const [GiftArt(key: 'chest_idle', lgUrl: 'main://idle')]);
    final seen = <int>{};
    for (var i = 0; i < 12; i++) {
      await run(tester, 1);
      seen.addAll(shownFrames(tester));
    }
    expect(seen.length, greaterThan(3), reason: 'кадры покоя обычного сундука должны сменяться');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('с главной экран открывается сразу на сезонном сундуке', (tester) async {
    if (!ok) return;
    phone(tester);
    await tester.runAsync(() => ChestSound.instance.load());
    CatalogService.instance.debugSetGiftArt(const [GiftArt(key: 'chest_idle', lgUrl: 'main://idle')]);
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: ChestScreen(theme: t, groupId: 'g', debugSeasons: [season], initialChest: 'hw'),
    ));
    await run(tester, 60);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page!.round(), 1);
    expect(find.text('← Обычный'), findsOneWidget, reason: 'к обычному можно вернуться');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('«Хэллоуин →» переводит ленту на сезонный сундук', (tester) async {
    if (!ok) return;
    phone(tester);
    await tester.runAsync(() => ChestSound.instance.load());
    CatalogService.instance.debugSetGiftArt(const [GiftArt(key: 'chest_idle', lgUrl: 'main://idle')]);
    await tester.pumpWidget(screen());
    await run(tester, 3);
    // покой обычного сундука играет и тогда, когда каталог уже был
    final seen = <int>{};
    for (var i = 0; i < 10; i++) {
      await run(tester, 1);
      seen.addAll(shownFrames(tester));
    }
    expect(seen.length, greaterThan(3), reason: 'кадры покоя обычного сундука должны сменяться');
    double page() => tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    await tester.tap(find.text('Хэллоуин →'));
    await run(tester, 3);
    expect(page(), 0, reason: 'пока тьма не закрыла экран, лента стоит: новую страницу не видно раньше занавеса');
    expect(find.byType(Image), findsWidgets);
    await run(tester, 60);
    expect(page().round(), 1, reason: 'после занавеса на экране сезонный сундук');
    // обратно кнопкой и снова вперёд пальцем
    await tester.tap(find.text('← Обычный'));
    await run(tester, 60);
    expect(page().round(), 0, reason: 'после дневного занавеса — обычный сундук');
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await run(tester, 60);
    expect(page().round(), 1, reason: 'свайп тоже доводит до сезонного сундука');
    // кнопка срывается в 666 (первый сбой — через 5–9 с) — лента стоит на месте
    var peaked = false;
    for (var i = 0; i < 300 && !peaked; i++) {
      await run(tester, 1);
      peaked = find.textContaining('666').evaluate().isNotEmpty;
    }
    expect(peaked, isTrue, reason: 'сбой кнопки должен был случиться');
    await run(tester, 40);
    expect(page().round(), 1, reason: 'после «666» на экране по-прежнему сезонный сундук');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
