import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/date_time_picker_screen.dart';
import 'package:love_app/theme/app_theme.dart';

/// Воспоминание — про прошлое. Барабаны ограничивали только год, и будущий
/// день текущего года выбирался свободно: такая запись висела над всей лентой
/// до своей даты (14.10.2026). Сервер теперь будущее у воспоминаний не
/// принимает, поэтому и экран не даёт его выбрать, иначе выбранный день молча
/// менялся бы на сегодняшний.
void main() {
  Future<DateTime?> pick(WidgetTester tester,
      {required DateTime initial, DateTime? latest}) async {
    DateTime? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<DateTime>(
              MaterialPageRoute(
                builder: (_) => DateTimePickerScreen(
                  title: 'Дата',
                  theme: AppThemes.pink,
                  initial: initial,
                  firstYear: 2000,
                  lastYear: 2026,
                  latest: latest,
                ),
              ),
            );
          },
          child: const Text('открыть'),
        ),
      ),
    ));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('день позже предела прижимается к пределу', (tester) async {
    final latest = DateTime(2026, 10, 14, 16, 30);
    final got = await pick(tester,
        initial: DateTime(2026, 10, 20, 18, 0), latest: latest);
    expect(got, latest);
  });

  testWidgets('прошлое проходит как выбрано', (tester) async {
    final got = await pick(tester,
        initial: DateTime(2026, 9, 1, 12, 15),
        latest: DateTime(2026, 10, 14, 16, 30));
    expect(got, DateTime(2026, 9, 1, 12, 15));
  });

  testWidgets('без предела будущее остаётся (таймер, капсула)', (tester) async {
    final got = await pick(tester, initial: DateTime(2026, 12, 31, 23, 0));
    expect(got, DateTime(2026, 12, 31, 23, 0));
  });
}
