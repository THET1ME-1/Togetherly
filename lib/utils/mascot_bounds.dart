import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Держит маскота в пределах экрана.
///
/// Прямой `clamp(half, width - half)` падает с «Invalid argument(s): 65.0», как
/// только экран оказывается у́же двух радиусов — а так бывает не только на
/// узких телефонах: в момент, когда виджет уже смонтирован, а размер ещё не
/// известен, `MediaQuery` отдаёт нули, и нижняя граница становится больше
/// верхней. Падало это на живой сборке.
///
/// В таком случае позицию не трогаем: маскот встанет на место следующим
/// пересчётом, когда размер станет настоящим.
///
/// [top] и [bottom] — полосы, куда маскоту нельзя: строка состояния сверху,
/// нижняя панель с безопасным полем снизу. Под панелью маскота не взять,
/// касание забирает она (TOG-15, обращение 411).
Offset clampMascotPosition(
  Offset position,
  Size screen,
  double half, {
  double top = 0,
  double bottom = 0,
}) {
  if (half <= 0) return position;
  final minY = top + half;
  final maxY = screen.height - bottom - half;
  if (screen.width <= half * 2 || maxY <= minY) return position;
  return Offset(
    position.dx.clamp(half, screen.width - half),
    position.dy.clamp(minY, maxY),
  );
}

/// Тап это был или перетаскивание.
///
/// Жест по маскоту разбирает `onScale*`: распознаватель масштаба забирает
/// касание себе на первом же микродвижении пальца, поэтому `onTap` у
/// `GestureDetector` до арены не доживал — маскот таскался, но не открывал
/// ничего (жалоба 13 августа 2026). Решение простое: короткое касание, за
/// которое палец почти не сдвинулся, считаем тапом сами.
bool mascotGestureIsTap({
  required double travel,
  required Duration held,
  double slop = 12,
  Duration limit = const Duration(milliseconds: 400),
}) =>
    travel <= slop && held < limit;

/// Тапы дальше друг от друга, чем это, — уже не одна серия. Считается между
/// отпусканиями пальца: Android даёт двойному тапу до 0,3 с от отпускания до
/// следующего касания, плюс сам прижатый палец — с 0,35 с живой двойной тап
/// распадался на два одиночных, и кувырка не было.
const Duration kMascotTapChain = Duration(milliseconds: 450);

/// На каком тапе серии Ту лопается.
const int kMascotBurstTap = 10;

/// Что делать прямо на тапе серии.
enum MascotTapStep { wait, feed, burst }

/// Чем кончилась серия, когда тапы прекратились.
enum MascotTapEnd { none, menu, flip, deflate }

/// Серия тапов по Ту: один — меню, два — кувырок, с третьего подряд Ту
/// раздувается, на десятом лопается на облачка и собирается обратно. Бросили
/// тапать посреди — сдувается.
class MascotTapCombo {
  int _count = 0;
  DateTime? _last;

  /// Насколько Ту раздуло: 0 — обычный, 1 — вот-вот лопнет.
  double get fed => _count < 3 ? 0 : (_count - 2) / (kMascotBurstTap - 2);

  MascotTapStep tap(DateTime now) {
    final last = _last;
    // Одно касание приходит и тапом, и концом жеста — это не второй тап.
    if (last != null && now.difference(last) < const Duration(milliseconds: 40)) return MascotTapStep.wait;
    _count = last != null && now.difference(last) <= kMascotTapChain ? _count + 1 : 1;
    _last = now;
    if (_count >= kMascotBurstTap) {
      _count = 0;
      _last = null;
      return MascotTapStep.burst;
    }
    return _count >= 3 ? MascotTapStep.feed : MascotTapStep.wait;
  }

  /// Тапы прекратились: что показать и с чистого листа.
  MascotTapEnd settle() {
    final count = _count;
    _count = 0;
    _last = null;
    return switch (count) {
      0 => MascotTapEnd.none,
      1 => MascotTapEnd.menu,
      2 => MascotTapEnd.flip,
      _ => MascotTapEnd.deflate,
    };
  }
}

/// Бросок стоит полёта: отпустили на ходу, а не просто разжали палец.
bool mascotFlingWorth(Offset velocity) => velocity.distance > 700;

/// Шаг полёта Ту после броска: летит по инерции, тормозит, о края [box]
/// (где может стоять его середина) отскакивает и теряет скорость.
///
/// [wall] — о какие стены удар: −1 левая или верхняя, 1 правая или нижняя,
/// 0 — не было. По диагонали в стену бьётся одна ось, в угол — обе.
({Offset position, Offset velocity, bool hit, Offset wall}) mascotFlightStep(
  Offset position,
  Offset velocity,
  double dt,
  Rect box, {
  double friction = 2.4,
  double bounce = 0.55,
}) {
  var x = position.dx + velocity.dx * dt;
  var y = position.dy + velocity.dy * dt;
  var vx = velocity.dx, vy = velocity.dy;
  var wx = 0.0, wy = 0.0;
  if (x < box.left || x > box.right) {
    wx = x < box.left ? -1 : 1;
    x = x.clamp(box.left, box.right);
    vx = -vx * bounce;
  }
  if (y < box.top || y > box.bottom) {
    wy = y < box.top ? -1 : 1;
    y = y.clamp(box.top, box.bottom);
    vy = -vy * bounce;
  }
  final slow = 1 / (1 + friction * dt);
  return (
    position: Offset(x, y),
    velocity: Offset(vx * slow, vy * slow),
    hit: wx != 0 || wy != 0,
    wall: Offset(wx, wy),
  );
}

/// Форма Ту после удара о стену: [flat] — вдоль удара, [wide] — поперёк.
/// В миг удара сплющен почти вдвое, потом пружинит с колыханием и за
/// полсекунды успокаивается. [strength] 0..1 — сила удара.
({double flat, double wide}) mascotSquash({required double sinceHit, required double strength}) {
  if (sinceHit < 0 || strength <= 0) return (flat: 1.0, wide: 1.0);
  final wobble = math.exp(-sinceHit * 9) * math.cos(sinceHit * 26);
  final k = strength.clamp(0.0, 1.0);
  return (flat: 1 - 0.45 * k * wobble, wide: 1 + 0.28 * k * wobble);
}
