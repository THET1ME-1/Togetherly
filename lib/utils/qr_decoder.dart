import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

import 'qr_frame.dart';

/// Чтение QR из кадра камеры чистым Dart — без ML Kit и без сервисов Google.
///
/// Вынесено из виджета намеренно: камеру в тестах не поднять, а весь путь
/// «байты кадра → строка» проверить надо. Тест собирает настоящий QR, кладёт
/// его в такой же буфер, какой отдаёт камера, и прогоняет через эту функцию.
class QrDecoder {
  final QRCodeReader _reader = QRCodeReader();

  /// Возвращает содержимое кода или `null`, если в кадре его нет.
  ///
  /// [bytesPerPixel] = 1 для плоскости яркости YUV420 (Android) и 4 для BGRA
  /// (iOS). Нечитаемый кадр — это норма, а не сбой: их тридцать в секунду.
  String? decode({
    required Uint8List bytes,
    required int bytesPerRow,
    required int width,
    required int height,
    int bytesPerPixel = 1,
    double windowFraction = kQrWindowFraction,
    int maxSide = 320,
  }) {
    final crop = cropSquare(
      width: width,
      height: height,
      fraction: windowFraction,
    );
    final frame = luminanceToPixels(
      bytes: bytes,
      bytesPerRow: bytesPerRow,
      crop: crop,
      maxSide: maxSide,
      bytesPerPixel: bytesPerPixel,
    );

    final source = RGBLuminanceSource(frame.side, frame.side, frame.pixels);
    // Гибридный бинаризатор, а не гистограммный: код читают при комнатном
    // свете и с бликом от экрана партнёра, освещённость по кадру гуляет.
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    try {
      return _reader.decode(bitmap).text;
    } on NotFoundException {
      return null;
    } on FormatException {
      return null;
    } on ChecksumException {
      return null;
    }
  }
}
