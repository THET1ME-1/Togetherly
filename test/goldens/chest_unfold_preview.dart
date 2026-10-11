// Сундук перелетает с главной на свой экран: кадры открытия и возврата.
//
// Карточка тут — повтор блока сундука с главной (`ChestHomeCard`) с теми же
// метками перехода; сам блок в тесте не поднять, он ходит на сервер. Экран
// сундука настоящий, файлы сезона — из запекания мастерской
// (`~/Projects/togetherly-badges-hand/out_season/hw`), как их отдаст сервер.
//
// Имя файла БЕЗ `_test`: обычный `flutter test` его не подхватывает.
//   flutter test test/goldens/chest_unfold_preview.dart → build/chest-unfold/
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

class _Home extends StatelessWidget {
  const _Home({required this.theme, required this.season});

  final AppTheme theme;
  final SeasonChest season;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(theme);
    final night = season.palette!;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 260, 12, 0),
          child: Column(
            children: [
              UnfoldSource(
                fill: night.surface,
                radius: 28,
                builder: (context, source) => Material(
                  color: night.surface,
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('card'),
                    onTap: () => Navigator.of(context).push(unfoldFrom<void>(
                      source,
                      (_) => ChestScreen(
                        theme: theme,
                        groupId: 'g',
                        debugSeasons: [season],
                        initialSeason: season,
                      ),
                    )),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 10, 16, 10),
                      child: Row(
                        children: [
                          UnfoldShared(
                            tag: chestUnfoldTag(season.key),
                            child: ChestFrames(
                              url: season.file('idle'),
                              still: null,
                              stillUrl: season.file('still'),
                              side: 112,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(season.nameIn('ru'),
                                    style: TextStyle(
                                        fontFamily: 'Unbounded',
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: night.ink)),
                                const SizedBox(height: 4),
                                Text(season.hintIn('ru'),
                                    style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color: night.ink)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
  final dir =
      '${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_season/hw';

  setUpAll(() async {
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _loadFont('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  testWidgets('сундук летит с главной на экран и обратно', (tester) async {
    if (!File('$dir/chest.json').existsSync()) return;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    await tester.runAsync(() => ChestSound.instance.load());
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(360 * 2, 780 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final spec = jsonDecode(File('$dir/chest.json').readAsStringSync())
        as Map<String, dynamic>;
    final files = <String, String>{};
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.json')) continue;
      files[name.split('.').first] = 'hw://$name';
      ChestFrames.debugPut('hw://$name', f.readAsBytesSync());
    }
    final season = SeasonChest.fromJson({...spec, 'files': files})!;

    final root = GlobalKey();
    final theme = buildAppTheme(
        kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(theme.scheme!),
        home: _Home(theme: theme, season: season),
      ),
    ));

    /// Кадры сундука разжимаются по-настоящему, не в поддельном времени.
    Future<void> run(int ms) async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(Duration(milliseconds: ms));
    }

    for (var i = 0; i < 6; i++) {
      await run(40);
    }

    Directory('build/chest-unfold').createSync(recursive: true);
    Future<void> snap(String name) async {
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/chest-unfold/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> frames(String name, List<int> at) async {
      var passed = 0;
      for (final ms in at) {
        await run(ms - passed);
        passed = ms;
        await snap('$name-${ms.toString().padLeft(3, '0')}');
      }
    }

    await snap('0-home');
    await tester.tap(find.byKey(const ValueKey('card')));
    await tester.pump();
    await frames('1-open', [0, 40, 90, 150, 230, 330, 640]);
    for (var i = 0; i < 8; i++) {
      await run(60);
    }
    await snap('2-open-settled');

    await tester.tap(find.byType(BackButton));
    await frames('3-close', [0, 50, 110, 190, 300, 460]);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
