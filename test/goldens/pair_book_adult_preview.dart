import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/screens/pair_book_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Переключатель «Записи 18+ в книге» для глаз:
/// `flutter test test/goldens/pair_book_adult_preview.dart`
/// → build/pair-book-adult/{off,on}.png. Имя без `_test`: обычный прогон
/// его не берёт.
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

Memory _m(String id, int day, {bool adult = false}) => Memory(
      id: id,
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Аня',
      type: MemoryType.photo,
      createdAt: DateTime(2026, 5, day),
      isAdult: adult,
    );

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  testWidgets('переключатель 18+ в книге пары', (tester) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(360, 560));
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PairBookScreen(
          memories: [_m('a', 1), _m('b', 2), _m('hot', 3, adult: true)],
          theme: AppThemes.pink,
          coupleTitle: 'Аня и Петя',
          secretUnlocked: true,
        ),
      ),
    ));
    await tester.pump();

    Future<void> shot(String name) => tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 2);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File('build/pair-book-adult/$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
        });

    await shot('off');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await shot('on');
  });
}
