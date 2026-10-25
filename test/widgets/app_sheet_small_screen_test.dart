import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/widgets/app_sheet.dart';

/// TOG-39, обращение 471 (iPhone SE 2022, 375×667, кнопка «домой»):
/// «трудно всплывающие окна закрыть бывает, приходится перезаходить».
///
/// Лист с длинным содержимым дорастал до самого верха экрана, а то и под
/// строку состояния. Затемнения над ним не оставалось, касаться было не по
/// чему, а смахивание вниз по списку только листало список. На айфоне
/// системного «назад» нет, и лист оставалось закрывать перезапуском.
void main() {
  const statusBar = 20.0;

  Future<void> openPhone(WidgetTester tester, {double keyboard = 0}) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: statusBar * 2);
    tester.view.viewPadding = const FakeViewPadding(top: statusBar * 2);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => showModalSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ListView(
                  key: const ValueKey('содержимое'),
                  shrinkWrap: true,
                  children: [for (var i = 0; i < 60; i++) Text('строка $i')],
                ),
              ),
              child: const Text('свой лист'),
            ),
            TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => SheetScaffold(
                  title: 'Лист приложения',
                  child: ListView(
                    key: const ValueKey('содержимое'),
                    shrinkWrap: true,
                    children: [for (var i = 0; i < 60; i++) Text('строка $i')],
                  ),
                ),
              ),
              child: const Text('лист приложения'),
            ),
            TextButton(
              onPressed: () => showModalSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: TextField(autofocus: true),
                ),
              ),
              child: const Text('лист с полем'),
            ),
          ]),
        );
      }))),
    );
  }

  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(BottomSheet)).dy;

  for (final which in ['свой лист', 'лист приложения']) {
    testWidgets('$which: над длинным листом остаётся полоса, и касание по ней его закрывает',
        (tester) async {
      await openPhone(tester);
      await tester.tap(find.text(which));
      await tester.pumpAndSettle();

      expect(sheetTop(tester), greaterThanOrEqualTo(statusBar + kSheetTopGap),
          reason: 'лист дорос до верха, касаться над ним не по чему');

      await tester.tapAt(Offset(187, statusBar + kSheetTopGap / 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('содержимое')), findsNothing,
          reason: 'касание над листом его не закрыло');
    });

    testWidgets('$which: с открытой клавиатурой полоса отдаёт место, но строку состояния лист не закрывает',
        (tester) async {
      await openPhone(tester, keyboard: 260);
      await tester.tap(find.text(which));
      await tester.pumpAndSettle();

      expect(sheetTop(tester), greaterThanOrEqualTo(statusBar),
          reason: 'лист залез под строку состояния');
      expect(sheetTop(tester), lessThan(statusBar + kSheetTopGap),
          reason: 'пока печатают, место нужнее полосы над листом');
    });
  }

  testWidgets('поле в листе не теряет фокус, когда выезжает клавиатура', (tester) async {
    await openPhone(tester);
    await tester.tap(find.text('лист с полем'));
    await tester.pumpAndSettle();
    final before = tester.state<EditableTextState>(find.byType(EditableText));
    expect(before.widget.focusNode.hasFocus, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 520);
    await tester.pumpAndSettle();

    final after = tester.state<EditableTextState>(find.byType(EditableText));
    expect(identical(before, after), isTrue,
        reason: 'поле пересоздалось, и клавиатура сразу спрячется');
    expect(after.widget.focusNode.hasFocus, isTrue);
  });

  test('высокий лист открывается только через showModalSheet или showAppSheet', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('widgets/app_sheet.dart')) continue;
      final source = file.readAsStringSync();
      // Тип результата бывает вложенным: showModalBottomSheet<List<String>>(.
      for (final match in RegExp(r'showModalBottomSheet\s*(<[^(]*>)?\s*\(').allMatches(source)) {
        var depth = 1;
        var i = match.end;
        while (depth > 0 && i < source.length) {
          final c = source[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        final call = source.substring(match.start, i);
        if (call.contains('isScrollControlled: true')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'лист с isScrollControlled дорастает до верха экрана и прячется '
            'под строку состояния; открывайте его через showModalSheet');
  });
}
