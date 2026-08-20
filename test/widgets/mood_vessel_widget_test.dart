import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_vessel.dart';
import 'package:love_app/widgets/mood/mood_vessel.dart';

VesselDay _day(int d, {bool mine = false, bool partner = false,
    bool intimacy = false, bool period = false}) =>
    VesselDay(
      date: DateTime(2026, 8, d),
      mineMood: mine ? const Color(0xFFFF7E8B) : null,
      partnerMood: partner ? const Color(0xFF3B82F6) : null,
      intimacy: intimacy,
      period: period,
    );

Future<void> _pumpVessel(WidgetTester tester, List<VesselDay> days) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: MoodVessel(days: days, columns: 6, height: 300),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('пропущенный день блока не даёт', (tester) async {
    await _pumpVessel(tester, [
      _day(1, mine: true),
      _day(2), // никто не отметился
      _day(3, mine: true, partner: true),
    ]);
    expect(find.byIcon(Icons.mood_rounded), findsNWidgets(3));
  });

  testWidgets('близость даёт свой этаж с сердцем', (tester) async {
    await _pumpVessel(tester, [_day(1, mine: true, intimacy: true)]);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mood_rounded), findsOneWidget);
  });

  testWidgets('месячные не добавляют ни этажа, ни значка', (tester) async {
    await _pumpVessel(tester, [_day(1, mine: true, period: true)]);
    expect(find.byIcon(Icons.mood_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
  });

  testWidgets('пустой месяц не роняет сосуд', (tester) async {
    await _pumpVessel(tester, [_day(1), _day(2)]);
    expect(find.byType(MoodVessel), findsOneWidget);
    expect(find.byIcon(Icons.mood_rounded), findsNothing);
  });

  testWidgets('на узком экране кладка не переполняется', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await _pumpVessel(tester, [
      for (var d = 1; d <= 31; d++) _day(d, mine: true, partner: true, intimacy: d % 5 == 0),
    ]);
    expect(tester.takeException(), isNull);
  });
}
