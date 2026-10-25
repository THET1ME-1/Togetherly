import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/single_exit.dart';

/// Выход с экрана, который сперва сохраняет себя, идёт один раз (TOG-33).
///
/// Холст на выходе снимает свою картинку, это доли секунды. Стрелка и
/// системное «назад», нажатые подряд, запускали выход дважды, и второй `pop`
/// закрывал экран под холстом, а когда закрывать было нечего, приложение
/// падало «Bad state: No element» (Bugsink 20.10 и 23.10.2026).
void main() {
  Future<NavigatorState> openScreen(
    WidgetTester tester,
    SingleExit exit,
    Future<void> Function() save,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('галерея'))));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => exit.run(context, save),
          child: const Text('назад'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return navigator;
  }

  testWidgets('второе «назад», пока экран сохраняется, не закрывает экран под ним',
      (tester) async {
    final saving = Completer<void>();
    await openScreen(tester, SingleExit(), () => saving.future);

    await tester.tap(find.text('назад'));
    await tester.tap(find.text('назад'));
    saving.complete();
    await tester.pumpAndSettle();

    expect(find.text('галерея'), findsOneWidget);
    expect(find.text('назад'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('поверх экрана что-то открыли — выход его не закрывает и не запирается',
      (tester) async {
    final saving = Completer<void>();
    var saves = 0;
    final exit = SingleExit();
    final navigator = await openScreen(tester, exit, () {
      saves++;
      return saves == 1 ? saving.future : Future<void>.value();
    });

    await tester.tap(find.text('назад'));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('лист поверх')),
    ));
    saving.complete();
    await tester.pumpAndSettle();
    expect(find.text('лист поверх'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('назад'));
    await tester.pumpAndSettle();
    expect(find.text('галерея'), findsOneWidget);
  });

  test('холст выходит только через SingleExit', () {
    final source = File('lib/screens/draw_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _captureThumbnailAndExit()');
    expect(start, isNot(-1));
    final body = source.substring(start, source.indexOf('\n  }\n', start));
    expect(body, contains('_exit.run('));
    expect(body, isNot(contains('Navigator.pop(')));
  });
}
