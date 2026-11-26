import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/anim_curtain.dart';

/// Метель при смене сундука: страницу меняет кадр, закрывший экран, а не
/// отдельные часы. В сборке 274 страница менялась по своим часам, а метель
/// начиналась, когда разожмётся, и на медленном телефоне сундук сменился бы
/// на глазах.
void main() {
  // десять кадров по 50 мс
  final bytes = File('test/fixtures/anim_curtain_10x50ms.webp').readAsBytesSync();

  Future<List<String>> run(WidgetTester tester, Uint8List data, int coverMs) async {
    final log = <String>[];
    final clock = Stopwatch()..start();
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: AnimCurtain(
          bytes: data,
          coverMs: coverMs,
          onCover: () => log.add('cover ${clock.elapsedMilliseconds}'),
          onDone: () => log.add('done ${clock.elapsedMilliseconds}'),
        ),
      ));
      for (var i = 0; i < 40 && !log.any((l) => l.startsWith('done')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    return log;
  }

  int ms(String line) => int.parse(line.split(' ').last);

  testWidgets('страница меняется кадром на отметке, один раз, потом конец', (tester) async {
    final log = await run(tester, bytes, 200);
    expect(log.map((l) => l.split(' ').first), ['cover', 'done']);
    // кадр с временем 200 мс показывается не раньше своего времени
    expect(ms(log[0]), greaterThanOrEqualTo(190));
    expect(ms(log[1]), greaterThanOrEqualTo(ms(log[0]) + 250));
  });

  testWidgets('битая анимация — страница всё равно меняется, занавес уходит', (tester) async {
    final log = await run(tester, Uint8List.fromList([1, 2, 3, 4]), 200);
    expect(log.map((l) => l.split(' ').first), ['cover', 'done']);
  });

  testWidgets('отметка позже конца анимации — смена страницы в конце', (tester) async {
    final log = await run(tester, bytes, 5000);
    expect(log.map((l) => l.split(' ').first), ['cover', 'done']);
  });
}
