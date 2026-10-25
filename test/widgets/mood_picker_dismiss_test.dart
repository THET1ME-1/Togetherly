import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/home/widgets/mood_picker_dialog.dart';
import 'package:love_app/services/locale_service.dart';

/// TOG-39, обращение 471: «трудно всплывающие окна закрыть бывает».
///
/// Лист выбора настроения растягивался невидимой частью на всю высоту
/// экрана (`DraggableScrollableSheet` с `expand: true`). Затемнение над ним
/// выглядело как обычно, но касание попадало в прозрачный лист, а не в
/// затемнение, и ничего не закрывало. Оставалось тянуть лист вниз, а об этом
/// догадывались не все.
void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  testWidgets('касание по затемнению над выбором самочувствия закрывает лист',
      (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.viewPadding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return Center(
        child: TextButton(
          onPressed: () => showAilmentPicker(
            context: context,
            pairData: PairData(),
            primary: Colors.pink,
          ),
          child: const Text('самочувствие'),
        ),
      );
    }))));

    await tester.tap(find.text('самочувствие'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodPickerSheet), findsOneWidget);

    // Лист открывается на 62 % высоты, над ним больше двухсот точек затемнения.
    await tester.tapAt(const Offset(187, 120));
    await tester.pumpAndSettle();
    expect(find.byType(MoodPickerSheet), findsNothing,
        reason: 'касание над листом попало в его прозрачную часть');
  });

  test('лист с перетаскиванием не растягивается на весь экран', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'DraggableScrollableSheet\(').allMatches(source)) {
        var depth = 1;
        var i = match.end;
        while (depth > 0 && i < source.length) {
          final c = source[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        if (!source.substring(match.start, i).contains('expand: false')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'с expand: true прозрачная часть листа перекрывает затемнение, '
            'и касание над листом его не закрывает');
  });
}
