import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/invite_partner_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/common/guide_hint_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подсказки Ту на экране «Позовите свою половинку» — на глаз:
/// `flutter test test/goldens/invite_guide_preview.dart` → `build/invite-guide/`.
class _Pair extends PairData {
  @override
  bool get isPaired => false;

  @override
  String get inviteCode => 'LAS9X5';

  @override
  InviteCodeState get inviteCodeState => InviteCodeState.ready;

  @override
  String get shareableInviteCode => 'LAS9X5';

  @override
  Future<void> ensureInviteCodeIsReal() async {}
}

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

  testWidgets('две подсказки Ту по очереди', (tester) async {
    final key = GlobalKey();
    // Размер окна, а не поверхности: облачко раскладывается по MediaQuery.
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final theme = buildAppTheme(kPalettes[3], Brightness.light);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: InvitePartnerScreen(pairData: _Pair(), theme: theme),
      ),
    ));

    Future<void> shot(String name) async {
      // Картинки Ту декодируются по-настоящему, вне подменённого времени.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pump(const Duration(milliseconds: 600));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/invite-guide/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // Где встаёт облачко: рисунок Ту в тесте не грузится (он из сети), и
    // кадр из мастерской (`out_guide/<имя>/still.png`) накладывается на
    // снимок по этим числам: имя, левый край, верх, сторона.
    void place(String name, Finder target, {bool? below}) {
      final l = guideHintLayout(target: tester.getRect(target), screen: const Size(393, 852), below: below);
      File('build/invite-guide/$name.cloud').writeAsStringSync(
          '${l.art} ${l.cloud.left} ${l.cloud.top} ${l.cloud.width}');
    }

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    Directory('build/invite-guide').createSync(recursive: true);
    place('1-code', find.ancestor(of: find.text('LAS9X5'), matching: find.byType(Material)).first);
    place('2-enter', find.ancestor(of: find.text(LocaleService.current.haveCode), matching: find.byType(Expanded)).first, below: true);
    await shot('1-code');
    await tester.tap(find.text(LocaleService.current.gotIt));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot('2-enter');
    await tester.tap(find.text(LocaleService.current.gotIt));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 13));
  });
}
