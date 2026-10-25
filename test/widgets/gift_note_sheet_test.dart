// Записка к подарку из сундука (обращение 244, 13.10.2026): «добавьте
// подпись и к подаркам из сундука». Лист один на магазин и сундук.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/gifts/gift_note_sheet.dart';

Future<String?> _open(WidgetTester tester, Future<void> Function() act) async {
  String? result = 'не закрыт';
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => result = await showGiftNoteSheet(
            context,
            cs: Theme.of(context).colorScheme,
            giftKey: 'hw_cocoa',
            title: 'Какао',
          ),
          child: const Text('открыть'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('записка уходит текстом', (tester) async {
    final got = await _open(tester, () async {
      await tester.enterText(find.byType(TextField), 'с любовью');
      await tester.tap(find.byType(FilledButton));
    });
    expect(got, 'с любовью');
  });

  testWidgets('без записки — пустая строка, подарок всё равно уходит', (tester) async {
    final got = await _open(tester, () => tester.tap(find.byType(TextButton).last));
    expect(got, '');
  });

  testWidgets('смахнул лист — подарок не уходит', (tester) async {
    final got = await _open(tester, () => tester.tapAt(const Offset(10, 10)));
    expect(got, isNull);
  });

  test('все места, где сундук отдаёт подарок, спрашивают записку и передают её', () {
    for (final path in [
      'lib/screens/chest_screen.dart',
      'lib/widgets/chest/chest_stash_lane.dart',
      'lib/widgets/chest/chest_stash_sheet.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('showGiftNoteSheet('), isTrue, reason: path);
      expect(RegExp(r'ChestService\.instance\.give\([^)]*note:').hasMatch(src), isTrue, reason: path);
    }
  });
}
