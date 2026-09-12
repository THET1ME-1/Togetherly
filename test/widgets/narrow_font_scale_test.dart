import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/widgets/mood_picker_dialog.dart';

/// Крупный системный шрифт на узком экране.
///
/// Прогон на эмуляторе (`wm size 720x1600`, `wm density 360`, `font_scale 1.3`)
/// дал четыре полосы переполнения: сетка настроений (9.6 px), плитки листа
/// «Добавить воспоминание» (15 px), пилюли выбора размера виджета (3 px) и
/// превью виджетов в каталоге (до 59 px). Первые две чинятся расчётом высоты
/// ячейки, вторые две — устройством самих виджетов, поэтому их стережёт
/// сканер исходников: увидеть такое можно только рендером, а тест обязан
/// краснеть раньше.
void main() {
  group('сетка настроений', () {
    late BuildContext ctx;

    Future<void> pump(WidgetTester tester, double scale) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          }),
        ),
      ));
    }

    testWidgets('на 360 dp при обычном шрифте отношение прежнее',
        (tester) async {
      await pump(tester, 1.0);
      // Лист на 360 dp даёт сетке 320 точек — ровно тот случай, под который
      // подбиралось число 0.62.
      expect(moodTileRatio(ctx, 320), 0.62);
    });

    testWidgets('на 320 dp ячейка подрастает даже при обычном шрифте',
        (tester) async {
      await pump(tester, 1.0);
      expect(moodTileRatio(ctx, 280), lessThan(0.62));
    });

    testWidgets('при шрифте 1.3 ячейка вмещает две строки подписи',
        (tester) async {
      await pump(tester, 1.3);
      const gridWidth = 280.0;
      final ratio = moodTileRatio(ctx, gridWidth);
      expect(ratio, lessThan(0.62), reason: 'ячейка обязана подрасти');

      final cell = (gridWidth - 8 * 4) / 5;
      final height = cell / ratio;
      final need = cell + 6 + 11 * 1.3 * 1.2 * 2;
      expect(height, greaterThanOrEqualTo(need),
          reason: 'плитка, отступ и две строки подписи должны поместиться');
    });
  });

  group('сторожа исходников', () {
    final widgetScreen =
        File('lib/screens/widget_screen.dart').readAsStringSync();

    test('превью каталога рисуется без масштабирования шрифта', () {
      expect(widgetScreen.contains('MediaQuery.withNoTextScaling'), isTrue,
          reason: 'превью виджета — картинка рабочего стола, а не текст '
              'интерфейса: системный шрифт не должен её распирать');
    });

    test('превью ужимается целиком, а не ломается на узком экране', () {
      // Кегли внутри превью подобраны под карточку шириной 296 (экран 360 dp).
      // На 320 dp места меньше, и без общего сжатия превью «Вместе 2×2»
      // вылезало на 45 пикселей, «Скучаю» — на 33.
      expect(widgetScreen.contains('kPreviewDesignWidth'), isTrue);
      expect(widgetScreen.contains('fit: BoxFit.contain'), isTrue);
    });

    test('пилюля выбора размера не держит жёсткую высоту', () {
      expect(widgetScreen.contains('curve: Curves.easeOut,\n                  height: 36,'),
          isFalse,
          reason: 'высота сегмента считается по содержимому, иначе метка с '
              'подписью не влезает при крупном шрифте');
      expect(widgetScreen.contains('BoxConstraints(minHeight: 36)'), isTrue);
    });

    test('заголовок ленты делит строку с кнопкой в ОБОИХ местах', () {
      // Ленту на главной рисует встроенный вариант из memory_lane_screen, а не
      // home_memory_preview: правка только во втором ничего не меняла.
      for (final path in const [
        'lib/screens/home/home_memory_preview.dart',
        'lib/screens/memory_lane_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final i = src.indexOf('relationshipMemoryLane');
        expect(i, greaterThan(0), reason: '$path потерял заголовок ленты');
        final before = src.substring(0, i);
        expect(before.lastIndexOf('Expanded(') > before.lastIndexOf('Row('),
            isTrue,
            reason: 'в $path заголовок обязан стоять в Expanded, иначе ряд с '
                'кнопкой «Посмотреть все» уносит на 108 пикселей вправо');
      }
    });

    test('лист добавления воспоминания считает высоту плитки', () {
      final lane = File('lib/screens/memory_lane_screen.dart').readAsStringSync();
      expect(lane.contains('childAspectRatio: 0.92,'), isFalse,
          reason: 'жёсткое отношение сторон резало подписи при шрифте 1.3');
      expect(lane.contains('_addTileRatio(ctx2, box.maxWidth)'), isTrue);
    });
  });
}
