import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/pair_book.dart';
import 'package:love_app/screens/pair_book_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Книга пары и записи 18+ (обращение 256, 11.10.2026). Решение владельца:
/// «пусть переключатель будет, человек сам решит». Книга уходит из
/// приложения файлом, поэтому по умолчанию таких записей в ней нет.
Memory _m(String id, int day, {bool adult = false}) => Memory(
      id: id,
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Аня',
      type: MemoryType.photo,
      createdAt: DateTime(2026, 5, day),
      caption: 'запись $id',
      isAdult: adult,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  Future<void> open(
    WidgetTester tester,
    List<Memory> memories, {
    double width = 400,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: PairBookScreen(
          memories: memories,
          theme: AppThemes.pink,
          coupleTitle: 'Аня и Петя',
          secretUnlocked: false,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('без записей 18+ переключателя нет', (tester) async {
    await open(tester, [_m('a', 1), _m('b', 2)]);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('2 '), findsOneWidget);
  });

  testWidgets('переключатель выключен, и запись 18+ в счёт не идёт',
      (tester) async {
    await open(tester, [_m('a', 1), _m('b', 2), _m('hot', 3, adult: true)]);
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isFalse);
    expect(find.text('Записи 18+ в книге'), findsOneWidget);
    expect(find.textContaining('2 воспоминани'), findsOneWidget);
  });

  testWidgets('включили — запись 18+ попадает в книгу', (tester) async {
    await open(tester, [_m('a', 1), _m('b', 2), _m('hot', 3, adult: true)]);
    // Нажимается вся строка, а не только сам рычажок.
    await tester.tap(find.text('Записи 18+ в книге'));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.textContaining('3 воспоминани'), findsOneWidget);
  });

  testWidgets('в книге одни записи 18+: кнопка сборки ждёт переключателя',
      (tester) async {
    await open(tester, [_m('hot', 3, adult: true)]);
    FilledButton build() => tester.widget<FilledButton>(
        find.widgetWithIcon(FilledButton, Icons.menu_book_rounded));
    expect(build().onPressed, isNull);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(build().onPressed, isNotNull);
  });

  // Владелец 11.10.2026: «конечно пусть сохраняется». Выбор живёт на
  // телефоне и переживает закрытие экрана и перезапуск приложения.
  testWidgets('выбор запоминается: включил один раз, дальше включён',
      (tester) async {
    final memories = [_m('a', 1), _m('hot', 3, adult: true)];
    await open(tester, memories);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPairBookAdultKey), isTrue);

    // Экран закрыли и открыли заново.
    await tester.pumpWidget(const SizedBox());
    await open(tester, memories);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.textContaining('2 воспоминани'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(prefs.getBool(kPairBookAdultKey), isFalse);
  });

  test('выход из аккаунта выбор стирает', () {
    final src = File('lib/models/user_data.dart').readAsStringSync();
    expect(src, contains('prefs.remove(kPairBookAdultKey)'));
  });

  testWidgets('строка переключателя влезает на 320 dp с крупным шрифтом',
      (tester) async {
    await open(tester, [_m('a', 1), _m('hot', 3, adult: true)],
        width: 320, scale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.byType(Switch), findsOneWidget);
  });
}
