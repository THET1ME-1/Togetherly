// Сетка «Выбрать кадры»: касание отмечает кадр, удержание с протягиванием и
// горизонтальный проход пальцем отмечают подряд. У воспоминания бывает 93
// кадра — выбирать по одному двадцать штук никто не станет.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/widgets/memory_save/frame_picker.dart';

List<MediaFile> _files(int n) => [
      for (var i = 0; i < n; i++)
        MediaFile(
          // Пустая заглушка: StorageImage в тесте не ходит в сеть.
          ref: 'localfile:///nope/$i.jpg',
          kind: i == 3 ? SaveKind.video : SaveKind.photo,
          index: i,
        ),
    ];

Future<FramePickResult?> _pump(
  WidgetTester t, {
  int n = 24,
  Set<String> saved = const {},
  double width = 360,
  double scale = 1.0,
}) async {
  FramePickResult? out;
  await t.binding.setSurfaceSize(Size(width, 760));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
          size: Size(width, 760), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: FramePicker(
          files: _files(n),
          savedKeys: saved,
          onDone: (r) => out = r,
        ),
      ),
    ),
  ));
  await t.pump();
  return out;
}

Finder _tile(int i) => find.byKey(ValueKey('frame-$i'));

String _counter(WidgetTester t) =>
    t.widget<Text>(find.byKey(FramePicker.counterKey)).data!;

void main() {
  testWidgets('касание отмечает и снимает кадр', (t) async {
    await _pump(t);
    await t.tap(_tile(2));
    await t.pump();
    expect(_counter(t), contains('1'));
    await t.tap(_tile(2));
    await t.pump();
    expect(_counter(t), contains('0'));
  });

  testWidgets('удержание и протягивание отмечает кадры подряд', (t) async {
    await _pump(t);
    final g = await t.startGesture(t.getCenter(_tile(1)));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveTo(t.getCenter(_tile(4)));
    await t.pump();
    await g.moveTo(t.getCenter(_tile(9)));
    await t.pump();
    await g.up();
    await t.pump();
    // 1…9 включительно.
    expect(_counter(t), contains('9'));
  });

  testWidgets('протягивание назад снимает то, что протянули лишнего',
      (t) async {
    await _pump(t);
    final g = await t.startGesture(t.getCenter(_tile(0)));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveTo(t.getCenter(_tile(7)));
    await t.pump();
    await g.moveTo(t.getCenter(_tile(2)));
    await t.pump();
    await g.up();
    await t.pump();
    expect(_counter(t), contains('3'));
  });

  testWidgets('горизонтальный проход по ряду отмечает ряд', (t) async {
    await _pump(t);
    final from = t.getCenter(_tile(0));
    final to = t.getCenter(_tile(3));
    await t.dragFrom(from, to - from);
    await t.pump();
    expect(_counter(t), contains('4'));
  });

  testWidgets('«Все» отмечает всё, повторно — снимает', (t) async {
    await _pump(t, n: 30);
    await t.tap(find.byKey(FramePicker.allKey));
    await t.pump();
    expect(_counter(t), contains('30'));
    await t.tap(find.byKey(FramePicker.allKey));
    await t.pump();
    expect(_counter(t), contains('0'));
  });

  testWidgets('«Сохранить» отдаёт выбранные кадры по порядку', (t) async {
    FramePickResult? result;
    await t.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FramePicker(
          files: _files(12),
          savedKeys: const {},
          onDone: (r) => result = r,
        ),
      ),
    ));
    await t.tap(_tile(5));
    await t.tap(_tile(1));
    await t.pump();
    await t.tap(find.byKey(FramePicker.saveKey));
    await t.pump();
    expect(result!.share, isFalse);
    expect(result!.files.map((f) => f.index), [1, 5]);
  });

  testWidgets('уже сохранённый кадр помечен, но выбрать его можно', (t) async {
    await _pump(t, saved: {'localfile:///nope/0.jpg'});
    expect(find.byKey(const ValueKey('frame-saved-0')), findsOneWidget);
    await t.tap(_tile(0));
    await t.pump();
    expect(_counter(t), contains('1'));
  });

  for (final w in [320.0, 360.0]) {
    testWidgets('$w dp, шрифт 1.3: без переполнения', (t) async {
      await _pump(t, width: w, scale: 1.3);
      expect(t.takeException(), isNull);
    });
  }
}
