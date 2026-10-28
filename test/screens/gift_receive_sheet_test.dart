import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/models/gift.dart';
import 'package:love_app/screens/gifts/gift_receive_sheet.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/app_sheet.dart';

/// TOG-39, обращение 471 (iPhone SE 2022, 24.10.2026): «кнопка забрать не
/// нажимается». На снимке лист подарка «Ключик» узкий, в половину экрана, а
/// «Забери ключ» под картинкой — обычная подсказка: принять подарок можно
/// было только касанием по самому ключу.
///
/// Лист сжимался, потому что модальный лист даёт содержимому свободную
/// ширину (до 640), а у подарков без кнопок в колонке нет ничего во всю
/// ширину, и лист садился по ширине картинки.
void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    LocaleService.instance.setLanguage(AppLanguage.ru);
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    ));
  });

  Future<void> open(WidgetTester tester, Gift gift, {Size size = const Size(375, 667), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    // Строка состояния iPhone SE, снизу отступа нет: кнопка «домой».
    tester.view.padding = const FakeViewPadding(top: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 20);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => GiftReceiveSheet.show(
                context,
                theme: AppThemes.byIndex(20),
                giftId: 'gggggggggggggg1',
                gift: gift,
                senderName: 'Аня',
              ),
              child: const Text('подарок'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('подарок'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  final key = GiftCatalog.byKey('key')!;

  testWidgets('лист подарка во всю ширину телефона, а не по ширине картинки', (tester) async {
    await open(tester, key);
    expect(tester.getSize(find.byType(GiftReceiveSheet)).width, 375, reason: 'лист сжался по ширине картинки');
    await done(tester);
  });

  testWidgets('«Забери ключ» — настоящая кнопка, и она принимает подарок', (tester) async {
    await open(tester, key);
    final button = find.widgetWithText(FilledButton, 'Забери ключ');
    expect(button, findsOneWidget, reason: 'подсказка выглядит кнопкой, а нажать её нельзя');

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, contains('POST /api/gifts/react'));
    await tester.pump(const Duration(seconds: 2));
    await done(tester);
  });

  testWidgets('высокий лист не заходит под строку состояния, и касание над ним его закрывает',
      (tester) async {
    // Шрифт вдвое крупнее: лист выше экрана, как бывает с запиской и снимком.
    await open(tester, GiftCatalog.byKey('photo')!, size: const Size(320, 568), scale: 2);
    final top = tester.getTopLeft(find.byType(GiftReceiveSheet)).dy;
    expect(top, greaterThanOrEqualTo(20 + kSheetTopGap),
        reason: 'лист дорос до верха, касаться над ним не по чему');

    await tester.tapAt(Offset(160, 20 + kSheetTopGap / 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GiftReceiveSheet), findsNothing);
    await done(tester);
  });

  // Обращение 471, 28.10.2026: «у письма кнопка наверх уехала». Над конвертом
  // висела крышка коробки — плашка цвета кнопки, а подсказка звала «Открой
  // коробку»: у «Письма» и «Коробки» одно действие, и сцена была одна на двоих.
  testWidgets('у письма нет крышки коробки, и подсказка про письмо', (tester) async {
    await open(tester, GiftCatalog.byKey('letter')!);
    expect(find.byKey(const ValueKey('gift-box-lid')), findsNothing, reason: 'над конвертом висит крышка коробки');
    expect(find.text('Открой коробку'), findsNothing);
    expect(find.text('Открой письмо'), findsOneWidget);
    await done(tester);
  });

  testWidgets('у коробки крышка на месте и подсказка про коробку', (tester) async {
    await open(tester, GiftCatalog.byKey('giftbox')!);
    expect(find.byKey(const ValueKey('gift-box-lid')), findsOneWidget);
    expect(find.text('Открой коробку'), findsOneWidget);
    await done(tester);
  });

  testWidgets('подсказка жеста кнопкой не становится: сердце принимают двойным касанием', (tester) async {
    await open(tester, GiftCatalog.byKey('heart')!);
    expect(find.byType(FilledButton), findsNothing);
    await done(tester);
  });

  for (final g in GiftCatalog.all) {
    testWidgets('320 точек при шрифте 1,3: «${g.key}» без переполнения', (tester) async {
      await open(tester, g, size: const Size(320, 568), scale: 1.3);
      expect(tester.takeException(), isNull);
      await done(tester);
    });
  }
}
