// Клавиатура не должна закрывать поле, в котором человек пишет.
//
// Отзыв из Play 02.09.2026: «когда пишешь комментарии к воспоминаниям,
// клавиатура закрывает поле для письма, не видно, что пишешь». Карточка
// книги, фильма или заметки открывалась нижним листом, а лист Flutter сам над
// клавиатурой не поднимается. У фото и видео экран поднимался, но поле
// прокручивалось к самому низу и пряталось за плавающим тулбаром.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/keyboard_aware.dart';

const _keyboard = 300.0;
const _screen = Size(360, 780);

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _screen * 3;
  addTearDown(tester.view.reset);
}

void _openKeyboard(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard * 3);
}

/// Лист как у карточки воспоминания: длинная прокрутка, поле в самом конце.
Widget _sheetBody({required bool lift}) {
  final sheet = DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.8,
    builder: (_, sc) => SingleChildScrollView(
      controller: sc,
      child: Column(
        children: [
          const SizedBox(height: 900),
          const TextField(key: Key('comment')),
          Builder(
            builder: (context) => SizedBox(
              height: MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
          ),
        ],
      ),
    ),
  );
  return lift ? LiftAboveKeyboard(child: sheet) : sheet;
}

Future<void> _showSheet(WidgetTester tester, {required bool lift}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _sheetBody(lift: lift),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _typeInComment(WidgetTester tester) async {
  await tester.showKeyboard(find.byKey(const Key('comment')));
  _openKeyboard(tester);
  await tester.pumpAndSettle();
}

double _fieldBottom(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('comment'))).bottom;

void main() {
  testWidgets('без подъёма поле в листе уходит под клавиатуру', (tester) async {
    // Сам механизм бага: если этот тест покраснеет, Flutter начал поднимать
    // листы сам, и обёртку можно убирать.
    _phone(tester);
    await _showSheet(tester, lift: false);
    await _typeInComment(tester);
    expect(_fieldBottom(tester), greaterThan(_screen.height - _keyboard));
  });

  testWidgets('лист с подъёмом держит поле над клавиатурой', (tester) async {
    _phone(tester);
    await _showSheet(tester, lift: true);
    await _typeInComment(tester);
    expect(_fieldBottom(tester),
        lessThanOrEqualTo(_screen.height - _keyboard));
  });

  testWidgets('подъём не удваивает отступ под клавиатуру внутри листа',
      (tester) async {
    _phone(tester);
    double? inner;
    await tester.pumpWidget(MaterialApp(
      home: LiftAboveKeyboard(
        child: Builder(builder: (context) {
          inner = MediaQuery.viewInsetsOf(context).bottom;
          return const SizedBox.expand();
        }),
      ),
    ));
    _openKeyboard(tester);
    await tester.pump();
    expect(inner, 0);
  });

  // Экран как у открытого фото: прокрутка и плавающий тулбар снизу.
  const dock = Key('dock');
  Widget momentScreen({required bool hideDock, void Function(bool)? inBody}) =>
      MaterialApp(
        home: Builder(
          builder: (outer) => Scaffold(
            body: Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 900),
                      const TextField(key: Key('comment')),
                      Builder(builder: (inner) {
                        inBody?.call(keyboardOpen(inner));
                        return const SizedBox(height: 150);
                      }),
                    ],
                  ),
                ),
                if (!(hideDock && keyboardOpen(outer)))
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(key: dock, height: 88),
                  ),
              ],
            ),
          ),
        ),
      );

  testWidgets('тулбар поверх прокрутки закрывает поле при наборе',
      (tester) async {
    // Механизм бага у фото и видео: поле уезжает к низу экрана, под тулбар.
    _phone(tester);
    await tester.pumpWidget(momentScreen(hideDock: false));
    await _typeInComment(tester);
    expect(_fieldBottom(tester),
        greaterThan(tester.getRect(find.byKey(dock)).top));
  });

  testWidgets('тулбар уходит на время набора и возвращается после',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(momentScreen(hideDock: true));
    expect(find.byKey(dock), findsOneWidget);

    await _typeInComment(tester);
    expect(find.byKey(dock), findsNothing);
    expect(_fieldBottom(tester),
        lessThanOrEqualTo(_screen.height - _keyboard));

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byKey(dock), findsOneWidget);
  });

  testWidgets('внутри Scaffold клавиатуры не видно — спрашивать снаружи',
      (tester) async {
    _phone(tester);
    bool? seenInBody;
    await tester.pumpWidget(
        momentScreen(hideDock: true, inBody: (v) => seenInBody = v));
    await _typeInComment(tester);
    expect(find.byKey(dock), findsNothing);
    expect(seenInBody, isFalse);
  });
}
