import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/common/guide_hint.dart';

/// Владелец 12.11.2026, снимок подсказки на карточке кода: «выделение для
/// подсказки не соответствует форме блока». Кольцо всегда было таблеткой
/// (радиус — половина высоты), а у карточки углы 28. Форму кольца задаёт
/// экран: скругление цели, кольцо повторяет его с отступом.
void main() {
  BorderRadius? ringRadius(WidgetTester tester) {
    final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    for (final b in boxes) {
      final d = b.decoration;
      if (d is BoxDecoration && d.border != null && d.borderRadius != null) return d.borderRadius as BorderRadius;
    }
    return null;
  }

  Future<void> open(WidgetTester tester, {double? radius}) async {
    final target = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(key: target, width: 300, height: 150))),
    ));
    showGuideHint(
      tester.element(find.byKey(target)),
      targetKey: target,
      text: 'Подсказка',
      gotIt: 'Понятно',
      theme: buildAppTheme(kPalettes[3], Brightness.light),
      targetRadius: radius,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('кольцо повторяет скругление карточки', (tester) async {
    await open(tester, radius: 28);
    // Кольцо отступает от цели на 5 точек — и радиус больше на столько же.
    expect(ringRadius(tester), BorderRadius.circular(33));
    await tester.tap(find.text('Понятно'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('без радиуса кольцо — таблетка, как у кнопок', (tester) async {
    await open(tester);
    expect(ringRadius(tester), BorderRadius.circular((150 + 10) / 2));
    await tester.tap(find.text('Понятно'));
    await tester.pump(const Duration(seconds: 1));
  });
}
