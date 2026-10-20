import 'dart:async';
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
import 'package:shared_preferences/shared_preferences.dart';

/// Карточка кода на экране «Позовите свою половинку» для глаз:
/// `flutter test test/goldens/invite_code_preview.dart` →
/// build/invite-code/states.png. Два вида карточки (ждём код от сервера,
/// код готов) в четырёх рядах: Розовая светлая на 320 точках при шрифте 1,3,
/// Розовая тёмная, Фиолетовая светлая и Медовая тёмная на 393. Имя без
/// `_test`: обычный прогон его не берёт.
class _Pair extends PairData {
  _Pair({this.hang = false, this.ready = false});

  final bool hang;
  final bool ready;

  @override
  bool get isPaired => false;

  @override
  String get inviteCode => 'AB12CD';

  @override
  InviteCodeState get inviteCodeState =>
      ready ? InviteCodeState.ready : InviteCodeState.pending;

  @override
  String get shareableInviteCode => ready ? 'AB12CD' : '';

  @override
  Future<void> ensureInviteCodeIsReal() =>
      hang ? Completer<void>().future : Future<void>.value();
}

Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font(
        'MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter'
            '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  testWidgets('карточка кода: ждём сервер и код готов',
      (tester) async {
    final key = GlobalKey();

    Widget phone(PairData pair, theme, double w, double scale) => SizedBox(
          width: w,
          height: 640,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(w, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: InvitePartnerScreen(pairData: pair, theme: theme),
          ),
        );

    Widget row(int palette, Brightness mode, double w, double scale) {
      final theme = buildAppTheme(kPalettes[palette], mode);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          phone(_Pair(hang: true), theme, w, scale),
          const SizedBox(width: 16),
          phone(_Pair(ready: true), theme, w, scale),
        ],
      );
    }

    await tester.binding.setSurfaceSize(const Size(860, 2680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Material(
          color: const Color(0xFF8A8A8A),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Розовая светлая — тема новичка по умолчанию.
                row(0, Brightness.light, 320, 1.3),
                const SizedBox(height: 16),
                row(0, Brightness.dark, 393, 1.0),
                const SizedBox(height: 16),
                row(1, Brightness.light, 393, 1.0),
                const SizedBox(height: 16),
                row(13, Brightness.dark, 393, 1.0),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/invite-code/states.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // Повисшая сверка держит таймер предела: доводим его до конца, иначе
    // тест падает на незакрытом таймере.
    await tester.pump(const Duration(seconds: 21));
  });
}
