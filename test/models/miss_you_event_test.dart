import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/miss_you_event.dart';
import 'package:love_app/screens/miss_you_screen.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// История «Скучаю» за день (макет «Скучаю: история дня», вариант А). Раньше
// экран помнил только последний импульс партнёра, каждый новый затирал
// прежний: утреннее «Хочу обнять» к вечеру пропадало.
void main() {
  final now = DateTime(2026, 9, 28, 22, 0);
  MissYouEvent ev(String id, String uid, String vibe, DateTime at, {String? reply, int count = 1, String text = ''}) =>
      MissYouEvent(id: id, uid: uid, vibe: vibe, at: at, replyTo: reply, count: count, text: text);

  test('разбор ответа сервера, новые первыми, битое пропускается', () {
    final list = MissYouEvent.parseList([
      {'id': 'a', 'uid': 'u', 'vibe': 'want_hug', 'count': 3, 'at': 1000},
      {'id': 'b', 'uid': 'u', 'vibe': 'miss_you', 'replyTo': 'x', 'at': 5000},
      {'id': '', 'uid': 'u', 'at': 1},
      'мусор',
    ]);
    expect(list.map((e) => e.id), ['b', 'a']);
    expect(list.last.count, 3);
    expect(list.first.replyTo, 'x');
  });

  test('сегодня по часам телефона, а если тихо — вчера', () {
    final all = [
      ev('y', 'p', 'miss_you', DateTime(2026, 9, 27, 23, 50)),
      ev('t', 'p', 'want_hug', DateTime(2026, 9, 28, 9, 2)),
    ];
    final d = missYouDay(all, now);
    expect(d.events.map((e) => e.id), ['t']);
    expect(d.yesterday, isFalse);
    final quiet = missYouDay([all.first], now);
    expect(quiet.events.map((e) => e.id), ['y']);
    expect(quiet.yesterday, isTrue);
    expect(missYouDay(const [], now).events, isEmpty);
  });

  test('отвеченные — те, на которые ссылаются мои ответы', () {
    final all = [
      ev('p1', 'p', 'want_hug', now),
      ev('m1', 'me', 'want_hug', now, reply: 'p1'),
      ev('p2', 'p', 'miss_you', now),
    ];
    expect(missYouReplied(all, 'me'), {'p1'});
  });

  test('на своё пожелание партнёра отвечают «скучаю», остальное — тем же', () {
    expect(missYouReplyVibe('want_hug'), 'want_hug');
    expect(missYouReplyVibe('thinking_of_you'), 'thinking_of_you');
    expect(missYouReplyVibe('custom'), 'miss_you');
    expect(missYouReplyVibe('miss_you'), 'miss_you');
  });

  testWidgets('экран рисует день блоками и кнопку ответа только у партнёра', (t) async {
    SharedPreferences.setMockInitialValues({});
    final today = DateTime.now();
    DateTime at(int h, int m) => DateTime(today.year, today.month, today.day, h, m);
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 1400)),
      child: MaterialApp(
        home: MissYouScreen(
          theme: AppThemes.byIndex(7),
          groupId: '',
          myUid: 'me',
          partnerUid: '',
          partnerName: 'Аня',
          debugEvents: [
            ev('p3', 'p', 'miss_you', at(0, 30)),
            ev('m1', 'me', 'thinking_of_you', at(0, 20)),
            ev('p2', 'p', 'thinking_of_you', at(0, 10), reply: 'm1'),
            ev('p1', 'p', 'want_hug', at(0, 5), count: 4),
          ],
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('×4'), findsOneWidget);
    // Кнопка ответа у трёх импульсов партнёра, у моего — нет.
    expect(find.byIcon(Icons.reply_rounded), findsNWidgets(3));
    await t.tap(find.byIcon(Icons.reply_rounded).first);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
