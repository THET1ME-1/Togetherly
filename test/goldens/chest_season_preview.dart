import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/models/pair_jar.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/services/pair_jar_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

/// Лента сундуков с сезонным «Хэллоуин» (макет «Сундук на Хэллоуин», вариант
/// Б): обычный сундук и ночная страница, на 393 и 320 точках, плюс 320 при
/// шрифте 1.3. Файлы сундука берутся из запекания мастерской
/// (`~/Projects/togetherly-badges-hand/out_season/hw`), как их отдаст сервер.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/chest_season_preview.dart`, картинка в
/// `build/chest-season/season.png`.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  final dir = '${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_season/hw';

  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('сезонный сундук', (tester) async {
    if (!File('$dir/chest.json').existsSync()) return;
    // Кэш файлов и настройки звука просят папки и prefs; музыка в превью
    // не нужна — звук выключен.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    await tester.runAsync(() => ChestSound.instance.load());
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(3000, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Описание сундука — как его отдаст `/api/chest/state`: адреса файлов
    // заменены метками, байты кладутся в кэш проигрывателя напрямую.
    final spec = jsonDecode(File('$dir/chest.json').readAsStringSync()) as Map<String, dynamic>;
    final files = <String, String>{};
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final stem = name.split('.').first;
      if (name.endsWith('.json')) continue;
      files[stem] = 'hw://$name';
      ChestFrames.debugPut('hw://$name', f.readAsBytesSync());
    }
    final season = SeasonChest.fromJson({...spec, 'files': files})!;

    final key = GlobalKey();
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    Widget phone(double w, Widget child, {double scale = 1}) => Container(
      width: w,
      height: 2200,
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28)),
      child: MediaQuery(
        data: MediaQueryData(size: Size(w, 2200), textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    );
    ChestScreen screen(int page) => ChestScreen(
      theme: t,
      groupId: 'g',
      debugSeasons: [season],
      debugPage: page,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(t.scheme!),
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF171210),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                phone(393, screen(0)),
                phone(393, screen(1)),
                phone(320, screen(1)),
                phone(320, screen(1), scale: 1.3),
              ],
            ),
          ),
        ),
      ),
    );
    PairJarService.instance.apply(const PairJar(drops: [true, true, false], bonus: 0));
    // Кадры раскодируются по-настоящему: даём движку время между шагами.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 80));
    }

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('build/chest-season')..createSync(recursive: true);
      File('${out.path}/season.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    // Экраны держат таймеры и тикеры — снимаем дерево, пока тест жив.
    await tester.pumpWidget(const SizedBox());
    // Предельные таймеры загрузок (грома, файлов) досиживают своё.
    await tester.pump(const Duration(seconds: 20));
  });
}
