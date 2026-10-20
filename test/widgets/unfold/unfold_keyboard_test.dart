import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';

// Обращение 367: чат открыт из круглой кнопки внизу, человек печатает, жмёт
// «назад». Экран под чатом при клавиатуре ужат, его кнопка стоит выше своего
// места, и окно складывалось туда, в середину экрана, а снимок кнопки ещё
// висел там, когда настоящая уже вернулась вниз.

const _screen = Size(360, 760);
const _window = ValueKey<String>('unfold-window');
const _keyboard = 300.0;

class _Chat extends StatelessWidget {
  const _Chat();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 80),
          const TextField(autofocus: true),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('назад'),
          ),
        ],
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: UnfoldSource(
                fill: Colors.blue,
                radius: 20,
                builder: (context, source) => GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    UnfoldRoute<void>(source: source, builder: (_) => const _Chat()),
                  ),
                  child: const SizedBox(
                    key: ValueKey('chat-button'),
                    width: 40,
                    height: 40,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('с открытой клавиатурой чат складывается в кнопку, а не над ней',
      (tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _Home()));
    final button = tester.getRect(find.byKey(const ValueKey('chat-button')));

    await tester.tap(find.byKey(const ValueKey('chat-button')));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.hasAnyClients, isTrue, reason: 'поле в чате не в фокусе');

    // Клавиатура выехала: экран под чатом ужался, кнопка поднялась.
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await tester.pumpAndSettle();

    await tester.tap(find.text('назад'));
    await tester.pump();
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isFalse,
        reason: 'клавиатуру прячем сразу, как экран начал складываться');
    // Система убирает клавиатуру сама, пока окно складывается.
    tester.view.viewInsets = FakeViewPadding.zero;

    Rect? last;
    for (var frames = 0; frames < 80 && find.byKey(_window).evaluate().isNotEmpty; frames++) {
      last = tester.getRect(find.byKey(_window));
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(last, isNotNull);
    expect((last!.center - button.center).distance, lessThan(6),
        reason: 'окно сложилось в $last, а кнопка в $button');
  });
}
