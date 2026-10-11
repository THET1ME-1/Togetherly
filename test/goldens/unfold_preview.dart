// Переход «экран вырастает из карточки» глазами: кадры открытия записи из
// ленты, закрытия кнопкой и жеста «назад». Сверяются с макетом
// https://claude.ai/artifact/Ssgdjfc37xm7TigCWy6NGC (вариант А).
//
// Экран записи тут настоящий (`memoryDetailForPreview`), карточка ленты —
// повтор `_photoTile` с теми же метками общих элементов: сама лента живёт на
// потоке PocketBase и в тесте не поднимается. Сети нет, поэтому обложка на
// экране записи рисуется заглушкой; в полёте виден снимок карточки.
//
// Имя файла БЕЗ `_test`: обычный `flutter test` его не подхватывает.
//   flutter test test/goldens/unfold_preview.dart → build/unfold/*.png
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/models/memory.dart';
import 'package:love_app/screens/memory_lane_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/memory/media_strip.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _coverUrl = 'pb://media/abc/a.jpg';

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

class _Feed extends StatelessWidget {
  const _Feed({required this.theme, required this.memory, required this.photo});

  final AppTheme theme;
  final Memory memory;
  final ImageProvider photo;

  @override
  Widget build(BuildContext context) {
    Widget chip(Widget child, Color fill) => Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: fill, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: child,
        );

    final card = UnfoldSource(
      fill: theme.cardSurface,
      radius: 28,
      builder: (context, source) => GestureDetector(
        key: const ValueKey('card'),
        onTap: () => Navigator.of(context).push(UnfoldRoute<void>(
          source: source,
          builder: (_) => memoryDetailForPreview(memory),
        )),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardSurface,
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                  children: [
                    UnfoldShared(
                      tag: 'avatar',
                      radius: 20,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.primaryLight,
                        child: Text('T',
                            style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontWeight: FontWeight.w800,
                                color: theme.textPrimary)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    UnfoldShared(
                      tag: 'name',
                      fit: UnfoldFit.scale,
                      child: Text(memory.authorName,
                          style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.textPrimary)),
                    ),
                    Text('  ·  3 августа',
                        style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 12,
                            color: theme.textMuted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(memory.title!,
                        style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.textPrimary)),
                    Text(memory.caption!,
                        style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 15,
                            height: 1.35,
                            color: theme.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: UnfoldShared(
                    tag: 'cover',
                    radius: 22,
                    child: AspectCover(
                        url: _coverUrl,
                        provider: photo,
                        radius: 22,
                        maxHeight: 420),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    chip(
                        Icon(Icons.add_reaction_outlined,
                            size: 20, color: theme.textSecondary),
                        theme.bgGradient[0]),
                    const SizedBox(width: 6),
                    chip(
                        Icon(Icons.chat_bubble_outline_rounded,
                            size: 18, color: theme.textSecondary),
                        theme.bgGradient[0]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: theme.bgGradient[0],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 96, 12, 0),
          child: Column(
            children: [
              card,
              const SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: theme.cardSurface,
                  borderRadius: BorderRadius.circular(28),
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
    MediaAspectCache.put(_coverUrl, 624 / 364);
  });

  testWidgets('запись раскрывается из карточки и складывается обратно',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 780 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final root = GlobalKey();
    final theme = buildAppTheme(kPalettes[1], Brightness.light);
    final photo = MemoryImage(beach);
    final memory = Memory(
      id: 'p1',
      groupId: '',
      authorUid: 'u1',
      authorName: 'THET1ME',
      type: MemoryType.photo,
      createdAt: DateTime(2026, 8, 3, 18, 40),
      title: 'Берег',
      caption: 'Доехали за час до заката.',
      imageUrl: _coverUrl,
    );

    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: ThemeScope(
        theme: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: _Feed(theme: theme, memory: memory, photo: photo),
        ),
      ),
    ));
    // Картинка из памяти декодируется по-настоящему, не в поддельном времени.
    await tester.runAsync(() async {
      await precacheImage(photo, root.currentContext!);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Directory('build/unfold').createSync(recursive: true);
    Future<void> snap(String name) async {
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/unfold/$name.png')
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

    await snap('0-feed');

    // Открытие.
    await tester.tap(find.byKey(const ValueKey('card')));
    await tester.pump();
    await frames('1-open', [0, 40, 90, 150, 230, 330, 640]);

    // Закрытие кнопкой «назад».
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await frames('2-close', [0, 50, 110, 190, 300, 460]);

    // Жест от левого края: так на iPhone, на Android то же ведёт система.
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.tap(find.byKey(const ValueKey('card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final finger = await tester.startGesture(const Offset(4, 420));
    await finger.moveBy(const Offset(40, 0));
    await finger.moveBy(const Offset(60, 20));
    await tester.pump();
    await snap('3-drag-1');
    await finger.moveBy(const Offset(90, 30));
    await tester.pump();
    await snap('3-drag-2');
    await finger.up();
    await frames('4-drop', [0, 60, 140, 240, 460]);
    debugDefaultTargetPlatformOverride = null;

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
