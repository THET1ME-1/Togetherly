import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_reaction.dart';
import 'package:love_app/widgets/chat/reaction_art.dart';

void main() {
  test('у каждой реакции есть неподвижный кадр в сборке', () {
    for (final r in kChatReactions) {
      expect(File('assets/images/reactions/${r.id}.webp').existsSync(), isTrue,
          reason: r.id);
    }
    expect(kChatReactions.map((r) => r.id).toSet().length, kChatReactions.length);
  });

  test('эмодзи узнаётся и без вариационного селектора', () {
    expect(chatReactionOf('❤')?.id, 'heart');
    expect(chatReactionOf('❤️')?.id, 'heart');
    expect(chatReactionOf('🦄'), isNull);
  });

  test('двойное касание ставит, повтор снимает, чужую свою заменяет', () {
    expect(quickReactionToggle(mine: null, quick: '❤️'), '❤️');
    expect(quickReactionToggle(mine: '❤️', quick: '❤️'), isNull);
    expect(quickReactionToggle(mine: '😂', quick: '❤️'), '❤️');
  });

  testWidgets('незнакомая реакция рисуется эмодзи, знакомая — картинкой',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Row(children: [
        ReactionArt(emoji: '🦄'),
        ReactionArt(emoji: '🔥'),
      ]),
    ));
    expect(find.text('🦄'), findsOneWidget);
    expect(find.text('🔥'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('в сетке все шестнадцать, касание отдаёт эмодзи', (t) async {
    String? got;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: ReactionGrid(onPick: (e) => got = e)),
    ));
    expect(find.byType(ReactionArt), findsNWidgets(kChatReactions.length));
    await t.tap(find.byType(ReactionArt).at(8));
    expect(got, kChatReactions[8].emoji);
  });

  test('двойное касание в чате ставит реакцию, а не открывает выбор', () {
    final src = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(src, contains('onDoubleTap: () => _quickReact(msg)'));
    expect(src, isNot(contains('_showReactionPicker')));
  });
}
