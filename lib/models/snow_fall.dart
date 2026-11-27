import 'dart:math' as math;
import 'dart:ui';

/// Снегопад темы «Новый год» (макет 27.11.2026): хлопья в три глубины и
/// изредка снежки. Всё считается от времени, без состояния: где хлопок или
/// снежок в момент [seconds], знает чистая функция, поэтому кадры не копят
/// ошибку и петля не рвётся.

/// Один хлопок: доля ширины, глубина (0 — дальний, 2 — ближний), радиус,
/// скорость падения в точках за секунду, размах и период покачивания, сдвиг
/// по времени, прозрачность.
class SnowFlake {
  const SnowFlake({
    required this.x,
    required this.depth,
    required this.radius,
    required this.speed,
    required this.sway,
    required this.period,
    required this.phase,
    required this.alpha,
  });

  final double x, radius, speed, sway, period, phase, alpha;
  final int depth;
}

/// Хлопья снегопада. Числа — из макета: 18 дальних, 16 средних, 10 ближних.
List<SnowFlake> snowFlakes({int seed = 7}) {
  final r = math.Random(seed);
  double between(double a, double b) => a + r.nextDouble() * (b - a);
  const depths = [
    (count: 18, r0: 1.1, r1: 1.7, alpha: 0.55, v0: 16.0, v1: 24.0),
    (count: 16, r0: 2.0, r1: 2.9, alpha: 0.8, v0: 28.0, v1: 38.0),
    (count: 10, r0: 3.4, r1: 4.6, alpha: 0.95, v0: 42.0, v1: 56.0),
  ];
  return [
    for (var d = 0; d < depths.length; d++)
      for (var i = 0; i < depths[d].count; i++)
        SnowFlake(
          x: r.nextDouble(),
          depth: d,
          radius: between(depths[d].r0, depths[d].r1),
          speed: between(depths[d].v0, depths[d].v1),
          sway: between(6, 16),
          period: between(3, 6),
          phase: r.nextDouble(),
          alpha: depths[d].alpha,
        ),
  ];
}

/// Где хлопок в момент [seconds] на экране [size]: выходит из-за верхнего
/// края, уходит за нижний и начинает заново, по пути покачивается.
Offset flakePosition(SnowFlake f, Size size, double seconds) {
  final span = size.height + 20;
  final y = (f.phase * span + seconds * f.speed) % span - 10;
  final x = f.x * size.width + f.sway * math.sin(2 * math.pi * (seconds / f.period + f.phase));
  return Offset(x, y);
}

/// Снежок на экране: номер (по нему его ловят и помнят пойманным), центр и
/// радиус.
class Snowball {
  const Snowball(this.id, this.at, this.radius, this.turn);

  final int id;
  final Offset at;
  final double radius;

  /// Поворот, радианы: снежок медленно крутится в полёте.
  final double turn;
}

/// Новый снежок раз в [kSnowballEvery] секунд со сдвигом до трёх секунд;
/// падает медленнее ближних хлопьев.
const double kSnowballEvery = 9;
const double _ballSpeed = 38;

/// Детерминированный «случай» снежка [id]: одинаковый от кадра к кадру.
double _rand(int id, int salt) {
  final v = math.sin(id * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// Снежки в момент [seconds]: не больше двух разом, пойманные ([caught])
/// больше не падают.
List<Snowball> snowballsAt(Size size, double seconds, Set<int> caught) {
  final fall = (size.height + 80) / _ballSpeed;
  final out = <Snowball>[];
  final last = (seconds / kSnowballEvery).floor();
  for (var id = last; id >= 0 && out.length < 2; id--) {
    final born = id * kSnowballEvery + 3 * _rand(id, 1);
    final age = seconds - born;
    if (age < 0) continue;
    if (age > fall) break;
    if (caught.contains(id)) continue;
    final radius = 15 + 3 * _rand(id, 2);
    final x = size.width * (0.14 + 0.72 * _rand(id, 3)) + 10 * math.sin(age * 1.1 + 6 * _rand(id, 4));
    out.add(Snowball(id, Offset(x, -40 + age * _ballSpeed), radius, age * 0.4 + 6 * _rand(id, 5)));
  }
  return out;
}

/// Какой снежок под пальцем [point]: ближайший в радиусе не меньше 24
/// точек (мелкий снежок иначе не поймать), иначе null.
int? snowballHit(List<Snowball> balls, Offset point) {
  Snowball? best;
  var bestDist = double.infinity;
  for (final b in balls) {
    final d = (b.at - point).distance;
    if (d <= math.max(24, b.radius + 8) && d < bestDist) {
      best = b;
      bestDist = d;
    }
  }
  return best?.id;
}
