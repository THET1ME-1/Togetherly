import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/common/guide_hint.dart';
import 'package:love_app/widgets/common/guide_hint_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Обход нижнего меню Ту — на глаз:
/// `flutter test test/goldens/nav_guide_preview.dart` → `build/nav-guide/`.
/// Рисунок Ту в тесте не грузится (он из сети): где встаёт облачко, пишется
/// рядом в `<имя>.cloud` (имя анимации, левый край, верх, сторона).
Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font(
      'MaterialIcons',
      '${Platform.environment['HOME']}/snap/flutter/common/flutter'
          '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  testWidgets('Ту по очереди объясняет кнопки меню', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final theme = buildAppTheme(kPalettes[3], Brightness.light);
    final keys = {for (final i in HomeBottomNav.defaultOrder) i: GlobalKey()};
    final shotKey = GlobalKey();
    late BuildContext ctx;
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            backgroundColor: ProfileTheme.schemeFor(theme).surface,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: HomeBottomNav(selectedIndex: 0, theme: theme, isPaired: false, onTap: (_) {}, itemKeys: keys),
            ),
          );
        }),
      ),
    ));
    await tester.pump();
    Directory('build/nav-guide').createSync(recursive: true);
    final s = LocaleService.current;
    final texts = {0: s.navHintHome, 1: s.navHintWidgets, 4: s.navHintWatch, 2: s.navHintConnect, 3: s.navHintProfile};
    var n = 0;
    for (final i in HomeBottomNav.defaultOrder) {
      n++;
      final l = guideHintLayout(target: tester.getRect(find.byKey(keys[i]!)), screen: const Size(393, 852));
      File('build/nav-guide/$n.cloud').writeAsStringSync('${l.art} ${l.cloud.left} ${l.cloud.top} ${l.cloud.width}');
      final done = showGuideHint(ctx, targetKey: keys[i]!, text: texts[i]!, gotIt: s.gotIt, theme: theme);
      for (var k = 0; k < 15; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/nav-guide/$n.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.tap(find.text(s.gotIt));
      await tester.pump();
      await done;
    }
  });
}
