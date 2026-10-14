// Снимки пина запечатанной капсулы рядом с пином-заметкой:
// flutter test test/goldens/sealed_capsule_preview.dart → build/sealed-capsule/.
//
// Шапка карточки здесь — копия `_cardHeader` ленты по виду: настоящая живёт
// внутри экрана ленты, которому нужен сервер.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/memory/note_pin.dart';
import 'package:love_app/widgets/sealed_capsule_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Widget _header(AppTheme t, String name, String when, IconData icon, String badge) {
  final p = t.primary;
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.withValues(alpha: 0.18)),
          child: Text(name[0],
              style: TextStyle(
                  fontFamily: 'Onest', fontWeight: FontWeight.w800, fontSize: 16, color: t.textPrimary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(TextSpan(style: const TextStyle(fontFamily: 'Onest'), children: [
            TextSpan(
                text: name,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
            TextSpan(text: '  ·  $when', style: TextStyle(fontSize: 12, color: t.textMuted)),
          ])),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: p.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: p),
            const SizedBox(width: 5),
            Text(badge,
                style: TextStyle(
                    fontFamily: 'Onest', fontSize: 12, fontWeight: FontWeight.w600, color: p)),
          ]),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  for (final (name, palette, b, width, scale, lang) in [
    ('coffee-light-360', 21, Brightness.light, 360.0, 1.0, AppLanguage.ru),
    ('coffee-dark-360', 21, Brightness.dark, 360.0, 1.0, AppLanguage.ru),
    ('pink-light-360', 0, Brightness.light, 360.0, 1.0, AppLanguage.ru),
    ('pink-dark-320-1.3-de', 0, Brightness.dark, 320.0, 1.3, AppLanguage.de),
  ]) {
    testWidgets(name, (tester) async {
      LocaleService.instance.setLanguage(lang);
      final theme = buildAppTheme(kPalettes[palette], b);
      final cs = ProfileTheme.schemeFor(theme);
      final s = LocaleService.current;
      const h = 760.0;
      tester.view.physicalSize = Size(width * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: lang.locale,
          supportedLocales: LocaleService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: cs.surface,
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                SealedCapsuleCard(
                  theme: theme,
                  header: _header(theme, 'Аня', '12 июля', Icons.hourglass_top_rounded,
                      s.memBadgeCapsule),
                  sealedAt: DateTime(2026, 7, 12, 20),
                  openAt: DateTime(2027, 2, 14, 9),
                  onTapTooEarly: () {},
                  now: () => DateTime(2026, 10, 14, 12),
                ),
                Container(
                  decoration: BoxDecoration(
                      color: theme.cardSurface, borderRadius: BorderRadius.circular(28)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(theme, 'Саша', 'вчера', Icons.sticky_note_2_rounded, s.memBadgeNote),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: NotePin(
                          scheme: cs,
                          fill: theme.fillColor,
                          body: 'Купили два билета на поезд до Одессы. Пусть это будет наше лето.',
                          bodyBuilder: (text, style) => Text(text, style: style),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/sealed-capsule').createSync(recursive: true);
        File('build/sealed-capsule/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
