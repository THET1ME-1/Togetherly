// Переходы «на всех экранах» глазами: экран настроек растёт из шестерёнки, а
// кадр летит из обложки в просмотр. Сверяются с макетом
// https://claude.ai/artifact/Ssgdjfc37xm7TigCWy6NGC (сцены «Кнопка → экран» и
// «Фото → просмотр»).
//
// Экраны настоящие: `SettingsScreen` и `FullscreenGallery`. Переход подключён
// так же, как в приложении, — строителем темы, а место вызова открывает
// обычный `MaterialPageRoute` и про переход не знает. Сети нет, поэтому в
// просмотре на месте кадра стоит прилетевшая миниатюра.
//
// Имя файла БЕЗ `_test`: обычный `flutter test` его не подхватывает.
//   flutter test test/goldens/unfold_all_preview.dart → build/unfold-all/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/screens/memory_lane_screen.dart';
import 'package:love_app/screens/settings_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/unfold/photo_flight.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';
import 'package:love_app/widgets/unfold/unfold_touch.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Снимок моря из настоящего скриншота профиля — тот же кадр, что в макете.
Uint8List _beach() {
  final shot = img.decodeJpg(
      File('docs/branding/raw/04-profile.jpg').readAsBytesSync())!;
  final crop = img.copyCrop(shot, x: 312, y: 276, width: 624, height: 364);
  return Uint8List.fromList(img.encodePng(crop));
}

void _nothing() {}

class _Home extends StatelessWidget {
  const _Home({required this.theme, required this.scheme, required this.photo});

  final AppTheme theme;
  final ColorScheme scheme;
  final ui.Image photo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Баннер профиля с круглой шестерёнкой, как в шапке профиля.
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                alignment: Alignment.topRight,
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('gear'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(
                          scheme: scheme,
                          accountEmail: 'thet1me@togetherly.day',
                          onAppearance: _nothing,
                          onNotifications: _nothing,
                          onLanguage: _nothing,
                          onCoinShop: _nothing,
                          onPrivacyPolicy: _nothing,
                          onExport: _nothing,
                          onResetMissYou: _nothing,
                          onTerms: _nothing,
                          onSupport: _nothing,
                          onOfficial: _nothing,
                          onDrawTools: _nothing,
                          onTelegramChannel: _nothing,
                          onBugBot: _nothing,
                          onAbout: _nothing,
                          onChangePassword: _nothing,
                          onLogout: _nothing,
                          onDeleteAccount: _nothing,
                          lockScreenMood: false,
                          onLockScreenMoodChanged: (_) {},
                          sideActionIsArrow: true,
                          onToggleSideAction: _nothing,
                        ),
                      ),
                    ),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.settings_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Карточка ленты: касание по обложке открывает просмотр.
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Берег',
                        style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      key: const ValueKey('cover'),
                      onTap: () => Navigator.of(context).push<String>(
                        PhotoFlightRoute<String>(
                          builder: (_) => const FullscreenGallery(
                            items: [
                              GalleryItem(
                                  url: 'pb://media/abc/a.jpg',
                                  memoryId: 'p1',
                                  caption: 'Берег'),
                            ],
                            initialIndex: 0,
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 170,
                          width: double.infinity,
                          child: RawImage(image: photo, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  late Uint8List beach;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await PocketBaseService().init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _loadFont('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    beach = _beach();
    UnfoldTouch.install();
  });

  testWidgets('настройки растут из шестерёнки, кадр летит в просмотр',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 780 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final root = GlobalKey();
    final theme = buildAppTheme(kPalettes[1], Brightness.light);
    final scheme = ProfileTheme.schemeFor(theme);
    late ui.Image photo;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(beach);
      photo = (await codec.getNextFrame()).image;
    });
    addTearDown(() => photo.dispose());

    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: ThemeScope(
        theme: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(scheme).copyWith(
            pageTransitionsTheme: PageTransitionsTheme(
              builders: {
                TargetPlatform.android: UnfoldPageTransitionsBuilder(
                  fallback: const PredictiveBackPageTransitionsBuilder(),
                  fill: (context) => Theme.of(context).colorScheme.surface,
                ),
              },
            ),
          ),
          home: _Home(theme: theme, scheme: scheme, photo: photo),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    Directory('build/unfold-all').createSync(recursive: true);
    Future<void> snap(String name) async {
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/unfold-all/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> frames(String name, List<int> at) async {
      var passed = 0;
      for (final ms in at) {
        await tester.pump(Duration(milliseconds: ms - passed));
        passed = ms;
        await snap('$name-${ms.toString().padLeft(3, '0')}');
      }
    }

    await snap('0-home');

    // Кнопка → экран.
    await tester.tap(find.byKey(const ValueKey('gear')));
    await tester.pump();
    await frames('1-set-open', [0, 30, 70, 120, 200, 320, 520]);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(BackButton));
    await frames('2-set-close', [0, 50, 110, 190, 300, 460]);
    await tester.pump(const Duration(milliseconds: 400));

    // Фото → просмотр.
    await tester.tap(find.byKey(const ValueKey('cover')));
    await tester.pump();
    await frames('3-photo-open', [0, 40, 90, 150, 230, 330, 640]);

    // Кадр тянут вниз и отпускают за порогом.
    final finger = await tester.startGesture(const Offset(180, 380));
    await finger.moveBy(const Offset(0, 30));
    await finger.moveBy(const Offset(14, 60));
    await tester.pump();
    await snap('4-pull-1');
    await finger.moveBy(const Offset(20, 90));
    await tester.pump();
    await snap('4-pull-2');
    await finger.up();
    await frames('5-drop', [0, 60, 140, 240, 440]);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
