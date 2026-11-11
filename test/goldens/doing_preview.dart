import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/doing.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/doing/doing_rooms.dart';
import 'package:love_app/widgets/doing/doing_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Чем заняты» — на глаз: превью комнаток и лист выбора занятия. В общий
/// прогон не входит: `flutter test test/goldens/doing_preview.dart`, снимки в
/// `build/doing/`. Рисунков Ту на снимках нет: каталог в тесте пуст.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  testWidgets('чем заняты', (tester) async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final at = DateTime(2026, 11, 11, 19, 40);

    Future<void> shot(String name, Size size, Brightness light, Widget Function(ColorScheme scheme) build) async {
      await tester.binding.setSurfaceSize(size);
      final key = GlobalKey();
      final theme = ProfileTheme.themeFor(buildAppTheme(kPalettes[0], light));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(backgroundColor: theme.colorScheme.surfaceContainerLow, body: build(theme.colorScheme)),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final dir = Directory('build/doing')..createSync(recursive: true);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Widget rooms(ColorScheme scheme, {Color? myWall, Color? partnerWall}) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DoingRooms(
              now: at,
              my: DoingRoomLook(wall: myWall ?? scheme.primaryContainer, doing: Doing.of('gym', at)),
              partner: DoingRoomLook(wall: partnerWall ?? scheme.tertiaryContainer, doing: Doing.of('movie', at)),
            ),
          ),
        );

    await shot('rooms-light', const Size(393, 220), Brightness.light, (s) => rooms(s));
    await shot('rooms-dark', const Size(393, 220), Brightness.dark, (s) => rooms(s));
    await shot('rooms-custom', const Size(393, 220), Brightness.light,
        (s) => rooms(s, myWall: const Color(0xFFFFFFFF), partnerWall: const Color(0xFF2F5FB3)));
    await shot('rooms-narrow', const Size(320, 190), Brightness.light, (s) => rooms(s));
    await shot('sheet-light', const Size(393, 860), Brightness.light,
        (s) => DoingSheet(groupId: 'g', scheme: s, current: Doing.of('gym', at), wall: const Color(0xFFCFE3FB)));
    await shot('sheet-dark', const Size(393, 860), Brightness.dark,
        (s) => DoingSheet(groupId: 'g', scheme: s, current: Doing.of('gym', at)));
    stdout.writeln('снимки: build/doing/');
  });
}
