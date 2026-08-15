import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/stable_stream_builder.dart';

/// Каждая новая подписка на живой список уходит в сеть за ним целиком, поэтому
/// поток обязан переживать перерисовку. Проверяем по счётчику заведений.
void main() {
  testWidgets('поток заводится один раз на много перерисовок', (tester) async {
    var created = 0;
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return StableStreamBuilder<int>(
              create: () {
                created++;
                return Stream<int>.value(1);
              },
              keys: const ['g1'],
              builder: (_, snap) => Text('${snap.data}',
                  textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );

    expect(created, 1);

    for (var i = 0; i < 5; i++) {
      setOuter(() {});
      await tester.pump();
    }

    expect(created, 1, reason: 'перерисовка не должна заводить поток заново');
  });

  testWidgets('смена ключа заводит поток заново', (tester) async {
    var created = 0;
    var group = 'g1';
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return StableStreamBuilder<int>(
              create: () {
                created++;
                return Stream<int>.value(1);
              },
              keys: [group],
              builder: (_, snap) => Text('${snap.data}',
                  textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );

    expect(created, 1);

    setOuter(() => group = 'g2');
    await tester.pump();

    expect(created, 2, reason: 'другая пара — другой поток');
  });

  testWidgets('подписка снимается вместе с виджетом', (tester) async {
    var cancelled = false;
    // Broadcast: у обычного контроллера close() после снятой подписки ждёт
    // слушателя и вешает прогон.
    final controller = StreamController<int>.broadcast(
      onCancel: () => cancelled = true,
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StableStreamBuilder<int>(
          create: () => controller.stream,
          builder: (_, snap) =>
              Text('${snap.data}', textDirection: TextDirection.ltr),
        ),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    expect(cancelled, isTrue);
  });
}
