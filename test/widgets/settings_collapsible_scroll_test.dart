import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/ui_prefs.dart';
import 'package:love_app/widgets/settings_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Обращение 464 (24.10.2026, видео с Android): «когда у меня открыто только
/// „О приложении“, происходит вот это» — экран настроек сам дёргается вверх
/// и вниз по нескольку раз в секунду.
///
/// Список ленивый: ушедшая за край секция выгружается и при возврате
/// рождается заново. Свёрнутая человеком секция при этом сначала стояла
/// раскрытой, пока не прочитаются настройки, а потом схлопывалась: высота
/// списка скакала, и это выгружало и рождало соседей.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const open = 10;
  const sections = 12;
  const frame = Duration(milliseconds: 16);

  Widget screen() => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var s = 0; s < sections; s++)
                SettingsCollapsible(
                  prefsKey: 'case464_$s',
                  title: 'Секция $s',
                  children: [
                    for (var r = 0; r < (s == open ? 6 : 12); r++)
                      SizedBox(height: 72, child: Text('Строка $s.$r')),
                  ],
                ),
            ],
          ),
        ),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      UiPrefs.kCollapsedSections: [
        for (var s = 0; s < sections; s++)
          if (s != open) 'settings:case464_$s',
      ],
    });
  });

  /// Экран размером с телефон, все секции, кроме одной, свёрнуты, список
  /// долистан до низа, где эта секция и стоит.
  Future<ScrollPosition> openAtBottom(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    list.jumpTo(list.maxScrollExtent);
    return list;
  }

  testWidgets('Внизу списка экран не дёргается сам', (tester) async {
    final list = await openAtBottom(tester);
    final seen = <double>{};
    for (var i = 0; i < 90; i++) {
      await tester.pump(frame);
      if (i >= 45) seen.add(list.pixels);
    }
    expect(seen, hasLength(1), reason: 'положение по кадрам: $seen');
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'экран перерисовывается без конца',
    );
  });

  testWidgets('Вернувшаяся на экран свёрнутая секция не раскрывается', (
    tester,
  ) async {
    final list = await openAtBottom(tester);
    for (var i = 0; i < 45; i++) {
      await tester.pump(frame);
    }
    list.jumpTo(0);
    for (var i = 0; i < 20; i++) {
      await tester.pump(frame);
      expect(
        find.text('Строка 0.0', skipOffstage: false),
        findsNothing,
        reason: 'кадр $i: свёрнутая секция показала содержимое',
      );
    }
  });
}
