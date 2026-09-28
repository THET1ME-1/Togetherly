import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/main.dart' show LoveApp;
import 'package:love_app/models/pair_jar.dart';
import 'package:love_app/widgets/chest/jar_toast.dart';

// Жалоба 28.09.2026: строка «+1 в копилку пары» после ролика не пропадала.
// Награда приходит, пока реклама на экране и кадры не рисуются; таймер
// убирал строку только «если она уже нарисована» — а она ещё не была, и
// после возврата из рекламы строка оставалась навсегда.
void main() {
  testWidgets('строка уходит, даже если её таймер сработал до первого кадра', (t) async {
    await t.pumpWidget(MaterialApp(navigatorKey: LoveApp.rootNavigatorKey, home: const Scaffold()));
    showJarToast(const PairJar(drops: [true, true], added: true));
    // Ни одного кадра до срока: время уходит вперёд одним шагом.
    await t.pump(const Duration(seconds: 5));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('2'), findsNothing);
  });

  testWidgets('в обычном случае строка видна и уходит сама', (t) async {
    await t.pumpWidget(MaterialApp(navigatorKey: LoveApp.rootNavigatorKey, home: const Scaffold()));
    showJarToast(const PairJar(drops: [true, true, false], added: true));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('3'), findsWidgets);
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('3'), findsNothing);
  });

  testWidgets('строку закрывают касанием, не дожидаясь таймера', (t) async {
    await t.pumpWidget(MaterialApp(navigatorKey: LoveApp.rootNavigatorKey, home: const Scaffold()));
    showJarToast(const PairJar(drops: [true, true, true, true], added: true));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('4'), findsWidgets);
    await t.tap(find.textContaining('4').first);
    await t.pump();
    expect(find.textContaining('4'), findsNothing);
    await t.pump(const Duration(seconds: 3));
  });
}
