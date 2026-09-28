import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_look.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/chat/bubble_looks.dart';
import 'package:love_app/widgets/chat/chat_look_sheet.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  await (FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
}

void main() {
  setUpAll(() async {
    if (!Platform.environment.containsKey('LOOK_PREVIEW')) return;
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  test('прежние значения читаются как раньше', () {
    expect(chatLookFromName('cozy'), ChatLook.cozy);
    expect(chatLookFromName('material'), ChatLook.material);
    expect(chatLookFromName('sticker'), ChatLook.sticker);
    expect(chatLookFromName(null), ChatLook.cozy);
    expect(chatLookFromName('???'), ChatLook.cozy);
  });

  test('дрожь: три кадра, восемь раз в секунду', () {
    expect([0, 124, 125, 250, 375, 500].map((ms) => stickerFrameAt(Duration(milliseconds: ms))),
        [0, 0, 1, 2, 0, 1]);
  });

  test('форма наклейки стоит на месте, кадры контура различаются', () {
    const r = Rect.fromLTWH(5, 5, 120, 40);
    final a = handRoundRect(r, 16, HandRandom(42));
    final b = handRoundRect(r, 16, HandRandom(42));
    final c = handRoundRect(r, 16, HandRandom(42 + 977));
    expect(a, b);
    expect(a, isNot(c));
    for (final p in a) {
      expect(p.dx, inInclusiveRange(r.left - 1, r.right + 1));
      expect(p.dy, inInclusiveRange(r.top - 1, r.bottom + 1));
    }
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('лист видов без переполнения на 320 dp, шрифт $scale', (t) async {
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      ChatLook? got;
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFFE7E8B)),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 700), textScaler: TextScaler.linear(scale)),
          child: Builder(builder: (ctx) => Scaffold(
            body: Center(child: TextButton(
              onPressed: () async => got = await showChatLookSheet(ctx,
                  current: ChatLook.cozy, mine: const Color(0xFFFE7E8B), partner: const Color(0xFFFFC9CF)),
              child: const Text('open'),
            )),
          )),
        ),
      ));
      await t.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      expect(find.byType(ChatLookCard), findsNWidgets(4));
      await t.tap(find.text('Наклейки'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(got, ChatLook.sticker);
    });
  }

  testWidgets('снимок наклеек и пикселя для глаз', (t) async {
    final key = GlobalKey();
    t.view.physicalSize = const Size(760, 800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    Widget bubble(CustomPainter p, String text, {bool dark = false}) => CustomPaint(
          painter: p,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(19, 15, 19, 15),
            child: Text(text, style: TextStyle(fontFamily: 'Onest', fontSize: 15, color: dark ? Colors.white : const Color(0xFF23191A))),
          ),
        );
    await t.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        // Как в чате: пузыри лежат на Material, без него Flutter метит текст
        // жёлтым подчёркиванием (признак отсутствующей темы, не вёрстки).
        child: Material(
          type: MaterialType.transparency,
          child: Container(
          color: const Color(0xFFFFF8F6),
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bubble(StickerBubblePainter(color: const Color(0xFFFFE2C6), seed: 3), 'Ты уже дома?'),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: bubble(StickerBubblePainter(color: const Color(0xFFFE7E8B), seed: 9), 'Почти, в маршрутке 🙈', dark: true)),
              const SizedBox(height: 14),
              bubble(StickerBubblePainter(color: const Color(0xFFFFE2C6), seed: 21), 'Напиши как зайдёшь,\nя подожду'),
            ])),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CustomPaint(painter: const PixelBubblePainter(color: Color(0xFFFFC9CF), tailLeft: true),
                  child: const Padding(padding: EdgeInsets.fromLTRB(14, 10, 14, 22), child: Text('Ты уже дома?', style: TextStyle(fontFamily: 'Onest', fontSize: 15)))),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: CustomPaint(painter: const PixelBubblePainter(color: Color(0xFFFE7E8B), tailLeft: false),
                  child: const Padding(padding: EdgeInsets.fromLTRB(14, 10, 14, 22), child: Text('Почти, в маршрутке', style: TextStyle(fontFamily: 'Onest', fontSize: 15, color: Colors.white))))),
            ])),
          ]),
        ),
        ),
      ),
    ));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/look').createSync(recursive: true);
      File('build/look/bubbles.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }, skip: !Platform.environment.containsKey('LOOK_PREVIEW'));
}
