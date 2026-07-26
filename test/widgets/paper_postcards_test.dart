import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/postcard/models/postcard_template.dart';
import 'package:love_app/screens/postcard/widgets/postcard_card.dart';

/// Бумажные открытки: билет, чек, телеграмма, посылка.
///
/// Каждая рисуется своими painter'ами (перфорация, оторванный край, кайма
/// авиапочты, штрихкод), и любая ошибка в них всплывает только на экране.
/// Тест прогоняет отрисовку и следит, что данные пары доехали до карточки.
void main() {
  const paper = [
    PostcardTemplateId.ticket,
    PostcardTemplateId.receipt,
    PostcardTemplateId.telegram,
    PostcardTemplateId.parcel,
  ];

  Future<void> pumpCard(WidgetTester tester, PostcardTemplateId id) async {
    final blocks = PostcardTemplate.defaultBlocks(
      templateId: id,
      days: 431,
      myName: 'Саша',
      partnerName: 'Аня',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 360,
            child: PostcardCard(templateId: id, days: 431, blocks: blocks),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final id in paper) {
    testWidgets('${id.name}: рисуется без исключений', (tester) async {
      await pumpCard(tester, id);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Число дней видно на билете, чеке и посылке', (tester) async {
    for (final id in [
      PostcardTemplateId.ticket,
      PostcardTemplateId.receipt,
    ]) {
      await pumpCard(tester, id);
      expect(find.text('431'), findsOneWidget, reason: id.name);
    }
  });

  testWidgets('Имена доезжают до карточки', (tester) async {
    await pumpCard(tester, PostcardTemplateId.ticket);
    expect(find.text('Саша → Аня'), findsOneWidget);

    await pumpCard(tester, PostcardTemplateId.parcel);
    expect(find.text('Аня'), findsOneWidget,
        reason: 'посылка адресуется партнёру');
  });

  test('Новые шаблоны попали в список выбора', () {
    final ids = PostcardTemplate.all.map((t) => t.id).toSet();
    for (final id in paper) {
      expect(ids, contains(id), reason: id.name);
    }
    expect(PostcardTemplate.all.length, 8, reason: 'четыре старых и четыре новых');
  });
}
