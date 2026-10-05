import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/postcard/models/postcard_template.dart';
import 'package:love_app/screens/postcard/widgets/postcard_card.dart';
import 'package:love_app/services/locale_service.dart';

/// Все восемь открыток как есть — для сравнения перед редизайном.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/postcards_now_preview.dart`, картинка в
/// `build/postcards/now.png`.
Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  await (FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons', '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  testWidgets('открытки сейчас', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(1440, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const stats = PostcardStats(memories: 214, drawings: 37, missYou: 1288, streak: 41);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEFE7E4),
        body: RepaintBoundary(
          key: key,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in PostcardTemplate.all)
                SizedBox(
                  width: 340,
                  height: 340,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: PostcardCard(
                      templateId: t.id,
                      days: 440,
                      isEditing: false,
                      blocks: PostcardTemplate.defaultBlocks(
                        templateId: t.id,
                        days: 440,
                        myName: 'Аня',
                        partnerName: 'Боря',
                        stats: stats,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/postcards').createSync(recursive: true);
      File('build/postcards/now.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
