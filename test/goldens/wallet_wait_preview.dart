import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/screens/home/home_action_buttons.dart';
import 'package:love_app/screens/wallet_wait_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/wallet_teaser.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Снимки кнопки Togetherly Wallet и стены-чека настоящим кодом, для глаз.
///
/// Имя без `_test`: файл не сторож. Запуск:
/// `flutter test test/goldens/wallet_wait_preview.dart`, картинки —
/// `build/preview/wallet-*.png`.
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

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/preview')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/'
          'artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  for (final b in Brightness.values) {
    testWidgets('стена и ряд, ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final theme = buildAppTheme(kPalettes[0], b);

      final row = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: row,
          child: Container(
            color: theme.bgGradient.first,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Align(
              alignment: Alignment.topCenter,
              child: HomeActionButtons(
                theme: theme,
                isPaired: true,
                myMoodImagePath: '',
                onDraw: () {},
                onMood: () {},
                onCalendar: () {},
                onPost: () {},
                onWallet: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await _shot(tester, row, 'wallet-row-${b.name}');

      final wall = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: wall,
          child: WalletWaitScreen(
            theme: theme,
            load: () async => const WaitlistState(
                count: 2418, joined: false, place: 0, links: WalletLinks()),
            join: () async => const WaitlistState(
                count: 2419, joined: true, place: 2419, links: WalletLinks()),
          ),
        ),
      ));
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/logo/wallet_teaser.webp'),
          tester.element(find.byType(WalletWaitScreen))));
      await tester.pump(const Duration(milliseconds: 100));
      await _shot(tester, wall, 'wallet-wall-${b.name}');

      await tester.tap(find.byKey(const ValueKey('wallet-join')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await _shot(tester, wall, 'wallet-wall-${b.name}-joined');
    });
  }
}
