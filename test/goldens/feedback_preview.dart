import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/feedback.dart';
import 'package:love_app/screens/feedback_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Экран «Сообщить о проблеме» — на глаз. В общий прогон не входит:
/// `flutter test test/goldens/feedback_preview.dart`, снимки в `build/feedback/`.
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
  testWidgets('сообщить о проблеме', (tester) async {
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

    Future<void> shot(String name, Size size, Brightness light,
        {bool sent = false, bool child = false}) async {
      await tester.binding.setSurfaceSize(size);
      final key = GlobalKey();
      final scheme =
          ProfileTheme.themeFor(buildAppTheme(kPalettes[0], light)).colorScheme;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: FeedbackScreen(
            key: ValueKey(name),
            scheme: scheme,
            accountEmail: 'anna@example.com',
            initialKind: child ? FeedbackKind.childSafety : FeedbackKind.bug,
            send: (kind, text) async => FeedbackSent.ok,
          ),
        ),
      ));
      if (find.byKey(const Key('feedback_text')).evaluate().isNotEmpty) {
        await tester.enterText(find.byKey(const Key('feedback_text')),
            'После обновления не открывается лента воспоминаний: кручу, а она пустая.');
      }
      await tester.pump();
      if (sent) {
        await tester.tap(find.byKey(const Key('feedback_send')));
        await tester.pumpAndSettle();
      }
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final dir = Directory('build/feedback')..createSync(recursive: true);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shot('form-light', const Size(393, 860), Brightness.light);
    await shot('child-dark', const Size(393, 860), Brightness.dark, child: true);
    await shot('sent-light', const Size(393, 860), Brightness.light, sent: true);
    await shot('form-narrow', const Size(320, 568), Brightness.light, child: true);
    stdout.writeln('снимки: build/feedback/');
  });
}
