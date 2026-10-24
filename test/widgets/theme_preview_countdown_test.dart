import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/theme/theme_preview_countdown.dart';

void main() {
  test('Остаток пишется минутами и секундами', () {
    expect(themePreviewLeft(const Duration(minutes: 1)), '1:00');
    expect(themePreviewLeft(const Duration(seconds: 59, milliseconds: 1)), '1:00');
    expect(themePreviewLeft(const Duration(seconds: 42)), '0:42');
    expect(themePreviewLeft(const Duration(milliseconds: 300)), '0:01');
    expect(themePreviewLeft(Duration.zero), '0:00');
    expect(themePreviewLeft(const Duration(seconds: -3)), '0:00');
  });

  testWidgets('Плашка отсчитывает секунды', (tester) async {
    var now = DateTime(2026, 10, 24, 10);
    final ends = now.add(const Duration(minutes: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: ThemePreviewCountdown(
          label: 'Предпросмотр',
          endsAt: ends,
          now: () => now,
        ),
      ),
    );
    expect(find.text('Предпросмотр · 1:00'), findsOneWidget);

    now = now.add(const Duration(seconds: 18));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Предпросмотр · 0:42'), findsOneWidget);
  });

  testWidgets('Без срока остаётся одна подпись', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThemePreviewCountdown(label: 'Предпросмотр', endsAt: null),
      ),
    );
    expect(find.text('Предпросмотр'), findsOneWidget);
  });
}
