// Рисунок уезжает в чат обычным сообщением с пином, а чат показывает его
// крупной карточкой, а не крошечным значком пина.
//
// Просьба из Play 06.09.2026: «было бы удобно, чтобы в чате самого
// приложения можно было отправлять эти рисунки».
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/chat_drawing.dart';
import 'package:love_app/widgets/chat/chat_drawing_card.dart';

void main() {
  test('пин рисунка узнаётся по приставке, пин воспоминания — нет', () {
    final id = chatDrawingPinId('abc123');
    expect(isChatDrawing(id), isTrue);
    expect(isChatDrawing('xYz0memoryId'), isFalse);
    expect(isChatDrawing(null), isFalse);
  });

  test('подпись-заглушка рисунка не выводится текстом в пузыре', () {
    expect(showsChatText(pinId: chatDrawingPinId('a'), text: kChatDrawingText),
        isFalse);
    expect(showsChatText(pinId: chatDrawingPinId('a'), text: 'Смотри!'),
        isTrue);
    expect(showsChatText(pinId: null, text: kChatDrawingText), isTrue);
  });

  testWidgets('карточка крупная, с названием, и открывается по нажатию',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ChatDrawingCard(
            imageUrl: '',
            title: 'Наш кот',
            foreground: Colors.black,
            onTap: () => opened++,
          ),
        ),
      ),
    ));
    expect(find.text('Наш кот'), findsOneWidget);
    final size = tester.getSize(find.byType(ChatDrawingCard));
    expect(size.width, greaterThanOrEqualTo(180));
    await tester.tap(find.byType(ChatDrawingCard));
    expect(opened, 1);
  });

  test('строки есть на всех семи языках', () {
    for (final key in ['drawSendToChat', 'drawSentToChat', 'drawSendToChatFailed', 'chatDrawingTitle']) {
      for (final lang in ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de']) {
        expect(kStrings[key]?[lang], isNotNull, reason: '$key/$lang');
      }
    }
  });

  test('холст отправляет в чат, чат рисует карточку', () {
    final draw = File('lib/screens/draw_screen.dart').readAsStringSync();
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(draw, contains('sendDrawing('));
    expect(draw, contains("'send-to-chat'"));
    expect(chat, contains('ChatDrawingCard('));
    expect(chat, contains('isChatDrawing(msg.pinId)'));
  });
}
