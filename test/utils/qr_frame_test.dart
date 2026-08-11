import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/qr_frame.dart';

/// Кадр камеры приходит в YUV420: первая плоскость — яркость, по байту на
/// точку, со своей длиной строки. Из неё и собирается картинка для декодера,
/// поэтому проверяем именно разбор, а не сам ZXing.
void main() {
  /// Плоскость яркости `width`×`height` с отступом в строке: реальная камера
  /// почти всегда даёт `bytesPerRow` больше ширины.
  Uint8List plane(int width, int height, int bytesPerRow, int Function(int x, int y) at) {
    final bytes = Uint8List(bytesPerRow * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        bytes[y * bytesPerRow + x] = at(x, y);
      }
    }
    return bytes;
  }

  group('cropSquare', () {
    test('берёт центральный квадрат по короткой стороне', () {
      final r = cropSquare(width: 640, height: 480);
      expect(r.side, 480);
      expect(r.left, 80);
      expect(r.top, 0);
    });

    test('вертикальный кадр режется сверху и снизу', () {
      final r = cropSquare(width: 480, height: 640);
      expect(r.side, 480);
      expect(r.left, 0);
      expect(r.top, 80);
    });

    test('квадрат остаётся собой', () {
      final r = cropSquare(width: 300, height: 300);
      expect(r.side, 300);
      expect(r.left, 0);
      expect(r.top, 0);
    });

    test('доля повторяет окно видоискателя и остаётся по центру', () {
      final r = cropSquare(width: 1000, height: 800, fraction: 0.72);
      expect(r.side, 576);
      expect(r.left, 212);
      expect(r.top, 112);
    });

    test('нелепая доля зажимается, а не выносит квадрат за кадр', () {
      expect(cropSquare(width: 400, height: 400, fraction: 5).side, 400);
      expect(cropSquare(width: 400, height: 400, fraction: 0).side, 40);
    });
  });

  group('luminanceToPixels', () {
    test('серый байт становится серым пикселем, альфа непрозрачная', () {
      final bytes = plane(4, 4, 8, (x, y) => 200);
      final img = luminanceToPixels(
        bytes: bytes,
        bytesPerRow: 8,
        crop: const CropRect(left: 0, top: 0, side: 4),
        maxSide: 4,
      );
      expect(img.side, 4);
      expect(img.pixels.length, 16);
      // Int32List знаковый: 0xFFC8C8C8 лежит там отрицательным числом.
      expect(img.pixels.first, 0xFFC8C8C8.toSigned(32));
    });

    test('отступ строки не уезжает в картинку', () {
      // Байты за пределами ширины кадра забиты мусором: если разбор считает
      // строку по bytesPerRow неверно, он их подхватит.
      final bytes = Uint8List(8 * 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 8; x++) {
          bytes[y * 8 + x] = x < 4 ? 10 : 250;
        }
      }
      final img = luminanceToPixels(
        bytes: bytes,
        bytesPerRow: 8,
        crop: const CropRect(left: 0, top: 0, side: 4),
        maxSide: 4,
      );
      expect(img.pixels.every((p) => p == 0xFF0A0A0A.toSigned(32)), isTrue);
    });

    test('крупный кадр ужимается до предела', () {
      final bytes = plane(600, 600, 600, (x, y) => x < 300 ? 0 : 255);
      final img = luminanceToPixels(
        bytes: bytes,
        bytesPerRow: 600,
        crop: const CropRect(left: 0, top: 0, side: 600),
        maxSide: 300,
      );
      expect(img.side, 300);
      expect(img.pixels.length, 300 * 300);
      // Левая половина осталась чёрной, правая белой — прореживание не
      // перемешало столбцы.
      expect(img.pixels[0], 0xFF000000.toSigned(32));
      expect(img.pixels[299], 0xFFFFFFFF.toSigned(32));
    });

    test('мелкий кадр не растягивается', () {
      final bytes = plane(120, 120, 120, (x, y) => 128);
      final img = luminanceToPixels(
        bytes: bytes,
        bytesPerRow: 120,
        crop: const CropRect(left: 0, top: 0, side: 120),
        maxSide: 400,
      );
      expect(img.side, 120);
    });

    test('смещение обрезки учитывается', () {
      final bytes = plane(8, 8, 8, (x, y) => x >= 4 ? 255 : 0);
      final img = luminanceToPixels(
        bytes: bytes,
        bytesPerRow: 8,
        crop: const CropRect(left: 4, top: 0, side: 4),
        maxSide: 4,
      );
      expect(img.pixels.every((p) => p == 0xFFFFFFFF.toSigned(32)), isTrue);
    });

    test('обрезанный буфер не роняет разбор', () {
      // У реальных кадров последняя строка бывает короче: читаем аккуратно.
      final bytes = Uint8List(8 * 4 - 3);
      final img = luminanceToPixels(
        bytes: bytes,
        bytesPerRow: 8,
        crop: const CropRect(left: 0, top: 0, side: 4),
        maxSide: 4,
      );
      expect(img.pixels.length, 16);
    });
  });
}
