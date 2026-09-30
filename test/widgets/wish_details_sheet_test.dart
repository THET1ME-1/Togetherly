// Желание партнёра открывается целиком.
//
// Отзыв из Play 02.09.2026: «нельзя открыть желания с партнёром, если они
// большие — их не видно». Нажатие на чужое желание ничего не делало, а в
// списке описание обрезано до одной строки: длинное не прочитать никак.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/widgets/wishes/wish_details_sheet.dart';

final _longNote = List.filled(12, 'только в Питере белыми ночами').join(', ');

Wish _wish({String url = '', int price = 0}) => Wish(
      id: 'w1',
      title: 'Прокатиться на катере по каналам и встретить рассвет у моста',
      note: _longNote,
      authorUid: 'partner',
      price: price,
      currency: '₽',
      shop: 'Нева-тур',
      url: url,
      createdAt: DateTime(2026, 9, 1),
    );

Future<void> _pump(WidgetTester tester, Wish wish) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(360, 780) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: WishDetailsSheet(wish: wish, authorName: 'Аня')),
  ));
}

void main() {
  testWidgets('описание и название видны целиком, без обрезки', (tester) async {
    await _pump(tester, _wish());
    final note = tester.widget<Text>(find.text(_longNote));
    expect(note.maxLines, isNull);
    expect(note.overflow, isNot(TextOverflow.ellipsis));
    final title = tester.widget<Text>(find.textContaining('Прокатиться'));
    expect(title.maxLines, isNull);
    expect(find.textContaining('Аня'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('цена и ссылка показаны, когда они есть', (tester) async {
    await _pump(tester, _wish(url: 'https://example.com/boat', price: 4500));
    expect(find.textContaining('4 500'), findsOneWidget);
    expect(find.byKey(const Key('wish-open-link')), findsOneWidget);
  });

  testWidgets('без ссылки кнопки перехода нет', (tester) async {
    await _pump(tester, _wish());
    expect(find.byKey(const Key('wish-open-link')), findsNothing);
  });

  test('чужое желание в списке открывается, а не молчит', () {
    final src = File('lib/screens/wishes_screen.dart').readAsStringSync();
    expect(src, contains('showWishDetailsSheet('));
    // Прежде ветка «не моё и не сбылось» давала onTap: null.
    expect(src, isNot(contains(': mine\n                                          ? () => _edit(wish)\n                                          : null')));
  });
}
