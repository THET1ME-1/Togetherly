import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Геометрия 2,5D-ёлки пары — порт `xmas_tree3d.js` из мастерской
/// (`~/Projects/GitHub/togetherly-badges-hand`). Картинки ёлки запечены оттуда
/// же, поэтому числа обязаны совпадать до знака: тест сверяет порт с эталоном,
/// снятым из JS (`test/fixtures/xmas_tree_geometry.json`).
///
/// Единицы — холст ёлки −8…108 (116 единиц на сторону картинки). Ярус — юбка
/// вокруг ствола: угол `th` вокруг оси и доля склона `u` (0 — верхушка яруса,
/// 1 — край лап). Игрушка висит в точке на хвое, а не на экране: так она
/// остаётся на ветке, где её повесили.

const double kXtPitch = -0.22;
const double kXtYaw = -0.32;
const int _ns = 52;

/// Ярусы [верх, низ, радиус, число лап] сверху вниз: индекс 0 — верхний ярус
/// (как в JS).
const Map<String, List<List<double>>> _tiers = {
  'fir': [[4, 26, 15, 7], [15, 41, 23, 9], [28, 57, 31, 11], [42, 74, 39, 13]],
  'snowy': [[4, 26, 15, 7], [15, 41, 23, 9], [28, 57, 31, 11], [42, 74, 39, 13]],
};

List<List<double>> xtTiers(String kind) => _tiers[kind] ?? _tiers['fir']!;

typedef _V = List<double>;

