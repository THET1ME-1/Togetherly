// Новый PIN секретных воспоминаний спрашивается дважды.
//
// Письмо в поддержку 17.08.2026: «неправильно изначально ввёл пароль для
// „Секретное“ во вкладке „Воспоминания“, как мне теперь его изменить?». Так и
// было: четыре набранные цифры сразу становились паролем, подтверждения не
// спрашивали, а сменить или сбросить его в приложении было нечем — воспоминания
// запирались навсегда, причём PIN живёт только на этом устройстве и в облаке его
// нет вовсе.
//
// Здесь проверяется первая половина лечения: при создании ввод идёт дважды и
// расходящиеся наборы не проходят.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/pin_entry_sheet.dart';

void main() {
  Future<void> type(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.widgetWithText(InkWell, d).first);
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<String?> pumpEntry(
    WidgetTester tester, {
    required bool create,
  }) async {
    String? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PinEntry(
              create: create,
              onDone: (pin) => done = pin,
              confirmHint: 'Повторите пароль',
              mismatchError: 'Не совпал, попробуйте снова',
            ),
          ),
        ),
      ),
    );
    return done;
  }

  testWidgets('существующий PIN отдаётся сразу, без повтора', (tester) async {
    String? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PinEntry(
              create: false,
              onDone: (pin) => done = pin,
              confirmHint: 'Повторите пароль',
              mismatchError: 'Не совпал, попробуйте снова',
            ),
          ),
        ),
      ),
    );
    await type(tester, '1234');
    expect(done, '1234');
  });

  testWidgets('новый PIN не принимается с одного ввода', (tester) async {
    String? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PinEntry(
              create: true,
              onDone: (pin) => done = pin,
              confirmHint: 'Повторите пароль',
              mismatchError: 'Не совпал, попробуйте снова',
            ),
          ),
        ),
      ),
    );
    await type(tester, '1111');
    expect(done, isNull, reason: 'после первого ввода пароль ещё не задан');
    expect(find.text('Повторите пароль'), findsOneWidget);
  });

  testWidgets('совпавший повтор задаёт PIN', (tester) async {
    String? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PinEntry(
              create: true,
              onDone: (pin) => done = pin,
              confirmHint: 'Повторите пароль',
              mismatchError: 'Не совпал, попробуйте снова',
            ),
          ),
        ),
      ),
    );
    await type(tester, '1111');
    await type(tester, '1111');
    expect(done, '1111');
  });

  testWidgets('расхождение сбрасывает ввод и показывает ошибку', (tester) async {
    String? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PinEntry(
              create: true,
              onDone: (pin) => done = pin,
              confirmHint: 'Повторите пароль',
              mismatchError: 'Не совпал, попробуйте снова',
            ),
          ),
        ),
      ),
    );
    await type(tester, '1111');
    await type(tester, '2222');
    expect(done, isNull, reason: 'опечатка не должна становиться паролем');
    expect(find.text('Не совпал, попробуйте снова'), findsOneWidget);

    // После ошибки ввод начинается заново, и правильная пара проходит.
    await type(tester, '3333');
    await type(tester, '3333');
    expect(done, '3333');
  });
}
