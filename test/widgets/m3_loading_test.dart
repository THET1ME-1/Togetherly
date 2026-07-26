import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/m3_loading.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

/// Общий индикатор ожидания. Морфинг-фигура M3 Expressive вместо кольца —
/// но только там, где она читается: на мелком размере фигура превращается в
/// дрожащее пятно, поэтому ниже порога остаётся кольцо.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('M3Loading', () {
    testWidgets('На обычном размере — морфинг-фигура', (tester) async {
      await tester.pumpWidget(host(const M3Loading(color: Colors.pink)));
      await tester.pump();

      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Мельче порога — кольцо, а не фигура', (tester) async {
      await tester.pumpWidget(
        host(const M3Loading(color: Colors.pink, size: 14)),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    });

    testWidgets('Размер держится заданный', (tester) async {
      await tester.pumpWidget(
        host(const M3Loading(color: Colors.pink, size: 56)),
      );
      await tester.pump();

      final box = tester.getSize(find.byType(M3Loading));
      expect(box.width, 56);
      expect(box.height, 56);
    });

    testWidgets('Contained добавляет тональный круг вокруг фигуры',
        (tester) async {
      await tester.pumpWidget(
        host(const M3Loading(
          color: Colors.white,
          containerColor: Colors.black,
          contained: true,
        )),
      );
      await tester.pump();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(M3Loading),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, Colors.black);
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    });
  });

  group('M3PageLoading', () {
    testWidgets('Центрирует фигуру на всю страницу', (tester) async {
      await tester.pumpWidget(host(const M3PageLoading(color: Colors.pink)));
      await tester.pump();

      expect(find.byType(Center), findsWidgets);
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    });
  });
}
