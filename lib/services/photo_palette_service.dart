import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../models/photo_seed.dart';

/// Во сколько точек ужимается снимок перед разбором.
///
/// Больше не нужно: цвета кадра от разрешения не зависят, а полный снимок с
/// камеры (4000 точек по длинной стороне) — это шестнадцать миллионов пикселей
/// в квантователе и секунды ожидания на слабом телефоне.
const int _kSampleSide = 128;

/// Сколько разных цветов оставляет квантователь. Дальше ряд всё равно сожмёт
/// [pickSeedCandidates], убрав неразличимые оттенки.
const int _kQuantizeTo = 24;

/// Заметные цвета кадра по его точкам.
///
/// Прозрачные точки пропускаются: PNG со срезанным фоном иначе отдал бы в
/// главные цвета пустоту.
Future<List<SeedCandidate>> candidatesFromPixels(Uint32List argb) async {
  if (argb.isEmpty) return const [];
  final opaque = Uint32List.fromList(
      argb.where((p) => (p >> 24) & 0xFF == 0xFF).toList(growable: false));
  if (opaque.isEmpty) return const [];
  final result = await QuantizerCelebi().quantize(opaque, _kQuantizeTo);
  final out = <SeedCandidate>[];
  result.colorToCount.forEach((color, count) {
    out.add(SeedCandidate(Color(color), count));
  });
  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out;
}

/// Цвета, из которых человек выберет свою тему, прямо из файла снимка.
///
/// Декодирование идёт средствами движка с уменьшением на лету
/// (`targetWidth`), поэтому полный кадр в память не разворачивается.
Future<List<Color>> seedColorsFromImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: _kSampleSide, targetHeight: _kSampleSide);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return const [];
    return pickSeedCandidates(await candidatesFromPixels(_argbFromRgba(data)));
  } catch (e) {
    debugPrint('seedColorsFromImage failed: $e');
    return const [];
  }
}

/// Движок отдаёт точки как RGBA по байту на канал, квантователю нужен ARGB
/// одним числом.
Uint32List _argbFromRgba(ByteData data) {
  final bytes = data.buffer.asUint8List();
  final out = Uint32List(bytes.length ~/ 4);
  for (var i = 0; i < out.length; i++) {
    final o = i * 4;
    out[i] = (bytes[o + 3] << 24) |
        (bytes[o] << 16) |
        (bytes[o + 1] << 8) |
        bytes[o + 2];
  }
  return out;
}
