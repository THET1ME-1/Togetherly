import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Значок для блока «Когда вы скучаете» — в ряду соседей по профилю.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/section_icon_preview.dart`.
/// Подшивает настоящие шрифты: без них тестовый рендер пишет и текст, и значки
/// пустыми квадратами. Тот же приём, что в `screens_golden_test`.
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
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('варианты значка', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final cs = buildAppTheme(kPalettes[7], Brightness.light).scheme!;

    Widget row(IconData icon, String title, {String note = ''}) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: ProfileTheme.sectionLabel(cs)),
              ),
              if (note.isNotEmpty)
                Text(note,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: cs.surface,
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  row(Icons.group_rounded, 'Друзья', note: 'соседи'),
                  row(Icons.favorite_rounded, 'Отношения', note: 'соседи'),
                  row(Icons.insights_rounded, 'Статистика', note: 'соседи'),
                  const Divider(height: 40),
                  row(Icons.calendar_view_week_rounded, 'Когда вы скучаете',
                      note: 'сейчас'),
                  row(Icons.monitor_heart_rounded, 'Когда вы скучаете',
                      note: 'пульс'),
                  row(Icons.schedule_rounded, 'Когда вы скучаете',
                      note: 'часы'),
                  row(Icons.bar_chart_rounded, 'Когда вы скучаете',
                      note: 'столбики'),
                  row(Icons.volunteer_activism_rounded, 'Когда вы скучаете',
                      note: 'ладони'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/section-icon.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
