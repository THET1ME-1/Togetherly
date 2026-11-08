// Отзыв в Google Play на 1.41.0 (realme C30): «если слишком быстро нажать на
// отправку сообщения, оно может отправиться, а текст с линии не убраться».
// Клавиатура держит слово недописанным (composing) и после очистки поля
// присылает своё прежнее состояние: текст возвращается в уже пустое поле.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/clear_sent_text.dart';

void main() {
  Future<TextEditingController> pumpField(WidgetTester t) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: c))));
    await t.tap(find.byType(TextField));
    await t.pump();
    return c;
  }

  testWidgets('клавиатура вернула отправленный текст — поле всё равно пустое', (t) async {
    final c = await pumpField(t);
    await t.enterText(find.byType(TextField), 'привет');
    clearSentText(c, 'привет', () => true);
    // Запоздалое состояние клавиатуры с недописанным словом.
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'привет',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      ),
    );
    await t.pump();
    await t.pump(kSentTextEcho);
    expect(c.text, isEmpty);
  });

  testWidgets('новое, набранное после отправки, не трогаем', (t) async {
    final c = await pumpField(t);
    await t.enterText(find.byType(TextField), 'привет');
    clearSentText(c, 'привет', () => true);
    await t.pump();
    await t.enterText(find.byType(TextField), 'как дела');
    await t.pump(kSentTextEcho);
    expect(c.text, 'как дела');
  });

  testWidgets('экран закрыли — поле больше не трогаем', (t) async {
    final c = await pumpField(t);
    await t.enterText(find.byType(TextField), 'привет');
    var alive = true;
    clearSentText(c, 'привет', () => alive);
    alive = false;
    c.text = 'привет';
    await t.pump(kSentTextEcho);
    expect(c.text, 'привет');
  });
}
