import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/utils/calendar_swipe.dart';
import 'package:love_app/widgets/mood/month_year_wheel.dart';

/// Просьба владельца 08.11.2026: месяцы в календаре настроений листать
/// свайпом влево-вправо, а не только стрелками, и по нажатию на «Ноябрь 2026»
/// выбирать месяц и год барабаном прямо на календаре.
void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  group('свайп', () {
    test('влево — следующий период, вправо — прошлый', () {
      expect(calendarSwipeShift(-800), 1);
      expect(calendarSwipeShift(800), -1);
    });

    test('медленное движение пальца — не свайп', () {
      expect(calendarSwipeShift(-120), 0);
      expect(calendarSwipeShift(0), 0);
    });
  });

  Future<void> pump(WidgetTester t, Widget child) async {
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5E34))),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
    ));
    await t.pump();
  }

  testWidgets('барабан показывает выбранный месяц и год', (t) async {
    await pump(t, MonthYearWheel(
      year: 2026,
      month: 11,
      firstYear: 2024,
      lastYear: 2026,
      onChanged: (_, _) {},
    ));
    expect(find.text('Ноябрь'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
  });

  testWidgets('прокрутили месяц — календарь получает новый', (t) async {
    final got = <(int, int)>[];
    await pump(t, MonthYearWheel(
      year: 2026,
      month: 11,
      firstYear: 2024,
      lastYear: 2026,
      onChanged: (y, m) => got.add((y, m)),
    ));
    await t.drag(find.byKey(const ValueKey('month_wheel')), const Offset(0, 120));
    await t.pumpAndSettle();
    expect(got, isNotEmpty);
    expect(got.last.$1, 2026);
    expect(got.last.$2, lessThan(11));
  });

  testWidgets('в режиме года — только год', (t) async {
    await pump(t, MonthYearWheel(
      year: 2025,
      month: 3,
      firstYear: 2024,
      lastYear: 2026,
      yearOnly: true,
      onChanged: (_, _) {},
    ));
    expect(find.byKey(const ValueKey('month_wheel')), findsNothing);
    expect(find.text('2025'), findsOneWidget);
  });
}
