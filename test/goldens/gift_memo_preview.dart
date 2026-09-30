import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/models/partner_profile.dart';
import 'package:love_app/screens/gifts/gift_memo_sheet.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/app_sheet.dart';

/// Лист подарка (вариант А) на розовой теме, 393 и 320.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/gift_memo_preview.dart`, картинка в
/// `build/qr-preview/gift_memo.png`.
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

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('лист подарка', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(1600, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final cs = ProfileTheme.schemeFor(AppThemes.pink);
    final key = GlobalKey();
    const gift = Gift(
        key: 'hug', price: 15, engine: GiftEngine.response,
        titleRu: 'Обнимашка', titleEn: 'Hug');
    final year = DateTime.now().year;
    final memos = [
      GiftMemo(
        giftKey: 'hug',
        sentAt: DateTime(year, 9, 12),
        senderUid: 'sasha',
        note: 'Держи обнимашку на весь день, вечером приду за настоящей.',
        reply: 'Жду тебя!',
        place: 'Кофейня на Пушкина',
        date: DateTime(year, 9, 12, 19),
      ),
      GiftMemo(
          giftKey: 'hug',
          sentAt: DateTime(year, 8, 3),
          senderUid: 'sasha',
          note: 'Это тебе просто так.'),
      GiftMemo(giftKey: 'hug', sentAt: DateTime(2025, 12, 31), senderUid: 'chest'),
    ];

    Widget phone(double w) => Container(
          width: w,
          height: 700,
          margin: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28)),
          child: Material(
            color: cs.surfaceContainerLow,
            child: SheetScaffold(
              child: GiftMemoList(
                gift: gift,
                memos: memos,
                myUid: 'me',
                shelfOwnerUid: 'me',
                counterpartName: 'Саша',
                scheme: cs,
                ru: true,
                strings: LocaleService.current,
              ),
            ),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ProfileTheme.data(cs),
      home: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFF171210),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [phone(393), phone(320)],
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      await precacheImage(
          const AssetImage('assets/images/gifts/hug.webp'), key.currentContext!);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/gift_memo.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
