import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/m3_wave_progress.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

/// Волновая полоса из ролика Material: волна означает «идёт прямо сейчас» и
/// распрямляется к финишу. На статистику («сколько достижений собрано») её
/// вешать нельзя — там обычная полоса.
void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 240, child: child))));

  group('амплитуда', () {
    test('на старте волна уже видна', () {
      expect(M3WaveProgress.amplitudeFor(0.0), greaterThan(0));
    });

    test('в середине — максимум', () {
      expect(M3WaveProgress.amplitudeFor(0.5), 1.0);
    });

    test('к финишу распрямляется в линию', () {
      expect(M3WaveProgress.amplitudeFor(1.0), 0.0);
    });

    test('под самый конец гаснет постепенно, а не рывком', () {
      final a95 = M3WaveProgress.amplitudeFor(0.95);
      final a99 = M3WaveProgress.amplitudeFor(0.99);
      expect(a95, greaterThan(a99));
      expect(a99, greaterThan(0));
    });

    test('доля вне 0..1 не ломает расчёт', () {
      expect(M3WaveProgress.amplitudeFor(-1), inInclusiveRange(0.0, 1.0));
      expect(M3WaveProgress.amplitudeFor(5), inInclusiveRange(0.0, 1.0));
    });
  });

  group('виджет', () {
    testWidgets('с долей рисует волновую полосу', (tester) async {
      await tester.pumpWidget(host(const M3WaveProgress(value: 0.4)));
      await tester.pump();

      final bar = tester.widget<ExpressiveLinearProgressIndicator>(
        find.byType(ExpressiveLinearProgressIndicator),
      );
      expect(bar.value, 0.4);
      expect(bar.amplitude, M3WaveProgress.amplitudeFor(0.4));
    });

    testWidgets('без доли остаётся неопределённой', (tester) async {
      await tester.pumpWidget(host(const M3WaveProgress()));
      await tester.pump();

      final bar = tester.widget<ExpressiveLinearProgressIndicator>(
        find.byType(ExpressiveLinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });

    testWidgets('на финише волна выключена', (tester) async {
      await tester.pumpWidget(host(const M3WaveProgress(value: 1.0)));
      await tester.pump();

      final bar = tester.widget<ExpressiveLinearProgressIndicator>(
        find.byType(ExpressiveLinearProgressIndicator),
      );
      expect(bar.amplitude, 0.0);
    });
  });

  group('доля очереди синхронизации', () {
    test('пока ничего не отправляли — доли нет', () {
      expect(M3WaveProgress.queueFraction(active: 0, peak: 0), isNull);
    });

    test('половина очереди ушла — половина полосы', () {
      expect(M3WaveProgress.queueFraction(active: 5, peak: 10), 0.5);
    });

    test('очередь опустела — полная полоса', () {
      expect(M3WaveProgress.queueFraction(active: 0, peak: 10), 1.0);
    });

    test('очередь выросла сверх пика — доля не уходит в минус', () {
      expect(M3WaveProgress.queueFraction(active: 12, peak: 10), 0.0);
    });
  });
}
