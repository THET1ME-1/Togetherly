import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/memory_lane_screen.dart';

/// Вкладки внизу полной ленты воспоминаний.
///
/// Bugsink 23.10.2026, версия 1.38.0: «Null check operator used on a null
/// value» в `_openFullLane`. Полную ленту открывает встроенная лента главной, и
/// переход по вкладке закрывал полную ленту через `context` встроенной. Пока
/// полная лента открыта, главная успевает перестроиться без встроенной, её
/// `context` умирает, и нажатие на вкладку падало, ничего не сделав.
void main() {
  testWidgets('вкладка работает, когда открывшая ленту уже снята с экрана',
      (tester) async {
    final opener = GlobalKey<_OpenerState>();
    final shell = GlobalKey<_ShellState>();
    final tabs = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: _Shell(key: shell, opener: opener, onTab: tabs.add),
    ));

    opener.currentState!.open();
    await tester.pumpAndSettle();
    expect(find.text('полная лента'), findsOneWidget);

    // Главная перестроилась без встроенной ленты, пока полная открыта.
    shell.currentState!.hideOpener();
    await tester.pump();

    await tester.tap(find.text('вкладка 2'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tabs, [2]);
    expect(find.text('полная лента'), findsNothing);
  });

  test('без перехода по вкладкам и вкладок нет', () {
    expect(fullLaneNavTab(_FakeContext(), null), isNull);
  });

  test('полную ленту закрывает её собственный маршрут', () {
    final src = File('lib/screens/memory_lane_screen.dart').readAsStringSync();
    final start = src.indexOf('void _openFullLane()');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains('fullLaneNavTab('));
    expect(body, isNot(contains('context.mounted')));
  });
}

class _Shell extends StatefulWidget {
  const _Shell({super.key, required this.opener, required this.onTab});

  final GlobalKey<_OpenerState> opener;
  final void Function(int) onTab;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool _showOpener = true;

  void hideOpener() => setState(() => _showOpener = false);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _showOpener
            ? _Opener(key: widget.opener, onTab: widget.onTab)
            : const SizedBox.shrink(),
      );
}

class _Opener extends StatefulWidget {
  const _Opener({super.key, required this.onTab});

  final void Function(int) onTab;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  void open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) {
          final onNavTab = fullLaneNavTab(routeContext, widget.onTab)!;
          return Scaffold(
            body: Column(children: [
              const Text('полная лента'),
              TextButton(
                onPressed: () => onNavTab(2),
                child: const Text('вкладка 2'),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Text('встроенная лента');
}

class _FakeContext extends Fake implements BuildContext {}
