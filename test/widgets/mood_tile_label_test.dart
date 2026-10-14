import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/widgets/mood_picker_dialog.dart';

/// Подпись плитки настроения: слово, которое не влезает в ширину плитки,
/// Flutter рвёт посреди («Подмигив/аю»). У своих настроений названия длиннее
/// встроенных, поэтому длинное слово уменьшается, а не рвётся.
void main() {
  testWidgets('короткая подпись остаётся в 11 пунктов, длинное слово уменьшается', (tester) async {
    late double short, long;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        short = moodLabelSize(ctx, 'Смех', 57.6);
        long = moodLabelSize(ctx, 'Подмигиваю', 57.6);
        return const SizedBox();
      }),
    ));
    expect(short, 11);
    expect(long, lessThan(11));
    // Ниже предела не мельчим: дальше слово всё же перенесётся.
    expect(long, greaterThanOrEqualTo(kMoodLabelMinSize));
  });

  testWidgets('крупный системный шрифт учитывается при замере', (tester) async {
    late double plain, scaled;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        plain = moodLabelSize(ctx, 'Пицца', 60);
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: Builder(builder: (inner) {
            scaled = moodLabelSize(inner, 'Пицца', 60);
            return const SizedBox();
          }),
        );
      }),
    ));
    expect(plain, 11);
    expect(scaled, lessThan(11));
  });
}
