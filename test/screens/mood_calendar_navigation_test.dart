import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/mood_calendar_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/mood_service.dart';
import 'package:love_app/services/widget_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/mood/month_year_wheel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Просьба владельца 08.11.2026: месяцы листать свайпом, а по нажатию на
/// «Ноябрь 2026» выбирать месяц и год барабаном прямо на календаре.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  const months = ['', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль',
    'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
  String title(DateTime d) => '${months[d.month]} ${d.year}';

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MoodCalendarScreen(
        pairData: PairData(),
        moodService: MoodService(),
        widgetService: WidgetService(),
        theme: AppThemes.pink,
      ),
    ));
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('свайп влево — следующий месяц, вправо — прошлый', (t) async {
    await pump(t);
    final now = DateTime.now();
    expect(find.text(title(now)), findsOneWidget);

    final card = find.byKey(const ValueKey('cal_swipe-false'));
    await t.ensureVisible(card);
    await t.fling(card, const Offset(-300, 0), 1500);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(title(DateTime(now.year, now.month + 1, 1))), findsOneWidget);

    await t.fling(card, const Offset(300, 0), 1500);
    await t.fling(card, const Offset(300, 0), 1500);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(title(DateTime(now.year, now.month - 1, 1))), findsOneWidget);
  });

  testWidgets('«Сегодня» есть только вдали от текущего месяца и возвращает к нему', (t) async {
    await pump(t);
    final now = DateTime.now();
    expect(find.byKey(const ValueKey('cal_today')), findsNothing);

    final card = find.byKey(const ValueKey('cal_swipe-false'));
    await t.ensureVisible(card);
    await t.fling(card, const Offset(300, 0), 1500);
    await t.fling(card, const Offset(300, 0), 1500);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(title(DateTime(now.year, now.month - 2, 1))), findsOneWidget);

    await t.ensureVisible(find.byKey(const ValueKey('cal_today')));
    await t.tap(find.byKey(const ValueKey('cal_today')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(title(now)), findsOneWidget);
    expect(find.byKey(const ValueKey('cal_today')), findsNothing);
  });

  testWidgets('нажатие на месяц открывает барабан на календаре', (t) async {
    await pump(t);
    expect(find.byType(MonthYearWheel), findsNothing);
    await t.tap(find.byKey(const ValueKey('cal_title')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(MonthYearWheel), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('cal_title')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(MonthYearWheel), findsNothing);
  });
}
