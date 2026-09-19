// Разделённая кнопка сохранения в листе воспоминания (направление A макета
// «Сохранить воспоминание»): левая часть сохраняет всё и знает, сколько, правая
// открывает выбор. Во время сохранения — кольцо, «37/94» и отмена.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/memory_save/save_split_button.dart';

Widget _host(Widget child, {double width = 360, double scale = 1.0}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.push_pin_outlined),
                      label: const Text('Закрепить'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  child,
                ]),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  group('saveButtonState', () {
    test('в покое показывает, сколько ещё не в галерее', () {
      final s = saveButtonState(total: 94, saved: 0);
      expect(s.mode, SaveButtonMode.idle);
      expect(s.label, '94');
    });

    test('частично сохранённое считает остаток', () {
      expect(saveButtonState(total: 94, saved: 80).label, '14');
    });

    test('всё сохранено — отметка без числа', () {
      final s = saveButtonState(total: 94, saved: 94);
      expect(s.mode, SaveButtonMode.allSaved);
      expect(s.label, '');
    });

    test('идёт сохранение — «готово/всего» и доля', () {
      final s = saveButtonState(total: 94, saved: 0, done: 37, jobTotal: 94);
      expect(s.mode, SaveButtonMode.running);
      expect(s.label, '37/94');
      expect(s.progress, closeTo(37 / 94, 1e-9));
    });
  });

  testWidgets('в покое: левая часть сохраняет всё, правая открывает выбор',
      (t) async {
    var all = 0, choose = 0, cancel = 0;
    await t.pumpWidget(_host(SaveSplitButton(
      state: saveButtonState(total: 94, saved: 0),
      onSaveAll: () => all++,
      onChoose: () => choose++,
      onCancel: () => cancel++,
    )));
    expect(find.text('94'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    await t.tap(find.byKey(SaveSplitButton.mainKey));
    await t.tap(find.byKey(SaveSplitButton.trailingKey));
    expect((all, choose, cancel), (1, 1, 0));
  });

  testWidgets('во время сохранения: кольцо, счётчик и отмена справа',
      (t) async {
    var all = 0, cancel = 0;
    await t.pumpWidget(_host(SaveSplitButton(
      state: saveButtonState(total: 94, saved: 0, done: 37, jobTotal: 94),
      onSaveAll: () => all++,
      onChoose: () {},
      onCancel: () => cancel++,
    )));
    expect(find.text('37/94'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.byKey(SaveSplitButton.trailingKey));
    await t.tap(find.byKey(SaveSplitButton.mainKey));
    expect((all, cancel), (0, 1));
  });

  testWidgets('всё сохранено: левая часть тоже открывает выбор', (t) async {
    var all = 0, choose = 0;
    await t.pumpWidget(_host(SaveSplitButton(
      state: saveButtonState(total: 94, saved: 94),
      onSaveAll: () => all++,
      onChoose: () => choose++,
      onCancel: () {},
    )));
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    await t.tap(find.byKey(SaveSplitButton.mainKey));
    expect((all, choose), (0, 1));
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('320 dp, шрифт $scale: ряд с «Закрепить» влезает', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_host(
        SaveSplitButton(
          state: saveButtonState(total: 94, saved: 0, done: 37, jobTotal: 94),
          onSaveAll: () {},
          onChoose: () {},
          onCancel: () {},
        ),
        width: 320,
        scale: scale,
      ));
      expect(t.takeException(), isNull);
      final main = t.getSize(find.byKey(SaveSplitButton.mainKey));
      expect(main.height, greaterThanOrEqualTo(48));
    });
  }
}
