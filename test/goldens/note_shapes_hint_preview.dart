import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/note_send_status.dart';
import 'package:love_app/widgets/chat/note_bubble.dart';
import 'package:love_app/widgets/chat/note_shapes.dart';

import '../support/fake_note_player.dart';

/// Все формы кружка: верхний ряд играет молча (подсказка про звук), нижний
/// отправляется. Запуск: `flutter test test/goldens/note_shapes_hint_preview.dart`,
/// картинка в `build/note-states/shapes.png`.
Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  await (FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    LocaleService.instance.setLanguage(AppLanguage.de); // самая длинная подпись
  });

  testWidgets('подсказка и значки внутри каждой формы', (t) async {
    final key = GlobalKey();
    t.view.physicalSize = const Size(4200, 1000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    ChatMsg msg(String id, String shape) => ChatMsg(
          id: id, uid: 'her', name: 'A', text: '', ts: 1,
          noteUrl: '/tmp/$id.mp4', noteMs: 9000, noteShape: shape, noteSeenAt: 1);
    final players = <FakeNotePlayer>[];
    final top = <Widget>[], bottom = <Widget>[];
    for (final s in kNoteShapes) {
      final p = FakeNotePlayer();
      players.add(p);
      top.add(NoteBubble(msg: msg('t${s.id}', s.id), isMine: false, size: 190, partnerReadTs: 0, autoplay: false, player: p, onOpenFull: () {}));
      NoteSendStatus.instance.set('b${s.id}', const NoteSendState(NoteSendPhase.compressing, .5));
      bottom.add(NoteBubble(msg: msg('b${s.id}', s.id), isMine: true, size: 190, partnerReadTs: 0, autoplay: false, player: FakeNotePlayer()));
    }
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFE7E8B)), fontFamily: 'Onest'),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFFF8F6),
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Wrap(spacing: 8, runSpacing: 8, children: top),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: bottom),
            ]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < kNoteShapes.length; i++) {
      await players[i].open(messageId: 't${kNoteShapes[i].id}', url: '/tmp/x.mp4', auto: true);
    }
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1.4);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/note-states').createSync(recursive: true);
      File('build/note-states/shapes.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    for (final s in kNoteShapes) {
      NoteSendStatus.instance.clear('b${s.id}');
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
