import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/models/partner_profile.dart';
import 'package:love_app/widgets/gifts/gift_photo_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Снимок к подарку «Кадр» (обращение 20): даритель прикладывает своё фото,
/// как текст прикладывается к «Песне».
void main() {
  test('снимок несёт только «Кадр»', () {
    expect(GiftCatalog.byKey('photo')!.carriesPhoto, isTrue);
    final others = [...GiftCatalog.all, ...GiftCatalog.chest]
        .where((g) => g.key != 'photo' && g.carriesPhoto)
        .map((g) => g.key);
    // Зеркало PHOTO_GIFTS в gifts.pb.js: сервер примет снимок только у них.
    expect(others, isEmpty);
  });

  test('полка читает снимок, и подарок с одним снимком есть что открыть', () {
    final memos = memosOfKey([
      {
        'gift_key': 'photo',
        'created': '2026-09-28 10:00:00.000Z',
        'photo': 'pb://media/abcdefghijklmno/shot.jpg',
      },
    ], 'photo');
    expect(memos.single.photo, 'pb://media/abcdefghijklmno/shot.jpg');
    expect(memos.single.hasText, isTrue);
  });

  test('подарок без снимка остаётся как был', () {
    final memo = memosOfKey([
      {'gift_key': 'photo', 'created': '2026-09-28 10:00:00.000Z'},
    ], 'photo').single;
    expect(memo.photo, isEmpty);
    expect(memo.hasText, isFalse);
  });

  testWidgets('лист снимка помещается на 320 dp при шрифте 1.3',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    String? result = 'не закрыт';
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 700), textScaler: TextScaler.linear(1.3)),
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showGiftPhotoSheet(
                    context,
                    gift: GiftCatalog.byKey('photo')!,
                    scheme: ColorScheme.fromSeed(seedColor: Colors.pink),
                    groupId: 'g1',
                    uid: 'u1',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Пока снимок не загружен, «Отправить» закрыт, а «Без фото» отдаёт
    // пустую строку — подарок уходит как раньше.
    // У тональных кнопок свой тип-наследник, поэтому точный FilledButton в
    // листе один — «Отправить».
    final send = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(send.onPressed, isNull);
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(result, '');
  });
}
