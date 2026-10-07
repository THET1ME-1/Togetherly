import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/memory/note_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пин-заметка глазами: светлая и тёмная тема, 360 точек.
///
///   flutter test test/goldens/note_pin_preview.dart → build/note-pin/*.png
///
/// Шапки карточки здесь нет — её рисует лента, превью показывает сам лист.

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  for (final b in Brightness.values) {
    testWidgets('заметка ${b.name}', (tester) async {
      final theme = buildAppTheme(kPalettes[0], b);
      final cs = ProfileTheme.themeFor(theme).colorScheme;
      final key = GlobalKey();
      tester.view.physicalSize = const Size(360 * 2, 1100 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      Widget card(NotePin pin) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            decoration: BoxDecoration(
              color: theme.cardSurface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: pin,
          );

      Widget body(String text, TextStyle style) => Text(
            text,
            style: style,
            maxLines: 14,
            overflow: TextOverflow.ellipsis,
          );

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(
          key: key,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              color: b == Brightness.light ? const Color(0xFFFFE8DC) : cs.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  card(NotePin(
                    scheme: cs,
                    fill: theme.fillColor,
                    body: 'Возвращаюсь домой, купи мандаринов',
                    bodyBuilder: body,
                  )),
                  card(NotePin(
                    scheme: cs,
                    fill: theme.fillColor,
                    title: 'Список на выходные',
                    body: 'Забрать посылку\nКупить подарок маме\nЗаписаться на стрижку',
                    bodyBuilder: body,
                  )),
                  card(NotePin(
                    scheme: cs,
                    fill: theme.fillColor,
                    body: '',
                    bodyBuilder: body,
                  )),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/note-pin').createSync(recursive: true);
        File('build/note-pin/${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
