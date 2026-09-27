import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_jar.dart';
import 'package:love_app/services/pair_jar_service.dart';
import 'package:love_app/widgets/chest/jar_drops.dart';

// Копилка пары (pocketbase/pb_hooks/pair_jar.js): сервер шлёт капли числами
// 1 (моя) и 2 (партнёра), бонус открытий и признаки added/filled.
void main() {
  setUp(() => PairJarService.instance.debugReset());

  test('разбор ответа сервера', () {
    final j = PairJar.fromJson({
      'size': 10,
      'drops': [1, 2, 1],
      'bonus': 2,
      'capped': false,
      'added': true,
      'filled': false,
    })!;
    expect(j.count, 3);
    expect(j.mine, 2);
    expect(j.partner, 1);
    expect(j.bonus, 2);
    expect(j.added, isTrue);
    expect(PairJar.fromJson(null), isNull);
    expect(PairJar.fromJson('x'), isNull);
  });

  test('лишние капли и кривой бонус не ломают', () {
    final j = PairJar.fromJson({
      'size': 3,
      'drops': [1, 1, 1, 1, 2],
      'bonus': -4,
    })!;
    expect(j.count, 3);
    expect(j.bonus, 0);
  });

  test('строка после ролика только когда капля упала', () {
    final shown = <PairJar>[];
    PairJarService.instance.onDrop = shown.add;
    PairJarService.instance.applyDrop(const PairJar(drops: [true]));
    expect(shown, isEmpty, reason: 'added = false: капля не упала (предел или частый ролик)');
    PairJarService.instance.applyDrop(const PairJar(drops: [true, false], added: true));
    expect(shown.length, 1);
    expect(PairJarService.instance.jar?.count, 2);
    PairJarService.instance.onDrop = null;
  });

  test('смена пары забывает прежнюю копилку', () {
    PairJarService.instance.bindGroup('a');
    PairJarService.instance.apply(const PairJar(drops: [true], bonus: 1));
    PairJarService.instance.bindGroup('b');
    expect(PairJarService.instance.jar, isNull);
  });

  testWidgets('десять капель на 320 точках без переполнения', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 170,
            child: JarDrops(
              jar: const PairJar(drops: [true, true, false]),
              mine: Colors.brown,
              partner: Colors.white,
              dropHeight: 26,
              gap: 2,
              popLast: true,
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 800));
    expect(t.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
