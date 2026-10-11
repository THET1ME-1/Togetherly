import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/tab_fade.dart';

const _old = ValueKey<String>('tab-fade-old');

final _homeKey = GlobalKey();

/// Вкладка со своим состоянием: по нему видно, не пересоздали ли её зря.
class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.label});

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => taps++),
        child: ColoredBox(
          color: Colors.white,
          child: Center(child: Text('${widget.label} $taps')),
        ),
      );
}

Widget _tab(int index) => switch (index) {
      0 => _Counter(key: _homeKey, label: 'главная'),
      1 => const Center(child: Text('виджеты')),
      _ => const Center(child: Text('профиль')),
    };

Future<void> _pump(WidgetTester tester, int index) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TabFade(index: index, child: _tab(index))),
      ),
    );

double _opacityOf(WidgetTester tester, Finder of) => tester
    .widget<Opacity>(
        find.ancestor(of: of, matching: find.byType(Opacity)).first)
    .opacity;

double _scaleOf(WidgetTester tester, Finder of) => tester
    .widget<Transform>(
        find.ancestor(of: of, matching: find.byType(Transform)).first)
    .transform
    .storage[0];

void main() {
  test('числа проявления: старая гаснет за 90 мс, новая с 90-й по 300-ю', () {
    expect(TabFade.oldOpacity(0), 1);
    expect(TabFade.oldOpacity(45), closeTo(0.5, 1e-9));
    expect(TabFade.oldOpacity(90), 0);
    expect(TabFade.newOpacity(90), 0);
    expect(TabFade.newOpacity(195), closeTo(0.5, 1e-9));
    expect(TabFade.newOpacity(300), 1);
    expect(TabFade.newScale(90), closeTo(0.96, 1e-9));
    expect(TabFade.newScale(300), closeTo(1, 1e-9));
    expect(TabFade.newScale(150), inExclusiveRange(0.96, 1.0));
  });

  testWidgets('в покое вкладка стоит как есть', (tester) async {
    await _pump(tester, 0);

    expect(find.text('главная 0'), findsOneWidget);
    expect(_opacityOf(tester, find.text('главная 0')), 1);
    expect(_scaleOf(tester, find.text('главная 0')), 1);
    expect(find.byKey(_old), findsNothing);
  });

  testWidgets('старая вкладка уходит снимком, новая проявляется следом',
      (tester) async {
    await _pump(tester, 0);
    await _pump(tester, 1);

    expect(find.text('главная 0'), findsNothing,
        reason: 'живой экземпляр вкладки всегда один: прежнюю держит снимок');
    expect(find.byKey(_old), findsOneWidget);
    expect(tester.widget<Opacity>(find.byKey(_old)).opacity, 1);
    expect(_opacityOf(tester, find.text('виджеты')), 0);

    await tester.pump(const Duration(milliseconds: 45));
    expect(tester.widget<Opacity>(find.byKey(_old)).opacity,
        closeTo(0.5, 0.01));
    expect(_opacityOf(tester, find.text('виджеты')), 0);

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(_old), findsNothing);
    expect(_opacityOf(tester, find.text('виджеты')), closeTo(0.5, 0.01));
    expect(_scaleOf(tester, find.text('виджеты')), inExclusiveRange(0.96, 1.0));

    await tester.pumpAndSettle();
    expect(_opacityOf(tester, find.text('виджеты')), 1);
    expect(_scaleOf(tester, find.text('виджеты')), 1);
  });

  testWidgets('перерисовка той же вкладки её не трогает', (tester) async {
    await _pump(tester, 0);
    await tester.tap(find.text('главная 0'));
    await tester.pump();
    expect(find.text('главная 1'), findsOneWidget);

    await _pump(tester, 0);
    expect(find.text('главная 1'), findsOneWidget,
        reason: 'состояние вкладки пережило пересборку родителя');
    expect(find.byKey(_old), findsNothing);
  });

  testWidgets('туда и обратно быстрее проявления — без двух экземпляров',
      (tester) async {
    await _pump(tester, 0);
    await _pump(tester, 1);
    await tester.pump(const Duration(milliseconds: 30));
    // У вкладки общий GlobalKey: два её экземпляра разом уронили бы экран.
    await _pump(tester, 0);
    await tester.pump(const Duration(milliseconds: 30));
    await _pump(tester, 2);

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('профиль'), findsOneWidget);
    expect(_opacityOf(tester, find.text('профиль')), 1);
  });

  testWidgets('при «уменьшить движение» вкладка меняется сразу',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, 0);
    await _pump(tester, 1);

    expect(find.byKey(_old), findsNothing);
    expect(_opacityOf(tester, find.text('виджеты')), 1);
    expect(_scaleOf(tester, find.text('виджеты')), 1);
  });
}
