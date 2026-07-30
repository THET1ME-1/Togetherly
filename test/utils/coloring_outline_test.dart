// Раскраску загружает человек, а рисует по ней двое. Если контур не подготовить,
// он закроет собой холст (белый фон поверх мазков), а заливка утечёт через
// разрыв в линии и зальёт весь лист. Тесты держат обе границы.

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/utils/coloring_outline.dart';

/// Белый лист с чёрной рамкой внутри — замкнутая фигура.
img.Image _closedShape({int w = 200, int h = 200}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  img.drawRect(im,
      x1: 20, y1: 20, x2: w - 20, y2: h - 20,
      color: img.ColorRgb8(0, 0, 0), thickness: 4);
  return im;
}

/// Та же рамка, но с дырой в верхней стороне.
img.Image _brokenShape({int w = 200, int h = 200}) {
  final im = _closedShape(w: w, h: h);
  img.fillRect(im,
      x1: 80, y1: 16, x2: 120, y2: 26, color: img.ColorRgb8(255, 255, 255));
  return im;
}

void main() {
  group('prepareColoringOutline', () {
    test('белый фон становится прозрачным', () {
      final out = prepareColoringOutline(img.encodePng(_closedShape()));
      final im = img.decodePng(out.png)!;
      // Угол — это фон, он обязан просвечивать: иначе контур закроет мазки.
      expect(im.getPixel(2, 2).a, 0);
    });

    test('линии остаются непрозрачными и тёмными', () {
      final out = prepareColoringOutline(img.encodePng(_closedShape()));
      final im = img.decodePng(out.png)!;
      final onLine = im.getPixel(20, 100);
      expect(onLine.a, greaterThan(200));
      expect(onLine.r, lessThan(80));
    });

    test('пропорции считаются по файлу, а не по квадрату', () {
      final tall = prepareColoringOutline(
          img.encodePng(_closedShape(w: 600, h: 900)));
      expect(tall.ratio, closeTo(600 / 900, 0.001));

      final wide = prepareColoringOutline(
          img.encodePng(_closedShape(w: 1200, h: 600)));
      expect(wide.ratio, closeTo(2.0, 0.001));
    });

    test('замкнутый контур не течёт', () {
      expect(prepareColoringOutline(img.encodePng(_closedShape())).leaks,
          isFalse);
    });

    test('разрыв в линии виден до начала рисования', () {
      expect(prepareColoringOutline(img.encodePng(_brokenShape())).leaks,
          isTrue);
    });

    test('слишком вытянутый лист приводится к разумной пропорции', () {
      // Панорама 4:1 половинками по 2:1 — рисовать нечем, поле уже пальца.
      final out = prepareColoringOutline(
          img.encodePng(_closedShape(w: 2000, h: 500)));
      expect(out.ratio, lessThanOrEqualTo(kColoringMaxRatio));
      expect(out.ratio, greaterThanOrEqualTo(1 / kColoringMaxRatio));
    });

    test('битый файл не роняет приложение', () {
      expect(() => prepareColoringOutline([1, 2, 3]), throwsFormatException);
    });
  });
}
