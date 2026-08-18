// Цвета из фотографии считает тот же квантователь, которым Android берёт
// палитру из обоев. Проверяем не сам квантователь, а нашу обвязку: что из
// снимка выходят настоящие цвета кадра, что редкая мелочь не вытесняет
// главное и что пустой кадр не роняет экран.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/photo_palette_service.dart';

Uint32List _pixels(Map<int, int> colorToCount) {
  final out = <int>[];
  colorToCount.forEach((color, count) {
    out.addAll(List.filled(count, color));
  });
  return Uint32List.fromList(out);
}

void main() {
  group('цвета кадра', () {
    test('главные цвета снимка попадают в кандидаты', () async {
      final found = await candidatesFromPixels(_pixels({
        0xFF1685A2: 700, // вода
        0xFFF0A81C: 300, // закат
      }));
      final colors = found.map((c) => c.color.toARGB32()).toList();
      expect(colors, contains(0xFF1685A2));
      expect(colors, contains(0xFFF0A81C));
    });

    test('заметность считается по площади на кадре', () async {
      final found = await candidatesFromPixels(_pixels({
        0xFF1685A2: 900,
        0xFFF0A81C: 100,
      }));
      final water = found.firstWhere((c) => c.color.toARGB32() == 0xFF1685A2);
      final sunset = found.firstWhere((c) => c.color.toARGB32() == 0xFFF0A81C);
      expect(water.weight, greaterThan(sunset.weight));
    });

    test('прозрачные точки не считаются за цвет', () async {
      final found = await candidatesFromPixels(_pixels({
        0x00000000: 900,
        0xFF1685A2: 100,
      }));
      expect(found, isNotEmpty);
      expect(found.map((c) => c.color.a), everyElement(1.0));
    });

    test('пустой кадр даёт пустой ответ', () async {
      expect(await candidatesFromPixels(Uint32List(0)), isEmpty);
    });
  });
}
