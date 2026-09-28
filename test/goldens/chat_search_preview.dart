import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/screens/chat/chat_search_screen.dart';
import 'package:love_app/services/locale_service.dart';

/// Экран поиска с найденным: `flutter test test/goldens/chat_search_preview.dart`,
/// картинка в `build/chat-search/search.png`.
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
    LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  testWidgets('поиск', (t) async {
    final key = GlobalKey();
    t.view.physicalSize = const Size(786, 1400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    ChatMsg m(String id, String uid, String text, int day) => ChatMsg(
        id: id, uid: uid, name: 'JB SHARAN', text: text,
        ts: DateTime(2026, 9, day, 21, 5).millisecondsSinceEpoch);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFE7E8B)), fontFamily: 'Onest'),
      home: RepaintBoundary(
        key: key,
        child: ChatSearchScreen(
          groupId: 'g',
          myUid: 'me',
          searcher: (_) async => [
            m('1', 'her', 'Завтра в то кафе у парка, где были в первый раз?', 27),
            m('2', 'me', 'Кафе закрыто по понедельникам, пойдём во вторник', 20),
            m('3', 'her', 'Помнишь, мы долго искали, где поужинать, а потом зашли в маленькое кафе на углу и там был тот самый торт', 2),
          ],
        ),
      ),
    ));
    await t.enterText(find.byType(TextField), 'кафе');
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/chat-search').createSync(recursive: true);
      File('build/chat-search/search.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
