import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/season_chest.dart';
import 'package:love_app/widgets/chest/season_glitch.dart';

const _spec = SeasonGlitchSpec(mid: '13/13', peak: '666');

void main() {
  testWidgets('сбой проходит все такты и возвращает настоящее число', (tester) async {
    final g = SeasonGlitch(_spec);
    addTearDown(g.dispose);
    final seen = <GlitchPhase>{};
    final texts = <String?>{};
    var peaks = 0;
    g.onPeak = () => peaks++;
    g.addListener(() {
      seen.add(g.phase);
      texts.add(g.text);
    });
    final done = g.play();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await done;
    expect(seen, containsAll(GlitchPhase.values));
    expect(texts, containsAll(['13/13', '666']));
    expect(peaks, 1, reason: 'вибрация и треск — один раз за сбой');
    expect(g.phase, GlitchPhase.calm);
    expect(g.text, isNull, reason: 'после сбоя на кнопке снова настоящее число');
  });

  testWidgets('уменьшение движения: только подмена числа, без мигания и разрывов', (tester) async {
    final g = SeasonGlitch(_spec)..reduced = true;
    addTearDown(g.dispose);
    final seen = <GlitchPhase>{};
    g.addListener(() => seen.add(g.phase));
    final done = g.play();
    await tester.pump(const Duration(milliseconds: 800));
    await done;
    expect(seen, {GlitchPhase.peak, GlitchPhase.calm});
  });

  testWidgets('остановка посреди сбоя сразу возвращает кнопку', (tester) async {
    final g = SeasonGlitch(_spec);
    addTearDown(g.dispose);
    final done = g.play();
    await tester.pump(const Duration(milliseconds: 300));
    g.stop();
    expect(g.phase, GlitchPhase.calm);
    expect(g.text, isNull);
    await tester.pump(const Duration(seconds: 2));
    await done;
    expect(g.phase, GlitchPhase.calm);
  });

  test('битые знаки не меняют длину надписи', () {
    for (var k = 0; k < 8; k++) {
      expect(garble('13/13', k).length, 5);
    }
    expect(garble('13/13', 0), isNot('13/13'));
  });

  testWidgets('надпись на пике влезает в кнопку на 320 точках при шрифте 1.3', (tester) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = SeasonGlitch(_spec);
    addTearDown(g.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 200), textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedBuilder(
                animation: g,
                builder: (_, _) => FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 0)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: GlitchLabel(
                      glitch: g,
                      prefix: 'Открыть за рекламу',
                      real: '3/3',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final done = g.play();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
    }
    await done;
  });
}
