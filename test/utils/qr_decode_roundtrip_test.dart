import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/qr_decoder.dart';
import 'package:love_app/utils/qr_frame.dart';
import 'package:qr/qr.dart';

/// Проверка декодера без телефона и без эмулятора.
///
/// Настоящий QR собирается прямо здесь, укладывается в такой же буфер, какой
/// отдаёт камера (плоскость яркости с отступом в строке), и прогоняется через
/// тот же код, что будет работать на устройстве. Так ловятся ровно те ошибки,
/// которые глазами не увидеть: съехавшая строка, неверная обрезка, слишком
/// жадное прореживание.
void main() {
  final decoder = QrDecoder();

  /// Рисует код в кадре [frameW]×[frameH] и отдаёт плоскость яркости.
  ///
  /// [scale] — сколько точек кадра на один модуль кода, [invert] — светлый код
  /// на тёмном фоне, [bytesPerPixel] — 1 у YUV420, 4 у BGRA.
  Uint8List frameWithQr(
    String data, {
    int frameW = 640,
    int frameH = 480,
    int scale = 4,
    int rowPadding = 64,
    bool invert = false,
    int bytesPerPixel = 1,
    int background = 255,
    int offsetX = 0,
    int offsetY = 0,
  }) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final image = QrImage(qr);
    final modules = qr.moduleCount;

    final bytesPerRow = frameW * bytesPerPixel + rowPadding;
    final bytes = Uint8List(bytesPerRow * frameH);
    // Фон кадра: код лежит на светлом, всё остальное поле — тоже светлое,
    // иначе бинаризатор увидит рамку и примет её за часть кода.
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = invert ? 0 : background;
    }

    final size = modules * scale;
    final left = (frameW - size) ~/ 2 + offsetX;
    final top = (frameH - size) ~/ 2 + offsetY;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        final dark = image.isDark(row, col);
        final value = invert ? (dark ? 255 : 0) : (dark ? 0 : background);
        for (var dy = 0; dy < scale; dy++) {
          final y = top + row * scale + dy;
          for (var dx = 0; dx < scale; dx++) {
            final x = left + col * scale + dx;
            bytes[y * bytesPerRow + x * bytesPerPixel] = value;
          }
        }
      }
    }
    return bytes;
  }

  String? decodeFrame(
    Uint8List bytes, {
    int frameW = 640,
    int frameH = 480,
    int rowPadding = 64,
    int bytesPerPixel = 1,
  }) =>
      decoder.decode(
        bytes: bytes,
        bytesPerRow: frameW * bytesPerPixel + rowPadding,
        width: frameW,
        height: frameH,
        bytesPerPixel: bytesPerPixel,
      );

  test('шестизначный код читается из кадра камеры', () {
    final bytes = frameWithQr('AB12CD');
    expect(decodeFrame(bytes), 'AB12CD');
  });

  test('ссылка-приглашение читается целиком', () {
    const link = 'https://togetherly.day/invite/AB12CD';
    final bytes = frameWithQr(link, scale: 3);
    expect(decodeFrame(bytes), link);
  });

  test('код читается и с кадра BGRA — это путь iOS', () {
    final bytes = frameWithQr('AB12CD', bytesPerPixel: 4);
    expect(decodeFrame(bytes, bytesPerPixel: 4), 'AB12CD');
  });

  test('крупный кадр прореживается, но код остаётся читаемым', () {
    // 1080×1080 — то, что реально приходит с ResolutionPreset.high. Внутри
    // декодера сторона ужимается до 320: проверяем, что код это переживает.
    final bytes = frameWithQr(
      'AB12CD',
      frameW: 1440,
      frameH: 1080,
      scale: 8,
      rowPadding: 96,
    );
    final code = decoder.decode(
      bytes: bytes,
      bytesPerRow: 1440 + 96,
      width: 1440,
      height: 1080,
    );
    expect(code, 'AB12CD');
  });

  test('код мимо рамки не читается, а в рамке — читается', () {
    // Код уехал к левому краю кадра, за пределы окна наведения. Человек видит
    // его вне рамки — и сканер обязан вести себя так же, иначе рамка врёт.
    final bytes = frameWithQr('AB12CD', offsetX: -170);
    expect(decodeFrame(bytes), isNull);

    // Тот же кадр целиком, без окна: код на месте и читается. Значит дело
    // именно в обрезке, а не в испорченной картинке.
    expect(
      decoder.decode(
        bytes: bytes,
        bytesPerRow: 640 + 64,
        width: 640,
        height: 480,
        windowFraction: 1.0,
      ),
      'AB12CD',
    );
  });

  test('пустой кадр не выдаёт ложный код', () {
    final bytes = Uint8List(704 * 480)..fillRange(0, 704 * 480, 255);
    expect(decodeFrame(bytes), isNull);
  });

  test('шум не выдаёт ложный код', () {
    final bytes = Uint8List(704 * 480);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i * 7919) % 256;
    }
    expect(decodeFrame(bytes), isNull);
  });

  test('серый фон вместо белого не мешает', () {
    final bytes = frameWithQr('AB12CD', background: 170);
    expect(decodeFrame(bytes), 'AB12CD');
  });
}
