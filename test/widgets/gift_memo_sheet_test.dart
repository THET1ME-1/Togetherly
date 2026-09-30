// Лист подарка по варианту А макета: подарок на «печеньке», сколько раз
// дарили, карточка на каждый раз с запиской, ответом и встречей.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/models/partner_profile.dart';
import 'package:love_app/screens/gifts/gift_memo_sheet.dart';
import 'package:love_app/services/locale_service.dart';

const _gift = Gift(
  key: 'hug',
  price: 15,
  engine: GiftEngine.response,
  titleRu: 'Обнимашка',
  titleEn: 'Hug',
);

final _memos = [
  GiftMemo(
    giftKey: 'hug',
    sentAt: DateTime(DateTime.now().year, 9, 12),
    senderUid: 'sasha',
    note: 'Держи обнимашку на весь день, вечером приду за настоящей.',
    reply: 'Жду тебя!',
    place: 'Кофейня на Пушкина',
    date: DateTime(DateTime.now().year, 9, 12, 19),
  ),
  GiftMemo(giftKey: 'hug', sentAt: DateTime(2025, 8, 3), senderUid: 'chest'),
];

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  test('раз, раза, раз', () {
    expect(giftTimesLabel(1, ru: true), '1 раз');
    expect(giftTimesLabel(2, ru: true), '2 раза');
    expect(giftTimesLabel(5, ru: true), '5 раз');
    expect(giftTimesLabel(12, ru: true), '12 раз');
    expect(giftTimesLabel(22, ru: true), '22 раза');
    expect(giftTimesLabel(1, ru: false), 'once');
  });

  Future<void> pump(WidgetTester tester, String shelfOwner,
      {Size size = const Size(390, 844), double scale = 1}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: GiftMemoList(
            gift: _gift,
            memos: _memos,
            myUid: 'me',
            shelfOwnerUid: shelfOwner,
            counterpartName: 'Саша',
            scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B)),
            ru: true,
            strings: LocaleService.current,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('шапка говорит, сколько раз и когда последний', (tester) async {
    await pump(tester, 'me');
    expect(find.text('Обнимашка'), findsOneWidget);
    expect(find.textContaining('2 раза · последний'), findsOneWidget);
    expect(find.text('от Саша'), findsOneWidget);
    expect(find.text('из сундука'), findsOneWidget);
    expect(find.textContaining('Кофейня на Пушкина'), findsOneWidget);
    expect(find.text('Без записки'), findsOneWidget);
  });

  testWidgets('на своей полке ответ ваш, на чужой — просто ответ',
      (tester) async {
    await pump(tester, 'me');
    expect(find.text('Ваш ответ'), findsOneWidget);
    await pump(tester, 'partner');
    expect(find.text('Ответ'), findsOneWidget);
  });

  testWidgets('320 dp и шрифт 1.3 без переполнений', (tester) async {
    await pump(tester, 'me', size: const Size(320, 640), scale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
