import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/snowball_service.dart';
import 'package:love_app/widgets/snow/snow_hit_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Попадание снежка у партнёра (тема «Новый год», вариант «В стекло»):
/// снежок шлёпается о стекло экрана поверх любого экрана, сверху плашка
/// «Снежок от {имя}» и «Кинуть в ответ», через несколько секунд всё уходит
/// само. Серия снежков — одно попадание «×N», а не очередь анимаций.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    SnowballService.instance.debugReset();
  });

  group('серия снежков', () {
    test('несколько подряд — одно попадание с числом', () {
      final s = SnowballService.instance;
      s.hit(1, partnerName: 'Аня');
      s.hit(1, partnerName: 'Аня');
      s.hit(2, partnerName: 'Аня');
      expect(s.current.value!.count, 4);
      expect(s.current.value!.from, 'Аня');
    });

    test('после показа новый снежок — новое попадание', () {
      final s = SnowballService.instance;
      s.hit(1, partnerName: 'Аня');
      final first = s.current.value!;
      s.done(first);
      expect(s.current.value, isNull);
      s.hit(1, partnerName: 'Аня');
      expect(s.current.value!.count, 1);
      expect(identical(s.current.value, first), isFalse);
    });

    test('снежок вживую: попадание и подтверждение серверу, один раз на номер', () async {
      final s = SnowballService.instance;
      final acked = <String>[];
      s.debugAck = (id) async => acked.add(id);
      s.bindForTest('g1', 'Аня');
      s.received('sb1');
      s.received('sb1'); // событие канала пришло дважды (переподключение)
      await Future<void>.delayed(Duration.zero);
      expect(s.current.value!.count, 1);
      expect(acked, ['sb1']);
    });

    test('ноль снежков ничего не показывает', () {
      SnowballService.instance.hit(0, partnerName: 'Аня');
      expect(SnowballService.instance.current.value, isNull);
    });
  });

  Future<void> pump(WidgetTester tester, {bool still = false, VoidCallback? onBack}) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: still),
        child: SnowHitOverlay(onThrowBack: onBack ?? () {}, child: child!),
      ),
      home: const Scaffold(body: Center(child: Text('экран'))),
    ));
  }

  testWidgets('попадание: плашка с именем, кнопка ответа, потом уходит само', (tester) async {
    var back = 0;
    await pump(tester, onBack: () => back++);
    SnowballService.instance.hit(1, partnerName: 'Аня');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Снежок от Аня'), findsOneWidget);
    expect(find.text('Кинуть в ответ'), findsOneWidget);
    expect(find.text('экран'), findsOneWidget, reason: 'экран под снегом никуда не делся');

    await tester.tap(find.text('Кинуть в ответ'));
    expect(back, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Снежок от Аня'), findsNothing);
    expect(SnowballService.instance.current.value, isNull);
  });

  testWidgets('имя партнёра неизвестно — «Снежок от партнёра», а не «от Партнёр»', (tester) async {
    await pump(tester);
    SnowballService.instance.hit(1, partnerName: '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Снежок от партнёра'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('серия показывает число', (tester) async {
    await pump(tester);
    SnowballService.instance.hit(3, partnerName: 'Аня');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.textContaining('×3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('без анимации в системе — один спокойный кадр с плашкой', (tester) async {
    await pump(tester, still: true);
    SnowballService.instance.hit(1, partnerName: 'Аня');
    await tester.pump();
    expect(find.text('Снежок от Аня'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Снежок от Аня'), findsNothing);
  });

  testWidgets('пока снега нет, касания проходят к экрану', (tester) async {
    var taps = 0;
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SnowHitOverlay(onThrowBack: () {}, child: child!),
      home: Scaffold(body: Center(child: TextButton(onPressed: () => taps++, child: const Text('кнопка')))),
    ));
    await tester.tap(find.text('кнопка'));
    expect(taps, 1);
  });
}
