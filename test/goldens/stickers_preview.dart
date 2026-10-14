import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_sticker.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/memory/note_pin.dart';
import 'package:love_app/widgets/memory/sticker_editor.dart';
import 'package:love_app/widgets/memory/sticker_layer.dart';
import 'package:love_app/widgets/memory/sticker_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Наклейки на пинах глазами: лента, наклеивание на карточке, лист наборов.
///
///   STICKER_PHOTO=<снимок.jpg> flutter test test/goldens/stickers_preview.dart
///   → build/stickers/*.png
///
/// Карточка повторяет `_photoTile` ленты (шапка, подпись, обложка, низ),
/// наклейки рисуют настоящие StickerAnchor и редактор. Без снимка вместо
/// фото тональная заливка.

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

const _bunnyCool = 'assets/images/mood_packs/bunny/cool.webp';
const _pinkLove = 'assets/images/mood_packs/pink/love.webp';
const _bunnyPride = 'assets/images/mood_packs/bunny/pride.webp';

final _stickers = [
  const MemorySticker(
      id: 'a', uid: 'me', image: _bunnyCool, x: .92, y: .06, size: .34, angle: .16, at: 1),
  const MemorySticker(
      id: 'b', uid: 'jb', image: _pinkLove, x: .04, y: .82, size: .29, angle: -.19, at: 2),
];

/// Картинки декодируются вне тестовых часов: даём им время и перерисовываем.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await _settle(tester);
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/stickers').createSync(recursive: true);
    File('build/stickers/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _loadFont('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  for (final b in Brightness.values) {
    testWidgets('лента, наклеивание и лист — ${b.name}', (tester) async {
      // Тема владельца: «Кофе».
      final theme = buildAppTheme(kPalettes[21], b);
      final cs = ProfileTheme.schemeFor(theme);
      final key = GlobalKey();
      final cardKey = GlobalKey<StickerCardScopeState>();
      tester.view.physicalSize = const Size(360 * 2, 780 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final photoPath = Platform.environment['STICKER_PHOTO'] ?? '';
      final hasPhoto = photoPath.isNotEmpty && File(photoPath).existsSync();
      late BuildContext appContext;

      Widget cover() => ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: hasPhoto
                  ? Image.file(File(photoPath), fit: BoxFit.cover)
                  : ColoredBox(color: cs.secondaryContainer),
            ),
          );

      Widget header(String who, String ago) => Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: cs.secondaryContainer,
                child: Text(who[0],
                    style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text(who,
                  style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.textPrimary)),
              Text('  ·  $ago',
                  style: TextStyle(fontFamily: 'Onest', fontSize: 12, color: theme.textMuted)),
            ]),
          );

      Widget feed() => ListView(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
            children: [
              StickerCardScope(
                key: cardKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardSurface,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header('THET1ME', '3 ч. назад'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text('Рыцари семи королевств',
                            style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: theme.textPrimary)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                        child: Text('Хороший сериал по факту',
                            style: TextStyle(fontFamily: 'Onest', fontSize: 15, color: theme.textPrimary)),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: StickerAnchor(stickers: _stickers, onTap: (_, _) {}, child: cover()),
                      ),
                      const SizedBox(height: 62),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.cardSurface,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header('JB SHARAN', '2 д. назад'),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: StickerAnchor(
                        stickers: const [
                          MemorySticker(
                              id: 'c', uid: 'me', image: _bunnyPride, x: .88, y: .7, size: .26, angle: .12),
                        ],
                        child: NotePin(
                          scheme: cs,
                          fill: theme.fillColor,
                          body: 'Купила билеты на субботу, не планируй ничего',
                          bodyBuilder: (t, s) => Text(t, style: s),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: ThemeScope(
          theme: theme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ProfileTheme.data(cs),
            home: Builder(builder: (context) {
              appContext = context;
              return Scaffold(
                backgroundColor: b == Brightness.dark ? Colors.black : cs.surface,
                body: feed(),
              );
            }),
          ),
        ),
      ));
      await _shot(tester, key, 'feed-${b.name}');

      // Наклеивание: новая наклейка посередине обложки.
      final card = cardKey.currentState!;
      final block = card.anchor!.globalRect!;
      final rect = card.globalRect!;
      placeStickerOnCard(appContext,
          block: block,
          card: rect,
          sticker: const MemorySticker(
              id: 'n', uid: 'me', image: _bunnyPride, x: .42, y: .55, size: .33, angle: -.1),
          isNew: true,
          others: card.anchor!.shown);
      await tester.pump(const Duration(milliseconds: 400));
      await _shot(tester, key, 'place-${b.name}');
      Navigator.of(appContext).pop();
      await tester.pump(const Duration(milliseconds: 400));

      showStickerPicker(appContext);
      await tester.pump(const Duration(milliseconds: 600));
      await _shot(tester, key, 'sheet-${b.name}');
    });
  }
}
