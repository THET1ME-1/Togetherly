import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/together_track_spec.dart';

/// Раскладка виджета «Вместе» живёт в трёх местах — Kotlin, Swift и превью
/// каталога. Расхождение видно только на устройстве: в приложении одно, на
/// рабочем столе другое. Поэтому числа сверяются по исходникам.
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/togetherly/love/WidgetImages.kt',
  ).readAsStringSync();
  final swift =
      File('ios/TogetherlyWidget/TogetherWidget.swift').readAsStringSync();

  group('растр', () {
    test('левый верх остаётся чистым — там число', () {
      final dots = togetherHalftoneDots(const Size(338, 158));
      expect(dots, isNotEmpty);
      final near = dots.where((d) => d.center.dx < 40 && d.center.dy < 40);
      expect(near, isEmpty, reason: 'точки полезли под число');
    });

    test('к дальнему углу точки крупнее', () {
      final dots = togetherHalftoneDots(const Size(338, 338));
      final corner = dots.reduce((a, b) =>
          a.center.distance > b.center.distance ? a : b);
      expect(corner.radius, greaterThan(TogetherTrackSpec.dotMaxRadius * 0.6));
    });

    test('вырожденный размер не рушит расчёт', () {
      expect(togetherHalftoneDots(const Size(0, 0)), isEmpty);
      expect(togetherHalftoneDots(const Size(-10, 40)), isEmpty);
    });

    test('на маленькой ячейке растр остаётся, но редкий', () {
      final small = togetherHalftoneDots(const Size(140, 140));
      final big = togetherHalftoneDots(const Size(338, 338));
      expect(small, isNotEmpty);
      expect(small.length, lessThan(big.length));
    });
  });

  group('лента', () {
    test('отметки стоят в середине своих строк', () {
      expect(togetherColumnStops(4), [0.125, 0.375, 0.625, 0.875]);
      expect(togetherColumnStops(3), [1 / 6, 0.5, 5 / 6]);
    });
  });

  group('натив держит те же числа', () {
    test('растр', () {
      for (final src in [kotlin, swift]) {
        expect(src.contains('15'), isTrue);
        expect(src.contains('5.2'), isTrue,
            reason: 'радиус самой крупной точки разошёлся');
        expect(src.contains('0.18'), isTrue,
            reason: 'порог, с которого точки проявляются, разошёлся');
        expect(src.contains('0.55'), isTrue,
            reason: 'прозрачность точек разошлась');
      }
    });

    test('дорожка', () {
      for (final src in [kotlin, swift]) {
        expect(src.contains('9.5'), isTrue,
            reason: 'обводка сегодняшней отметки разошлась');
      }
    });
  });
}
