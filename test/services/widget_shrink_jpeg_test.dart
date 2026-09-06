// Запасное уменьшение снимка для виджета обязано давать файл, который влезает
// в контейнер.
//
// До 06.09.2026 запасной путь отдавал PNG (`toByteData(format: png)`): у кадра
// 1200×1200 это два-четыре мегабайта, то есть больше kMaxWidgetPhotoBytes, и
// `widgetPhotoPayload` его отбраковывал. Если оригинал тоже был крупный, в
// контейнер не попадало НИЧЕГО и путь оставался пустым — на iPhone это видно в
// самоотчётах: у 45% телефонов, где фото стоит на сервере, `my_photo_path`
// пуст, а виджет пустой.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/services/widget_image_limit.dart';

Uint8List _shot(int w, int h) {
  final frame = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      // Шум, а не заливка: однотонное поле жмётся в килобайты и ничего не
      // проверяет.
      frame.setPixelRgb(x, y, (x * 7 + y * 13) % 255, (x * 3) % 255, (y * 5) % 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(frame, quality: 95));
}

void main() {
  test('снимок с камеры ужимается и влезает в контейнер', () {
    final small = shrinkToJpeg(_shot(3000, 2000), 1200);
    expect(small, isNotNull);
    expect(small!.length, lessThanOrEqualTo(kMaxWidgetPhotoBytes));
    final frame = img.decodeJpg(small)!;
    expect(frame.width, 1200);
    expect(frame.height, 800, reason: 'пропорции сохраняются');
  });

  test('маленькую картинку не растягиваем', () {
    final small = shrinkToJpeg(_shot(300, 200), 1200);
    final frame = img.decodeJpg(small!)!;
    expect(frame.width, 300);
    expect(frame.height, 200);
  });

  test('аватарка ужимается до своей стороны', () {
    final frame = img.decodeJpg(shrinkToJpeg(_shot(2000, 2000), 400)!)!;
    expect(frame.width, 400);
  });

  test('мусор вместо картинки не роняет, а отдаёт null', () {
    expect(shrinkToJpeg(Uint8List.fromList([1, 2, 3, 4, 5]), 1200), isNull);
    expect(shrinkToJpeg(Uint8List(0), 1200), isNull);
  });

  test('результат запасного пути проходит отбор payload', () {
    final raw = _shot(4000, 3000);
    final small = shrinkToJpeg(raw, 1200);
    expect(widgetPhotoPayload(original: raw, compressed: small), isNotNull,
        reason: 'иначе в контейнер не ляжет ничего и виджет останется пустым');
  });
}
