import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/hint_calm.dart';

/// Подсказка вылезала прямо поверх листа покупки Плюса: очередь подсказок
/// стартует с главной сразу, а лист появляется через пару секунд после входа.
/// Теперь подсказка ждёт, пока закроются все окна поверх главной, и ещё
/// немного спокойствия — и только потом показывается.
void main() {
  group('правило «можно показывать»', () {
    test('открыто окно поверх главной — нельзя', () {
      expect(hintMayShow(openPopups: 1, sinceLastChange: const Duration(minutes: 5), sinceHomeShown: const Duration(minutes: 5)), isFalse);
    });

    test('только что вошли на главную — ждём: лист Плюса может выехать позже', () {
      expect(hintMayShow(openPopups: 0, sinceLastChange: const Duration(seconds: 30), sinceHomeShown: const Duration(seconds: 8)), isFalse);
    });

    test('окно только что закрыли — ждём несколько секунд спокойствия', () {
      expect(hintMayShow(openPopups: 0, sinceLastChange: const Duration(seconds: 2), sinceHomeShown: const Duration(minutes: 1)), isFalse);
    });

    test('окон нет, на главной давно и тихо — показываем', () {
      expect(hintMayShow(openPopups: 0, sinceLastChange: hintQuiet, sinceHomeShown: hintSettle), isTrue);
    });
  });

  group('наблюдатель окон', () {
    testWidgets('лист снизу считается открытым окном, пока его не закрыли', (tester) async {
      final calm = HintCalm.forTest();
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, navigatorObservers: [calm.observer], home: const SizedBox()));
      expect(calm.openPopups, 0);

      showModalBottomSheet<void>(context: key.currentContext!, builder: (_) => const SizedBox(height: 100));
      await tester.pumpAndSettle();
      expect(calm.openPopups, 1);

      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calm.openPopups, 0);
    });

    testWidgets('диалог тоже окно', (tester) async {
      final calm = HintCalm.forTest();
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, navigatorObservers: [calm.observer], home: const SizedBox()));
      showDialog<void>(context: key.currentContext!, builder: (_) => const AlertDialog(content: Text('Плюс')));
      await tester.pumpAndSettle();
      expect(calm.openPopups, 1);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calm.openPopups, 0);
    });
  });
}
