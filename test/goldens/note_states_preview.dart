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

import '../support/fake_note_player.dart';

/// Кружок в новых состояниях: сжатие с процентами, загрузка, играет молча.
/// Запуск: `flutter test test/goldens/note_states_preview.dart`,
/// картинка в `build/note-states/states.png`.
Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  await (FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
}

ChatMsg _note(String id, String uid) => ChatMsg(
      id: id, uid: uid, name: 'Аня', text: '',
      ts: DateTime(2026, 9, 28, 21, 5).millisecondsSinceEpoch,
      noteUrl: '/tmp/$id.mp4', noteMs: 12000, noteShape: 'circle', noteSeenAt: 1,
    );

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  testWidgets('состояния кружка', (t) async {
    final key = GlobalKey();
    t.view.physicalSize = const Size(1700, 600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    NoteSendStatus.instance.set('c', const NoteSendState(NoteSendPhase.compressing, .45));
    NoteSendStatus.instance.set('u', const NoteSendState(NoteSendPhase.uploading));
    final playing = FakeNotePlayer();
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFE7E8B)), fontFamily: 'Onest'),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFFF8F6),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              for (final w in [
                NoteBubble(msg: _note('c', 'me'), isMine: true, size: 170, partnerReadTs: 0, autoplay: false, player: FakeNotePlayer()),
                NoteBubble(msg: _note('u', 'me'), isMine: true, size: 170, partnerReadTs: 0, autoplay: false, player: FakeNotePlayer()),
                NoteBubble(msg: _note('p', 'her'), isMine: false, size: 170, partnerReadTs: 0, autoplay: false, player: playing, onOpenFull: () {}),
                NoteBubble(msg: _note('s', 'me'), isMine: true, size: 170, partnerReadTs: 9e15.toInt(), autoplay: false, player: FakeNotePlayer()),
              ]) Padding(padding: const EdgeInsets.all(8), child: w),
            ]),
          ),
        ),
      ),
    ));
    await playing.open(messageId: 'p', url: '/tmp/p.mp4', auto: true);
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/note-states').createSync(recursive: true);
      File('build/note-states/states.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    NoteSendStatus.instance.clear('c');
    NoteSendStatus.instance.clear('u');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
