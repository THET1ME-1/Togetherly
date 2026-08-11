import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/settings_scaffold.dart';

/// Заголовок секции в профиле идёт со значком (`_m3Group`), а в настройках его
/// не было вовсе: «ОФОРМЛЕНИЕ», «УВЕДОМЛЕНИЯ» и соседи висели голой строкой, и
/// два экрана рядом выглядели по-разному.
///
/// Значок без подложки и того же кегля, что в профиле; цвет идёт за
/// заголовком, поэтому у секции аккаунта он красный вместе с надписью.
void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    IconData? icon,
    Color? color,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSection('Оформление', icon: icon, color: color),
        ),
      ),
    );
  }

  testWidgets('значок стоит рядом с надписью', (tester) async {
    await pumpSection(tester, icon: Icons.brush_rounded);

    expect(find.text('ОФОРМЛЕНИЕ'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.brush_rounded));
    expect(icon.size, 18, reason: 'тот же кегль, что у секций профиля');
  });

  testWidgets('значок берёт цвет заголовка', (tester) async {
    const danger = Color(0xFFB3261E);
    await pumpSection(tester, icon: Icons.person_rounded, color: danger);

    final icon = tester.widget<Icon>(find.byIcon(Icons.person_rounded));
    expect(icon.color, danger);
  });

  testWidgets('без значка заголовок остаётся прежним', (tester) async {
    await pumpSection(tester);

    expect(find.text('ОФОРМЛЕНИЕ'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });
}
