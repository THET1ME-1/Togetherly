import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/single_exit.dart';

/// Выход с экрана, который на прощание сохраняет себя.
///
/// TOG-33: стрелка и системное «назад», нажатые подряд, запускали выход
/// дважды, и второй `pop` закрывал экран под холстом, а когда закрывать было
/// нечего, приложение падало «Bad state: No element» (Bugsink 20.10 и
/// 23.10.2026).
///
/// TOG-39, обращение 471 (iPhone SE, 24.10.2026): «в рисовании не жмётся
/// назад». Выход ждал, пока снимется картинка холста, разберётся список всех
/// холстов с их картинками и запишется в настройки. У кого холстов десятки,
/// это доли секунды и больше, а экран всё это время стоит как ни в чём не
/// бывало. Теперь экран закрывается сразу, картинка дописывается после.
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

  testWidgets('«назад» закрывает экран сразу, пока картинка ещё сохраняется',
      (tester) async {
    final saving = Completer<void>();
    await openScreen(tester, SingleExit(), () => saving.future);

    await tester.tap(find.text('назад'));
    await tester.pumpAndSettle();

    expect(find.text('назад'), findsNothing, reason: 'экран ждал сохранения');
    expect(find.text('галерея'), findsOneWidget);
    saving.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('картинку начинают снимать, пока экран ещё на месте', (tester) async {
    bool? currentAtSave;
    late BuildContext screen;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('галерея'))));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final exit = SingleExit();
    navigator.push(MaterialPageRoute<void>(
      builder: (context) {
        screen = context;
        return Scaffold(
          body: TextButton(
            onPressed: () => exit.run(context, () async {
              // Снимок берёт кадр с экрана, поэтому начаться он обязан до ухода.
              currentAtSave = ModalRoute.of(screen)?.isCurrent;
              await Future<void>.delayed(const Duration(seconds: 1));
            }),
            child: const Text('назад'),
          ),
        );
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('назад'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(currentAtSave, isTrue);
    expect(find.text('галерея'), findsOneWidget);
  });

  testWidgets('второе «назад» не закрывает экран под ним', (tester) async {
    final saving = Completer<void>();
    var saves = 0;
    await openScreen(tester, SingleExit(), () {
      saves++;
      return saving.future;
    });

    await tester.tap(find.text('назад'));
    // Уходящий экран Flutter может уже не пускать касания, второе нажатие
    // тогда пролетает мимо, и это тоже верный исход.
    await tester.tap(find.text('назад'), warnIfMissed: false);
    await tester.pumpAndSettle();
    saving.complete();
    await tester.pumpAndSettle();

    expect(find.text('галерея'), findsOneWidget);
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('картинка не сохранилась — экран всё равно закрыт, ошибка не вылетает',
      (tester) async {
    await openScreen(tester, SingleExit(), () async {
      throw StateError('кадр не снялся');
    });

    await tester.tap(find.text('назад'));
    await tester.pumpAndSettle();

    expect(find.text('галерея'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('экран не сверху — выход ничего не закрывает и не запирается',
      (tester) async {
    var saves = 0;
    final exit = SingleExit();
    final navigator = await openScreen(tester, exit, () async => saves++);
    final screen = tester.element(find.text('назад'));

    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('лист поверх')),
    ));
    await tester.pumpAndSettle();
    exit.run(screen, () async => saves++);
    await tester.pumpAndSettle();
    expect(find.text('лист поверх'), findsOneWidget);
    expect(saves, 0);

    navigator.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('назад'));
    await tester.pumpAndSettle();
    expect(find.text('галерея'), findsOneWidget);
    expect(saves, 1);
  });

  test('холст выходит только через SingleExit', () {
    final source = File('lib/screens/draw_screen.dart').readAsStringSync();
    final start = source.indexOf('void _captureThumbnailAndExit()');
    expect(start, isNot(-1));
    final body = source.substring(start, source.indexOf('\n  }\n', start));
    expect(body, contains('_exit.run('));
    expect(body, isNot(contains('Navigator.pop(')));
    expect(body, isNot(contains('await')),
        reason: 'выход не ждёт сохранения картинки (TOG-39)');
  });
}
