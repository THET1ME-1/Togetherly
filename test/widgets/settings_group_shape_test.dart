import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/settings_scaffold.dart';

/// Каждый пункт настроек — отдельный блок, у крайних скруглены внешние углы.
///
/// Раньше группа была одной карточкой со строками через разделитель. Форму
/// теперь раздаёт [SettingsGroup] по месту строки: первому большой верх,
/// последнему большой низ, средним малый радиус со всех сторон.
void main() {
  Future<void> pump(WidgetTester tester, Widget group) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ListView(children: [group]))),
      );

  List<BorderRadius> radiiOf(WidgetTester tester) => tester
      .widgetList<Material>(find.descendant(
        of: find.byType(SettingsGroup),
        matching: find.byType(Material),
      ))
      .where((m) => m.borderRadius != null)
      .map((m) => m.borderRadius! as BorderRadius)
      .toList();

  SettingsRow row(String title) => SettingsRow(
        icon: Icons.palette_rounded,
        title: title,
        onTap: () {},
      );

  testWidgets('у трёх пунктов внешние углы только сверху и снизу группы',
      (tester) async {
    await pump(tester, SettingsGroup([row('Первый'), row('Второй'), row('Третий')]));

    final radii = radiiOf(tester);
    expect(radii, hasLength(3));

    const outer = Radius.circular(SettingsGroup.outerRadius);
    const inner = Radius.circular(SettingsGroup.innerRadius);

    expect(radii.first.topLeft, outer);
    expect(radii.first.topRight, outer);
    expect(radii.first.bottomLeft, inner);

    expect(radii[1].topLeft, inner);
    expect(radii[1].bottomRight, inner);

    expect(radii.last.topLeft, inner);
    expect(radii.last.bottomLeft, outer);
    expect(radii.last.bottomRight, outer);
  });

  testWidgets('единственный пункт скруглён со всех сторон', (tester) async {
    await pump(tester, SettingsGroup([row('Один')]));

    const outer = Radius.circular(SettingsGroup.outerRadius);
    expect(
      radiiOf(tester).single,
      const BorderRadius.all(outer),
    );
  });

  testWidgets('между блоками есть зазор', (tester) async {
    await pump(tester, SettingsGroup([row('Первый'), row('Второй')]));

    final first = tester.getRect(find.text('Первый'));
    final second = tester.getRect(find.text('Второй'));
    expect(second.top - first.bottom, greaterThan(SettingsGroup.gap));
  });

  testWidgets('забытый разделитель не рисуется и не считается блоком',
      (tester) async {
    await pump(
      tester,
      SettingsGroup([row('Первый'), const SettingsDivider(), row('Второй')]),
    );

    expect(radiiOf(tester), hasLength(2));
    expect(find.byType(Divider), findsNothing);
  });
}
