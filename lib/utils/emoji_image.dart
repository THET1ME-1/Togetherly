import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Эмодзи → картинка настроения.
///
/// Своё настроение хранится картинкой, а не символом: так оно работает везде,
/// где работают встроенные — в сетке выбора, в календаре, на виджете рабочего
/// стола (нативная разметка рисует файл, а не текст) и у партнёра со сборкой
/// постарше, которая про свои настроения ещё не знает.
///
/// Размер 512 — тот же, что у картинок каталожных паков.
Future<Uint8List> renderEmojiPng(String emoji, {int size = 512}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final side = size.toDouble();

  final painter = TextPainter(
    text: TextSpan(
      text: emoji,
      // Кегль чуть меньше стороны: у эмодзи есть собственные поля, и на полной
      // высоте символ упирается в края квадрата.
      style: TextStyle(fontSize: side * 0.78),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: side);

  painter.paint(
    canvas,
    Offset((side - painter.width) / 2, (side - painter.height) / 2),
  );

  final image = await recorder.endRecording().toImage(size, size);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
