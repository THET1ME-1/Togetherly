import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/snow_fall.dart';

/// Снегопад темы «Новый год»: хлопья в три глубины и изредка снежки, которые
/// ловят касанием пустого места и бросают партнёру.
void main() {
  const screen = Size(360, 780);

  test('хлопья в три глубины: дальние мельче и медленнее ближних', () {
    final f = snowFlakes();
    expect(f.length, greaterThanOrEqualTo(30));
    final far = f.where((x) => x.depth == 0), near = f.where((x) => x.depth == 2);
    expect(far, isNotEmpty);
    expect(near, isNotEmpty);
    expect(far.map((x) => x.radius).reduce((a, b) => a > b ? a : b),
        lessThan(near.map((x) => x.radius).reduce((a, b) => a < b ? a : b)));
    expect(far.map((x) => x.speed).reduce((a, b) => a > b ? a : b),
        lessThan(near.map((x) => x.speed).reduce((a, b) => a < b ? a : b)));
  });

  test('хлопья всегда внутри экрана по высоте и не скачут между кадрами', () {
    for (final f in snowFlakes()) {
      for (var s = 0.0; s < 120; s += 0.5) {
        final a = flakePosition(f, screen, s), b = flakePosition(f, screen, s + 1 / 60);
        expect(a.dy, inInclusiveRange(-12, screen.height + 12));
        // за кадр — мелкий сдвиг, кроме перескока сверху вниз на краю
        if ((b.dy - a.dy).abs() < screen.height / 2) {
          expect((b - a).distance, lessThan(3));
        }
      }
    }
  });

  test('снежков на экране не больше двух, и они появляются регулярно', () {
    var seen = <int>{};
    for (var s = 0.0; s < 120; s += 0.25) {
      final balls = snowballsAt(screen, s, const {});
      expect(balls.length, lessThanOrEqualTo(2), reason: 'на $s с');
      seen.addAll(balls.map((b) => b.id));
    }
    expect(seen.length, greaterThanOrEqualTo(6), reason: 'за две минуты — хотя бы шесть снежков');
  });

  test('касание по снежку ловит его, мимо — нет', () {
    final s = _momentWithBall(screen);
    final ball = snowballsAt(screen, s, const {}).first;
    expect(snowballHit(snowballsAt(screen, s, const {}), ball.at + const Offset(10, -10)), ball.id);
    expect(snowballHit(snowballsAt(screen, s, const {}), ball.at + const Offset(90, 0)), isNull);
  });

  test('радиус касания не меньше 24 точек, даже у мелкого снежка', () {
    final s = _momentWithBall(screen);
    final ball = snowballsAt(screen, s, const {}).first;
    expect(snowballHit([ball], ball.at + const Offset(23, 0)), ball.id);
  });

  test('пойманный снежок больше не падает', () {
    final s = _momentWithBall(screen);
    final ball = snowballsAt(screen, s, const {}).first;
    expect(snowballsAt(screen, s, {ball.id}).any((b) => b.id == ball.id), isFalse);
    expect(snowballsAt(screen, s + 1, {ball.id}).any((b) => b.id == ball.id), isFalse);
  });
}

double _momentWithBall(Size screen) {
  for (var s = 0.0; s < 60; s += 0.25) {
    final b = snowballsAt(screen, s, const {});
    if (b.isNotEmpty && b.first.at.dy > 100 && b.first.at.dy < screen.height - 100) return s;
  }
  throw StateError('снежка нет за минуту');
}
