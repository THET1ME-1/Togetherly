import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/widgets/offline_sync_banner.dart';

/// Фоновая отправка молчит.
///
/// Плашку «Синхронизация…» чинили четыре раза, и каждый раз она возвращалась:
/// любой дефект очереди превращался в вечную серую доску поверх шапки. Решение
/// от 26.07 — не рассказывать про очередь вовсе. Тест держит это решение, чтобы
/// плашка не приехала обратно «заодно» с другой правкой.
Widget _app() => MaterialApp(
      home: OfflineSyncBanner(child: const Scaffold(body: SizedBox.expand())),
    );

void main() {
  tearDown(() {
    OutboxService.instance.activeCount.value = 0;
    OutboxService.instance.poisonCount.value = 0;
  });

  testWidgets('очередь в работе не показывает никакой плашки', (tester) async {
    OutboxService.instance.activeCount.value = 7;

    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 10));

    expect(find.textContaining('инхронизац'), findsNothing);
    expect(find.textContaining('yncing'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('плашку можно убрать, но только после подтверждения (TOG-79)', (tester) async {
    var dropped = 0;
    OutboxService.instance.poisonCount.value = 1;
    OutboxService.debugDropAll = () async {
      dropped++;
      OutboxService.instance.poisonCount.value = 0;
    };
    addTearDown(() => OutboxService.debugDropAll = null);

    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sync_drop')));
    // Смена плашки анимируется: жмём, когда вопрос доехал.
    await tester.pump(const Duration(milliseconds: 400));
    expect(dropped, 0, reason: 'первое нажатие только спрашивает');
    expect(find.byKey(const ValueKey('sync_drop_confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync_drop_confirm')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(dropped, 1);
  });

  testWidgets('передумал убирать — плашка снова с повтором', (tester) async {
    OutboxService.instance.poisonCount.value = 1;
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sync_drop')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('sync_drop_keep')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('sync_drop')), findsOneWidget);
  });

  testWidgets('непринятая сервером правка остаётся видимой', (tester) async {
    OutboxService.instance.poisonCount.value = 2;

    await tester.pumpWidget(_app());
    await tester.pump();

    // Язык в тестах не задан, поэтому принимаем обе локали.
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          (w.data?.contains('овторить') == true ||
              w.data?.contains('retry') == true)),
      findsOneWidget,
    );
  });
}
