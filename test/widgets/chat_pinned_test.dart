// Закреплённые сообщения: полоска над лентой и экран со всеми. Узкий экран,
// крупный шрифт, обе темы — без переполнений; нажатия доходят куда надо.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/screens/chat/chat_pinned_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/chat/pinned_bar.dart';

ChatMsg pinned(String id, String uid, String text, int day) => ChatMsg(
      id: id,
      uid: uid,
      name: uid == 'me' ? 'Я' : 'Маша',
      text: text,
      ts: DateTime(2026, 11, day, 21, 14).millisecondsSinceEpoch,
      pinnedAt: DateTime(2026, 11, day, 21, 20).millisecondsSinceEpoch,
      pinnedBy: uid,
    );

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  Future<void> pump(WidgetTester t, Widget child, {required Brightness brightness}) async {
    t.view.physicalSize = const Size(320 * 3, 700 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B), brightness: brightness)),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 700), textScaler: TextScaler.linear(1.3)),
        child: child,
      ),
    ));
    await t.pump();
  }

  for (final b in Brightness.values) {
    testWidgets('полоска: номер, текст и два нажатия (${b.name})', (t) async {
      var jumps = 0, lists = 0;
      await pump(
        t,
        Scaffold(
          body: Column(children: [
            PinnedBar(
              index: 1,
              count: 4,
              preview: 'Код домофона 4821, квартира 37, этаж 5, а дальше очень длинный текст',
              onTap: () => jumps++,
              onOpenAll: () => lists++,
            ),
          ]),
        ),
        brightness: b,
      );
      expect(find.text('Закреплённое · 2 из 4'), findsOneWidget);
      await t.tap(find.textContaining('Код домофона'));
      await t.tap(find.byTooltip('Все закреплённые'));
      expect((jumps, lists), (1, 1));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('полоска с одним закреплённым — без номера', (t) async {
    await pump(
      t,
      Scaffold(body: Column(children: [PinnedBar(index: 0, count: 1, preview: 'Билеты', onTap: () {}, onOpenAll: () {})])),
      brightness: Brightness.light,
    );
    expect(find.text('Закреплённое сообщение'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('экран: заголовок, переход, открепить одно и все (${b.name})', (t) async {
      final list = [
        pinned('a', 'her', 'Wi-Fi у мамы: Kotiki_5G, пароль 77mur77mur', 2),
        pinned('b', 'me', 'Годовщина 23 января. Столик в «Ласточке» на 19:00', 4),
        pinned('c', 'her', 'Код домофона 4821, квартира 37, этаж 5', 5),
      ];
      final unpinned = <String>[];
      ChatMsg? opened;
      await pump(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  opened = await Navigator.of(context).push<ChatMsg>(MaterialPageRoute(
                    builder: (_) => ChatPinnedScreen(
                      pinned: list,
                      myUid: 'me',
                      partnerName: 'Маша',
                      quoteOf: (m) => m.text,
                      onUnpin: (m) async => unpinned.add(m.id),
                    ),
                  ));
                },
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
        brightness: b,
      );
      await t.tap(find.text('открыть'));
      await t.pumpAndSettle();
      expect(find.text('3 закреплённых'), findsOneWidget);
      expect(t.takeException(), isNull);

      // Долгое нажатие открепляет одно, заголовок пересчитывается.
      await t.longPress(find.textContaining('Wi-Fi у мамы'));
      await t.pumpAndSettle();
      expect(unpinned, ['a']);
      expect(find.text('2 закреплённых'), findsOneWidget);

      // «Открепить все» спрашивает и открепляет оставшиеся.
      await t.tap(find.text('Открепить все'));
      await t.pumpAndSettle();
      await t.tap(find.text('Открепить все').last);
      await t.pumpAndSettle();
      expect(unpinned.toSet(), {'a', 'b', 'c'});
      expect(opened, isNull);
    });
  }

  testWidgets('экран: касание по сообщению возвращает его чату', (t) async {
    ChatMsg? opened;
    await pump(
      t,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              opened = await Navigator.of(context).push<ChatMsg>(MaterialPageRoute(
                builder: (_) => ChatPinnedScreen(
                  pinned: [pinned('c', 'her', 'Код домофона 4821', 5)],
                  myUid: 'me',
                  partnerName: 'Маша',
                  quoteOf: (m) => m.text,
                  onUnpin: (_) async {},
                ),
              ));
            },
            child: const Text('открыть'),
          ),
        ),
      ),
      brightness: Brightness.light,
    );
    await t.tap(find.text('открыть'));
    await t.pumpAndSettle();
    expect(find.text('1 закреплённое'), findsOneWidget);
    await t.tap(find.byTooltip('Показать в чате'));
    await t.pumpAndSettle();
    expect(opened?.id, 'c');
  });
}
