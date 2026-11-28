import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_date.dart';
import 'package:love_app/screens/dates/date_form_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/dates/next_date_card.dart';
import 'package:love_app/widgets/dates/reminder_sheet.dart';
import 'package:love_app/widgets/dates/repeat_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Наши даты» (TOG-61): форма, листы повтора и напоминаний, карточка.
void main() {
  final theme = buildAppTheme(kPalettes[0], Brightness.light);
  final cs = ProfileTheme.schemeFor(theme);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  Future<void> pumpAt(WidgetTester tester, Widget child, {Size size = const Size(390, 900), double text = 1}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(cs),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
        child: child,
      ),
    ));
    await tester.pump();
  }

  group('экран новой даты', () {
    testWidgets('без названия не сохраняется и просит назвать', (tester) async {
      await pumpAt(tester, DateFormScreen(theme: theme, groupId: 'g', initialDay: DateTime(2026, 11, 8)));
      await tester.tap(find.byKey(const ValueKey('date-form-save')));
      await tester.pump();
      expect(find.text('Назови дату'), findsOneWidget);
      expect(find.byType(DateFormScreen), findsOneWidget);
    });

    testWidgets('у новой даты на весь день — два напоминания в 9:00', (tester) async {
      await pumpAt(tester, DateFormScreen(theme: theme, groupId: 'g', initialDay: DateTime(2026, 11, 8)));
      expect(find.text('В этот день в 9:00'), findsOneWidget);
      expect(find.text('За день в 9:00'), findsOneWidget);
      expect(find.text('Вс, 8 ноября 2026'), findsOneWidget);
    });

    testWidgets('«весь день» выключили — напоминания перевелись по смыслу', (tester) async {
      await pumpAt(tester, DateFormScreen(theme: theme, groupId: 'g', initialDay: DateTime(2026, 11, 8)));
      await tester.tap(find.byKey(const ValueKey('date-form-all-day')));
      await tester.pump();
      expect(find.text('В момент начала'), findsOneWidget);
      expect(find.text('За день'), findsOneWidget);
      expect(find.byKey(const ValueKey('date-form-time')), findsOneWidget);
    });

    testWidgets('правка: удалить есть, повтор подписан', (tester) async {
      final d = PairDate.fromMap({
        'id': 'x',
        'title': 'Первое свидание',
        'day': '2025-11-08',
        'rrule': 'FREQ=YEARLY',
        'reminders': [900],
      });
      await pumpAt(tester, DateFormScreen(theme: theme, groupId: 'g', existing: d));
      expect(find.byKey(const ValueKey('date-form-delete')), findsOneWidget);
      expect(find.text('Каждый год'), findsOneWidget);
      expect(find.text('8 ноября'), findsOneWidget);
    });

    testWidgets('320 точек и крупный шрифт — ничего не вылезает', (tester) async {
      await pumpAt(
        tester,
        DateFormScreen(theme: theme, groupId: 'g', initialDay: DateTime(2026, 11, 26)),
        size: const Size(320, 640),
        text: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('листы', () {
    Widget sheet(Widget child) => Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child));

    testWidgets('свой повтор на 320 точках с крупным шрифтом', (tester) async {
      await pumpAt(
        tester,
        sheet(CustomRepeatSheet(
          theme: theme,
          scheme: cs,
          start: DateTime(2026, 11, 26),
          current: 'FREQ=MONTHLY;BYDAY=-1TH;COUNT=4',
        )),
        size: const Size(320, 900),
        text: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Каждый месяц, последний четверг, 4 раза'), findsOneWidget);
    });

    testWidgets('свой повтор: дни недели меняют описание, последний день не снимается', (tester) async {
      await pumpAt(
        tester,
        sheet(CustomRepeatSheet(theme: theme, scheme: cs, start: DateTime(2026, 11, 8), current: 'FREQ=WEEKLY;BYDAY=SU')),
      );
      await tester.tap(find.byKey(const ValueKey('weekday-3')));
      await tester.pump();
      expect(find.text('Каждую неделю, в ср и вс'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('weekday-3')));
      await tester.tap(find.byKey(const ValueKey('weekday-7')));
      await tester.pump();
      expect(find.text('Каждую неделю, в воскресенье'), findsOneWidget);
    });

    testWidgets('своё напоминание на 320 точках с крупным шрифтом', (tester) async {
      for (final allDay in [true, false]) {
        await pumpAt(
          tester,
          sheet(CustomReminderSheet(theme: theme, scheme: cs, allDay: allDay, nextStart: DateTime(2026, 12, 4, 19))),
          size: const Size(320, 900),
          text: 1.3,
        );
        expect(tester.takeException(), isNull, reason: 'allDay=$allDay');
      }
    });

    testWidgets('своё напоминание у даты со временем — «За 2 часа» и когда придёт', (tester) async {
      await pumpAt(
        tester,
        sheet(CustomReminderSheet(theme: theme, scheme: cs, allDay: false, nextStart: DateTime(2026, 12, 4, 19))),
      );
      expect(find.text('За 2 часа'), findsOneWidget);
      expect(find.text('придёт 4 декабря в 17:00'), findsOneWidget);
    });
  });

  testWidgets('карточка ближайшей даты: «Завтра» вместо числа', (tester) async {
    final d = PairDate.fromMap({'id': 'x', 'title': 'Годовщина', 'day': '2026-11-29', 'rrule': ''});
    await pumpAt(
      tester,
      Scaffold(
        body: NextDateCard(
          occurrence: d.nextFrom(DateTime(2026, 11, 28))!,
          line: '',
          scheme: cs,
          now: DateTime(2026, 11, 28, 12),
          onTap: () {},
        ),
      ),
      size: const Size(320, 600),
      text: 1.3,
    );
    expect(find.text('Завтра'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