_V _sub(_V a, _V b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
_V _add(_V a, _V b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
_V _mul(_V a, double k) => [a[0] * k, a[1] * k, a[2] * k];
double _dot(_V a, _V b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
_V _cross(_V a, _V b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
_V _norm(_V a) {
  final l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  final d = l == 0 ? 1.0 : l;
  return [a[0] / d, a[1] / d, a[2] / d];
}

/// Камера: поворот вокруг оси ёлки, взгляд сверху, лёгкая перспектива.
class XtCam {
  XtCam(double yaw)
      : _c = math.cos(yaw),
        _s = math.sin(yaw),
        _cp = math.cos(kXtPitch),
        _sp = math.sin(kXtPitch);

  final double _c, _s, _cp, _sp;

  /// Точка модели → [x, y, глубина] на холсте ёлки.
  _V project(_V p) {
    final x1 = p[0] * _c + p[2] * _s, z1 = -p[0] * _s + p[2] * _c, y0 = p[1] - 56;
    final y2 = y0 * _cp - z1 * _sp, z2 = y0 * _sp + z1 * _cp, k = 280 / (280 - z2);
    return [50 + x1 * k * 0.9, 57 + y2 * k * 0.9, z2];
  }

  /// Направление на зрителя в координатах модели.
  _V get view => [-_s * _cp, _sp, _c * _cp];
}

class XtTier {
  XtTier(List<double> t)
      : top = t[0],
        bot = t[1],
        r = t[2],
        lobes = t[3];

  final double top, bot, r, lobes;

  /// 1 — кончик лапы, 0 — ложбинка.
  double lobe(double th) => math.pow((math.sin(th * lobes / 2)).abs(), 0.55).toDouble();

  _V p(double th, double u) {
    final f = lobe(th);
    final rim = r * (0.78 + 0.22 * f), yb = bot + 4.2 * f;
    final rr = rim * u * (1 + 0.22 * (1 - u));
    final y = top + (yb - top) * (u * u * 0.35 + u * 0.65);
    return [rr * math.cos(th), y, rr * math.sin(th)];
  }

  _V n(double th, double u) {
    const e = 0.01;
    final a = p(th - e, u), b = p(th + e, u), c = p(th, math.max(0.02, u - e)), d = p(th, math.min(1, u + e));
    var v = _norm(_cross(_sub(b, a), _sub(d, c)));
    if (_dot(v, [math.cos(th), 0, math.sin(th)]) < 0) v = _mul(v, -1);
    return v;
  }
}

/// Силуэт яруса на холсте: верхушка и передний край лап (с полосой толщины).
List<List<double>> _silhouette(XtTier t, XtCam cam) {
  final band = 2.2 + t.r * 0.03;
  final ring = <_V>[];
  for (var i = 0; i < _ns; i++) {
    final th = i / _ns * math.pi * 2;
    ring.add(cam.project(_add(t.p(th, 1), [0, band, 0])));
  }
  final apex = cam.project(t.p(0, 0));
  var iL = 0, iR = 0;
  for (var i = 0; i < ring.length; i++) {
    if (ring[i][0] < ring[iL][0]) iL = i;
    if (ring[i][0] > ring[iR][0]) iR = i;
  }
  List<int> walk(int dir) {
    final out = <int>[];
    for (var i = iL;; i = (i + dir + _ns) % _ns) {
      out.add(i);
      if (i == iR) break;
    }
    return out;
  }

  double zAvg(List<int> ix) => ix.fold<double>(0, (s, i) => s + ring[i][2]) / ix.length;
  final a = walk(1), b = walk(-1);
  final front = zAvg(a) > zAvg(b) ? a : b;
  return [apex, for (final i in front) ring[i]];
}

bool _inside(double x, double y, List<List<double>> poly) {
  var c = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i][0], yi = poly[i][1], xj = poly[j][0], yj = poly[j][1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
  }
  return c;
}

/// Можно ли повесить игрушку в точку (x, y) холста: точка лежит на хвое, а
/// не на горшке, звезде или в воздухе, и не у самой макушки.
bool xtCanHang(String kind, double x, double y, {double yaw = kXtYaw}) {
  final tiers = xtTiers(kind);
  final cam = XtCam(yaw);
  if (!(y > tiers[0][0] + 6)) return false;
  for (final t in tiers) {
    if (_inside(x, y, _silhouette(XtTier(t), cam))) return true;
  }
  return false;
}

/// Место игрушки на хвое: ярус (0 — верхний), угол и доля склона.
class XtAnchor {
  const XtAnchor(this.tier, this.th, this.u);
  final int tier;
  final double th;
  final double u;
}

/// Где игрушка висит на картинке ёлки.
class XtHang {
  const XtHang({required this.screen, required this.depth, required this.visible, required this.tier});

  /// Точка подвеса на холсте ёлки −8…108.
  final Offset screen;
  final double depth;

  /// Насколько хвоя в этой точке смотрит на зрителя: меньше нуля — за ёлкой.
  final double visible;
  final int tier;

  /// Масштаб игрушки от её холста 100: ближе к зрителю — чуть крупнее.
  double get scale => 0.15 * (280 / (280 - depth));
}

/// Точка холста → место на хвое. Верхний ярус лежит поверх нижних, поэтому
/// ярусы проверяются сверху вниз. Точку мимо хвои (игрушку, повешенную на
/// старую ёлку) притягивает ближайшая ветка не дальше 20 единиц.
XtAnchor? xtAnchor(String kind, double x, double y) {
  final key = '$kind|$x|$y';
  final hit = _anchors[key];
  if (hit != null || _anchors.containsKey(key)) return hit;
  final a = _findAnchor(kind, x, y);
  if (_anchors.length > 2000) _anchors.clear();
  _anchors[key] = a;
  return a;
}

final Map<String, XtAnchor?> _anchors = {};

/// Точка (x, y) ёлки, повёрнутой на [yaw], → та же точка хвои при обычном
/// повороте: место игрушки хранится в обычном повороте, а палец касается
/// качающейся ёлки. Точка мимо хвои остаётся как есть.
Offset xtUnsway(String kind, double x, double y, double yaw) {
  if (yaw == kXtYaw) return Offset(x, y);
  final a = _findAnchor(kind, x, y, yaw);
  if (a == null) return Offset(x, y);
  final s = XtCam(kXtYaw).project(XtTier(xtTiers(kind)[a.tier]).p(a.th, a.u));
  return Offset(s[0], s[1]);
}

XtAnchor? _findAnchor(String kind, double x, double y, [double yaw = kXtYaw]) {
  final tiers = xtTiers(kind);
  final cam = XtCam(yaw), v = cam.view;
  for (var i = 0; i < tiers.length; i++) {
    final t = XtTier(tiers[i]);
    if (!_inside(x, y, _silhouette(t, cam))) continue;
    XtAnchor? best;
    var bd = 1e9;
    for (var a = 0; a < 96; a++) {
      final th = a / 96 * math.pi * 2;
      for (var k = 2; k <= 40; k++) {
        final u = k / 40;
        if (_dot(t.n(th, u), v) < 0) continue;
        final s = cam.project(t.p(th, u));
        final d = (s[0] - x) * (s[0] - x) + (s[1] - y) * (s[1] - y);
        if (d < bd) {
          bd = d;
          best = XtAnchor(i, th, u);
        }
      }
    }
    if (best != null) return best;
  }
  XtAnchor? best;
  var bd = 1e9;
  for (var i = 0; i < tiers.length; i++) {
    final t = XtTier(tiers[i]);
    for (var a = 0; a < 72; a++) {
      final th = a / 72 * math.pi * 2;
      for (var k = 12; k <= 40; k += 2) {
        final u = k / 40;
        if (_dot(t.n(th, u), v) < 0.2) continue;
        final s = cam.project(t.p(th, u));
        final d = (s[0] - x) * (s[0] - x) + (s[1] - y) * (s[1] - y);
        if (d < bd) {
          bd = d;
          best = XtAnchor(i, th, u);
        }
      }
    }
  }
  return bd < 400 ? best : null;
}

/// Точка подвеса игрушки на картинке ёлки (чуть над хвоей, по нормали).
XtHang xtHangPoint(String kind, XtAnchor a, {double yaw = kXtYaw}) {
  final t = XtTier(xtTiers(kind)[a.tier]);
  final cam = XtCam(yaw);
  final n = t.n(a.th, a.u);
  final s = cam.project(_add(t.p(a.th, a.u), _mul(n, 0.8)));
  return XtHang(screen: Offset(s[0], s[1]), depth: s[2], visible: _dot(n, cam.view), tier: a.tier);
}
