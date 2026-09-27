import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/miss_you/heart_field.dart';

// Живой фон «Я скучаю» (поле сердечек): спам нажатиями не копит анимации.
void main() {
  Widget host(GlobalKey<HeartFieldState> key, {bool still = false}) => MediaQuery(
        data: MediaQueryData(size: const Size(360, 400), disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 330,
            height: 380,
            child: HeartField(key: key, color: const Color(0xFFFE7E8B), center: (s) => Offset(s.width / 2, 98)),
          ),
        ),
      );

  testWidgets('двадцать нажатий подряд: волн не больше пяти, энергия не больше единицы', (t) async {
    final key = GlobalKey<HeartFieldState>();
    await t.pumpWidget(host(key));
    for (var i = 0; i < 20; i++) {
      key.currentState!.pulse();
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(key.currentState!.debugWaves, lessThanOrEqualTo(HeartField.maxWaves));
    expect(key.currentState!.debugEnergy, lessThanOrEqualTo(1.0));
    // Через пару секунд всё остыло.
    await t.pump(const Duration(seconds: 3));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState!.debugWaves, 0);
    expect(key.currentState!.debugEnergy, lessThan(0.05));
  });

  testWidgets('«уменьшить движение»: без волн, тикер засыпает', (t) async {
    final key = GlobalKey<HeartFieldState>();
    await t.pumpWidget(host(key, still: true));
    key.currentState!.pulse();
    expect(key.currentState!.debugWaves, 0);
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState!.debugTicking, isFalse);
  });
}
