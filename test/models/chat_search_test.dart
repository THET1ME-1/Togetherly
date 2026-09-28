import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_search.dart';
import 'package:love_app/screens/chat/chat_search_screen.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  group('фильтр для сервера', () {
    test('вкладка «Всё» ищет по тексту, одна буква — не ищет', () {
      expect(chatSearchFilter(groupId: 'g', kind: ChatSearchKind.all, query: 'к'), isNull);
      expect(chatSearchFilter(groupId: 'g', kind: ChatSearchKind.all, query: ' кафе '),
          "group_id = 'g' && deleted != true && text ~ 'кафе'");
    });

    test('вкладки по видам не требуют слова', () {
      expect(chatSearchFilter(groupId: 'g', kind: ChatSearchKind.voice), contains("voice_url != ''"));
      expect(chatSearchFilter(groupId: 'g', kind: ChatSearchKind.notes), contains("note_url != ''"));
      expect(chatSearchFilter(groupId: 'g', kind: ChatSearchKind.memories), contains("pin_id != ''"));
      expect(chatSearchFilter(groupId: 'g', kind: ChatSearchKind.links), contains("text ~ 'http'"));
    });

    test('кавычка в запросе не ломает фильтр, курсор по времени', () {
      final f = chatSearchFilter(
          groupId: 'g', kind: ChatSearchKind.all, query: "it's", beforeTs: 123)!;
      expect(f, contains(r"text ~ 'it\'s'"));
      expect(f, endsWith('ts < 123'));
    });
  });

  test('подсветка без учёта регистра, все вхождения', () {
    expect(matchRanges('Кафе и кафе', 'КАФЕ'), [(0, 4), (7, 11)]);
    expect(matchRanges('abc', ''), isEmpty);
  });

  test('первая ссылка из текста', () {
    expect(firstLink('смотри https://a.b/c и http://d'), 'https://a.b/c');
    expect(firstLink('без ссылок'), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('экран поиска на 320 dp, шрифт $scale', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 640), textScaler: TextScaler.linear(scale)),
          child: const ChatSearchScreen(groupId: 'g', myUid: 'me'),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Введите хотя бы две буквы'), findsOneWidget);
      expect(find.text('Всё'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Ссылки'), 80, scrollable: find.byType(Scrollable).at(1));
      expect(find.text('Ссылки'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'к');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Введите хотя бы две буквы'), findsOneWidget);
    });
  }
}
