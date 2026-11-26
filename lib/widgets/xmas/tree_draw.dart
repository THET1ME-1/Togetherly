import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../models/xmas_tree_geometry.dart';

/// Рисунок 2,5D-ёлки — порт `xt3Tree` из мастерской
/// (`~/Projects/GitHub/togetherly-badges-hand/xmas_tree3d.js`). До 26.11.2026
/// ёлка шла запечёнными слоями одного кадра, и покачивание макета («ёлка чуть
/// покачивается, игрушки едут вместе с ней») в приложение не доехало. Теперь
/// ёлка рисуется здесь при любом повороте [yaw], и слои, и игрушки считаются
/// по одной и той же камере.
///
/// Слои те же, что у запекания: `base` (тень, горшок или сугроб, ствол),
/// `t3`…`t0` (ярусы снизу вверх, у каждого тень верхнего яруса на нём) и
/// `star` (звезда со стерженьком). Единицы — холст ёлки −8…108.
///
/// Правишь ёлку в мастерской — правь и здесь: числа обязаны совпадать.

const _ink = ui.Color(0xFF2A2D30);
const _ink2 = ui.Color(0xFF5D5F62);

const _needle = [ui.Color(0xFF5FB07F), ui.Color(0xFF3F8F66), ui.Color(0xFF2A6B4B)];
const _band = ui.Color(0xFF1D4D36);
const _shade = ui.Color(0xFF123A28);
const _fine = ui.Color(0xFF9AD8AD);
const _fineDark = ui.Color(0xFF4F9A72);
const _fineShadow = ui.Color(0xFF215A3E);
const _potCols = [ui.Color(0xFFEC5A50), ui.Color(0xFFD4403F), ui.Color(0xFFA92F35)];
const _lip = [ui.Color(0xFFFFF6EA), ui.Color(0xFFF3E4CF), ui.Color(0xFFDCC6A8)];
const _soil = ui.Color(0xFF5A3A26);
const _soilDark = ui.Color(0xFF3F2819);
const _trunk = [ui.Color(0xFFA06A3A), ui.Color(0xFF8D5A30), ui.Color(0xFF6A4020)];
const _gold = ui.Color(0xFFF6C94A);
const _goldSide = ui.Color(0xFFD29A28);
const _goldDark = ui.Color(0xFFA8741C);
const _snow = [ui.Color(0xFFFFFFFF), ui.Color(0xFFEEF4FB), ui.Color(0xFFC9D8EE)];
const _bulbs = [ui.Color(0xFFF6CF4A), ui.Color(0xFFEF5F7C), ui.Color(0xFF7FD3FF), ui.Color(0xFFFFFFFF), ui.Color(0xFF9BE3B7)];

const int _ns = 52;
const List<double> _us = [0.05, 0.3, 0.55, 0.78, 0.92, 1];

typedef _V = List<double>;

_V _add(_V a, _V b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
_V _mul(_V a, double k) => [a[0] * k, a[1] * k, a[2] * k];
_V _sub(_V a, _V b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
double _dot(_V a, _V b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
_V _norm(_V a) {
  final l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  final d = l == 0 ? 1.0 : l;
  return [a[0] / d, a[1] / d, a[2] / d];
}

final _V _light = _norm([-0.55, -0.75, 0.45]);

int _tone(_V n) {
  final d = _dot(n, _light);
  return d > 0.32 ? 0 : (d > -0.12 ? 1 : 2);
}

/// Дрожь руки: одна и та же грань дрожит одинаково при любом повороте.
double _noise(num n) {
  final x = math.sin(n * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

ui.Path _poly(List<_V> q) {
  final p = ui.Path()..moveTo(q[0][0], q[0][1]);
  for (var i = 1; i < q.length; i++) {
    p.lineTo(q[i][0], q[i][1]);
  }
  return p..close();
}

ui.Path _open(List<_V> q) {
  final p = ui.Path()..moveTo(q[0][0], q[0][1]);
  for (var i = 1; i < q.length; i++) {
    p.lineTo(q[i][0], q[i][1]);
  }
  return p;
}

ui.Paint _fillPaint(ui.Color c, [double opacity = 1]) => ui.Paint()
  ..isAntiAlias = true
  ..style = ui.PaintingStyle.fill
  ..color = opacity == 1 ? c : c.withValues(alpha: c.a * opacity);

ui.Paint _strokePaint(ui.Color c, double w, {double opacity = 1, bool roundCap = false, bool roundJoin = false}) => ui.Paint()
  ..isAntiAlias = true
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = roundCap ? ui.StrokeCap.round : ui.StrokeCap.butt
  ..strokeJoin = roundJoin ? ui.StrokeJoin.round : ui.StrokeJoin.miter
  ..color = opacity == 1 ? c : c.withValues(alpha: c.a * opacity);

/// Грань, залитая и обведённая своим же цветом (шов между гранями не светится).
class _Face {
  _Face(this.q, this.z, this.tone, [this.order = 0, this.m = 0, this.j = 0]);
  final List<_V> q;
  final double z;
  final int tone;
  final int order;
  final double m;
  final int j;
}

int _byDepth(_Face a, _Face b) {
  final c = a.z.compareTo(b.z);
  return c != 0 ? c : a.order.compareTo(b.order);
}

/// Слои ёлки при повороте [yaw]: имя слоя → запись рисунка в единицах холста.
class XtTreePictures {
  XtTreePictures._(this.layers);
  final Map<String, ui.Picture> layers;

  void dispose() {
    for (final p in layers.values) {
      p.dispose();
    }
  }
}

/// Готовые слои по повороту: качание проходит одни и те же углы по кругу,
/// поэтому каждый угол рисуется один раз.
final Map<String, XtTreePictures> _cache = {};

/// Шаг поворота, на который делится качание: 0,002 рад сдвигают край нижнего
/// яруса на сотую долю точки при ёлке во весь экран.
const double kXtYawStep = 0.002;

double xtQuantizeYaw(double yaw) => (yaw / kXtYawStep).roundToDouble() * kXtYawStep;

XtTreePictures xtTreePictures(String kind, double yaw, {required bool garland}) {
  final k = kind == 'snowy' ? 'snowy' : 'fir';
  final key = '$k|${garland ? 1 : 0}|${(yaw / kXtYawStep).round()}';
  final hit = _cache.remove(key);
  if (hit != null) return _cache[key] = hit;
  final made = _XtTreeDraw(k, yaw, garland).build();
  _cache[key] = made;
  // два стиля, гирлянда и все углы качания — около трёхсот наборов
  while (_cache.length > 320) {
    final old = _cache.keys.first;
    _cache.remove(old)!.dispose();
  }
  return made;
}

class _XtTreeDraw {
  _XtTreeDraw(this.kind, double yaw, this.garland)
      : cam = XtCam(yaw),
        tiers = xtTiers(kind);

  final String kind;
  final bool garland;
  final XtCam cam;
  final List<List<double>> tiers;
  int key = 0;

  late ui.PictureRecorder _rec;
  late ui.Canvas c;

  _V get view => cam.view;
  _V s(_V p) => cam.project(p);
  bool vis(_V n) => _dot(n, view) > 0.01;

  void _begin() {
    _rec = ui.PictureRecorder();
    c = ui.Canvas(_rec);
  }

  ui.Picture _end() => _rec.endRecording();

  /// Линия «от руки»: на каждом отрезке точка посередине сдвинута шумом.
  ui.Path hand(List<_V> pts, int k, double amp, {bool closed = true}) {
    final n = pts.length, last = closed ? n : n - 1;
    final out = <List<double>>[];
    for (var i = 0; i < last; i++) {
      final a = pts[i], b = pts[(i + 1) % n];
      for (var kk = 0; kk < 2; kk++) {
        final t = kk / 2, j = kk == 0 ? 0.0 : amp;
        out.add([
          a[0] + (b[0] - a[0]) * t + (_noise(k * 97 + i * 7 + kk) - 0.5) * 2 * j,
          a[1] + (b[1] - a[1]) * t + (_noise(k * 131 + i * 11 + kk) - 0.5) * 2 * j,
        ]);
      }
    }
    if (!closed) out.add(pts[n - 1]);
    final p = ui.Path()..moveTo(out[0][0], out[0][1]);
    for (var i = 1; i < out.length; i++) {
      p.lineTo(out[i][0], out[i][1]);
    }
    if (closed) p.close();
    return p;
  }

  void fill(List<_V> q, ui.Color col) {
    final p = _poly(q);
    c.drawPath(p, _fillPaint(col));
    c.drawPath(p, _strokePaint(col, 0.55, roundJoin: true));
  }

  /// Штриховка теневых граней: косые линии через весь холст, только внутри них.
  void hatch(List<List<_V>> polys, double op) {
    if (polys.isEmpty) return;
    final clip = ui.Path();
    for (final q in polys) {
      clip.addPath(_poly(q), ui.Offset.zero);
    }
    final lines = ui.Path();
    for (var t = -140.0; t < 140; t += 3.6) {
      lines
        ..moveTo(50 + t, -12)
        ..lineTo(50 + t - 70, 116);
    }
    c.save();
    c.clipPath(clip);
    c.drawPath(lines, _strokePaint(_ink2, 1.05, opacity: op, roundCap: true));
    c.restore();
  }

  void ink(List<_V> q, {double w = 1.6, bool closed = false, double amp = 0.22}) {
    c.drawPath(hand(q, ++key, amp, closed: closed), _strokePaint(_ink, w, roundCap: true, roundJoin: true));
  }

  /// Тело вращения по профилю `[[r, y], …]`: видимые полосы трёх тонов.
  void lathe(List<List<double>> prof, List<ui.Color> cols, {int ns = 40, bool noHatch = false}) {
    _V p(double th, double r, double y) => [r * math.cos(th), y, r * math.sin(th)];
    final faces = <_Face>[];
    for (var j = 0; j < prof.length - 1; j++) {
      final r0 = prof[j][0], y0 = prof[j][1], r1 = prof[j + 1][0], y1 = prof[j + 1][1];
      for (var i = 0; i < ns; i++) {
        final a = i / ns * math.pi * 2, b = (i + 1) / ns * math.pi * 2, m = (a + b) / 2;
        final n = _norm([math.cos(m) * (y1 - y0), -(r1 - r0), math.sin(m) * (y1 - y0)]);
        final nn = (y1 - y0) == 0 ? <double>[0, r1 < r0 ? -1 : 1, 0] : n;
        if (!vis(nn)) continue;
        final q = [p(a, r0, y0), p(b, r0, y0), p(b, r1, y1), p(a, r1, y1)].map(s).toList();
        faces.add(_Face(q, (q[0][2] + q[2][2]) / 2, _tone(nn), faces.length));
      }
    }
    faces.sort(_byDepth);
    final dark = <List<_V>>[];
    for (final f in faces) {
      fill(f.q, cols[f.tone]);
      if (f.tone == 2) dark.add(f.q);
    }
    if (!noHatch) hatch(dark, 0.36);
  }

  List<_V> ringPts(double r, double y, [double from = 0, double to = math.pi * 2, int n = 40]) => [
        for (var i = 0; i <= n; i++) s([r * math.cos(from + (to - from) * i / n), y, r * math.sin(from + (to - from) * i / n)]),
      ];

  /// Передняя (видимая) дуга кольца от левого края к правому.
  List<_V> frontArc(double r, double y) {
    final pts = ringPts(r, y, 0, math.pi * 2, 64).sublist(0, 64);
    var iL = 0, iR = 0;
    for (var i = 0; i < pts.length; i++) {
      if (pts[i][0] < pts[iL][0]) iL = i;
      if (pts[i][0] > pts[iR][0]) iR = i;
    }
    List<_V> walk(int d) {
      final o = <_V>[];
      for (var i = iL;; i = (i + d + 64) % 64) {
        o.add(pts[i]);
        if (i == iR) break;
      }
      return o;
    }

    double z(List<_V> q) => q.fold<double>(0, (a, p) => a + p[2]) / q.length;
    final a = walk(1), b = walk(-1);
    return z(a) > z(b) ? a : b;
  }

  void trunk() => lathe([[3.4, tiers.last[1] - 6], [3.6, 89]], _trunk, ns: 20);

  XtTreePictures build() {
    final layers = <String, ui.Picture>{};
    _begin();
    _floorShadow();
    if (kind == 'snowy') {
      _drift();
    } else {
      _pot();
    }
    layers['base'] = _end();

    final screens = [for (final t in tiers) _TierScreen(XtTier(t), cam)];
    for (var ti = tiers.length - 1; ti >= 0; ti--) {
      _begin();
      _tier(ti, screens);
      layers['t$ti'] = _end();
    }
    _begin();
    _star();
    layers['star'] = _end();
    return XtTreePictures._(layers);
  }

  void _floorShadow() {
    final sh = [
      for (var i = 0; i < 28; i++) s([22 * math.cos(i / 28 * math.pi * 2) + 3, 101.5, 14 * math.sin(i / 28 * math.pi * 2) + 2]),
    ];
    c.drawPath(_poly(sh), _fillPaint(const ui.Color(0xFF2A1A14), 0.22));
  }

  // сугроб: пологий купол, ствол уходит в снег
  void _drift() {
    trunk();
    const prof = [[5.0, 89.0], [12.0, 90.4], [18.0, 92.8], [23.0, 96.0], [26.5, 99.6], [27.5, 101.5]];
    lathe(prof, _snow, ns: 44);
    final arcs = [for (final p in prof) frontArc(p[0], p[1])];
    ink(arcs.last, w: 1.7);
    ink([for (final a in arcs.reversed) a.first], w: 1.5);
    ink([for (final a in arcs.reversed) a.last], w: 1.5);
    // голубые ложбинки снега спереди
    final thF = math.atan2(view[2], view[0]);
    for (final g in const [[-0.9, -0.35, 96.2], [0.25, 0.8, 95.6]]) {
      final d0 = g[0], d1 = g[1], y0 = g[2];
      final pts = <_V>[];
      for (var e = 0; e <= 6; e++) {
        final th = thF + d0 + (d1 - d0) * e / 6, y = y0 - 0.9 * math.sin(e / 6 * math.pi), r = 23.2 + (y0 - 96) * 0.6;
        pts.add(s([r * math.cos(th), y, r * math.sin(th)]));
      }
      c.drawPath(hand(pts, ++key, 0.12, closed: false), _strokePaint(const ui.Color(0xFFB9CBE6), 1.4, roundCap: true));
    }
  }

  // горшок: тело-усечённый конус, сливочный бортик с толщиной, земля внутри
  void _pot() {
    const yLip0 = 83.6, yLip1 = 88.6, yBot = 101.5, rLip = 18.4, rIn = 15.2, rTop = 16.6, rBot = 12.8, yM1 = 92.4, yM2 = 97.8;
    lathe([[rTop, yLip1], [rTop - 0.9, yM1], [rBot + 1.2, yM2], [rBot, yBot]], _potCols, ns: 44);
    final thF = math.atan2(view[2], view[0]);
    // сердечко на стенке, лицом к зрителю
    {
      const hy = 95.0, hs = 3.9;
      final h = <_V>[];
      for (var i = 0; i < 28; i++) {
        final a = i / 28 * math.pi * 2;
        final hx = 16 * math.pow(math.sin(a), 3);
        final hh = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a));
        final u = hx / 17 * hs, v = hh / 17 * hs, rr = rTop - 0.9 - (hy + v - yM1) / (yM2 - yM1) * 2.5 + 0.15;
        h.add(s([rr * math.cos(thF + u / rr), hy + v, rr * math.sin(thF + u / rr)]));
      }
      final p = hand(h, ++key, 0.12);
      c.drawPath(p, _fillPaint(const ui.Color(0xFFFFF3E2)));
      c.drawPath(p, _strokePaint(_ink, 1.1, roundJoin: true));
    }
    // блик слева на стенке
    {
      final th = thF - 0.75;
      final pts = [
        s([rTop * math.cos(th), 90.6, rTop * math.sin(th)]),
        s([(rTop - 1.6) * math.cos(th), 94.6, (rTop - 1.6) * math.sin(th)]),
        s([(rBot + 1.4) * math.cos(th), 98.8, (rBot + 1.4) * math.sin(th)]),
      ];
      c.drawPath(hand(pts, ++key, 0.1, closed: false), _strokePaint(const ui.Color(0xFFFFFFFF), 2, opacity: 0.7, roundCap: true));
    }
    // бортик: наружная стенка, верхнее кольцо, земля, ствол
    lathe([[rLip, yLip0], [rLip, yLip1]], _lip, ns: 44);
    for (var i = 0; i < 44; i++) {
      final a = i / 44 * math.pi * 2, b = (i + 1) / 44 * math.pi * 2;
      fill([
        [rLip * math.cos(a), yLip0, rLip * math.sin(a)],
        [rLip * math.cos(b), yLip0, rLip * math.sin(b)],
        [rIn * math.cos(b), yLip0, rIn * math.sin(b)],
        [rIn * math.cos(a), yLip0, rIn * math.sin(a)],
      ].map(s).toList(), _lip[0]);
    }
    c.drawPath(_poly(ringPts(rIn, yLip0 + 0.6, 0, math.pi * 2, 44)), _fillPaint(_soil));
    c.drawPath(_poly(ringPts(rIn, yLip0 + 0.6, math.pi * 0.95, math.pi * 2.05, 24)), _fillPaint(_soilDark, 0.6));
    trunk();
    // тушь горшка: кольца бортика, низ бортика спереди, бока и дно
    ink(ringPts(rLip, yLip0, 0, math.pi * 2, 48), closed: true, amp: 0.15);
    ink(ringPts(rIn, yLip0, 0, math.pi * 2, 40), w: 1.1, closed: true, amp: 0.12);
    final lipF = frontArc(rLip, yLip1), lipT = frontArc(rLip, yLip0), botF = frontArc(rBot, yBot);
    ink(lipF, w: 1.4);
    ink([lipT.first, lipF.first]);
    ink([lipT.last, lipF.last]);
    final mid1 = frontArc(rTop - 0.9, yM1), mid2 = frontArc(rBot + 1.2, yM2), topB = frontArc(rTop, yLip1);
    ink([topB.first, mid1.first, mid2.first, botF.first], w: 1.7);
    ink([topB.last, mid1.last, mid2.last, botF.last], w: 1.7);
    ink(botF, w: 1.8);
  }

  void _tier(int ti, List<_TierScreen> screens) {
    final sc = screens[ti], f = sc.tier;
    final faces = <_Face>[];
    for (var j = 0; j < _us.length - 1; j++) {
      for (var i = 0; i < _ns; i++) {
        final a = i / _ns * math.pi * 2, b = (i + 1) / _ns * math.pi * 2, m = (a + b) / 2, um = (_us[j] + _us[j + 1]) / 2;
        final n = f.n(m, um);
        if (!vis(n)) continue;
        final q = [f.p(a, _us[j]), f.p(b, _us[j]), f.p(b, _us[j + 1]), f.p(a, _us[j + 1])].map(s).toList();
        faces.add(_Face(q, q.fold<double>(0, (z, p) => z + p[2]) / 4, _tone(n), faces.length, m, j));
      }
    }
    // толщина края лап: тёмная полоса под краем, видна спереди
    for (var i = 0; i < _ns; i++) {
      final a = i / _ns * math.pi * 2, b = (i + 1) / _ns * math.pi * 2, m = (a + b) / 2;
      if (!vis([math.cos(m), 0.15, math.sin(m)])) continue;
      final pa = f.p(a, 1), pb = f.p(b, 1);
      fill([pa, pb, _add(pb, [0, sc.band, -0.3 * math.sin(b)]), _add(pa, [0, sc.band, -0.3 * math.sin(a)])].map(s).toList(), _band);
    }
    faces.sort(_byDepth);
    final dark = <List<_V>>[];
    for (final face in faces) {
      fill(face.q, _needle[face.tone]);
      if (face.tone == 2) dark.add(face.q);
    }
    hatch(dark, 0.42);
    // хвоя: короткие штрихи вниз по склону, со сдвигом от ряда к ряду
    for (final face in faces) {
      if (face.j < 1) continue;
      final k = (face.m / (math.pi * 2 / _ns)).round();
      if ((k + face.j) % 2 != 0) continue;
      final u0 = _us[face.j] + 0.02 + 0.05 * _noise(k * 7 + face.j * 3 + ti), u1 = math.min(0.99, u0 + 0.1);
      final p0 = s(f.p(face.m, u0)), p1 = s(f.p(face.m + 0.025, u1));
      final col = face.tone == 0 ? _fine : (face.tone == 1 ? _fineDark : _fineShadow);
      c.drawLine(ui.Offset(p0[0], p0[1]), ui.Offset(p1[0], p1[1]), _strokePaint(col, 1.2, opacity: 0.9, roundCap: true));
    }
    if (kind == 'snowy') _tierSnow(f);
    if (garland && ti > 0) _garland(ti, f);
    // тушь: край лап (низ полосы и шов над ней) и бока яруса
    final lower = [for (final i in sc.front) sc.ring[i]];
    ink(lower, w: 1.7, amp: 0.18);
    c.drawPath(
      _open([for (final i in sc.front) s(f.p(i / _ns * math.pi * 2, 1))]),
      _strokePaint(_ink, 0.8, opacity: 0.85, roundCap: true),
    );
    ink([lower.first, sc.apex], w: 1.7, amp: 0.25);
    ink([sc.apex, lower.last], w: 1.7, amp: 0.25);
    // тень верхнего яруса ложится на этот
    if (ti > 0) {
      final up = [for (final p in screens[ti - 1].sil) <double>[p[0] + 1.2, p[1] + 3.8, 0]];
      c.save();
      c.clipPath(_poly(sc.sil));
      c.drawPath(_poly(up), _fillPaint(_shade, 0.38));
      c.restore();
    }
  }

  // снег лежит подушкой по краю лап: на кончиках толще, в ложбинках тает
  void _tierSnow(XtTier f) {
    double top(double th) => 1 - 0.2 * math.pow(f.lobe(th), 1.4).toDouble() - 0.015;
    _V over(double th) => _add(f.p(th, 1), [0, 1.6 * f.lobe(th), 0]);
    const nss = _ns * 2;
    final cells = <List<_V>>[];
    final edgeTop = <_V?>[];
    for (var i = 0; i < nss; i++) {
      final a = i / nss * math.pi * 2, b = (i + 1) / nss * math.pi * 2, m = (a + b) / 2;
      if (!vis(f.n(m, 0.95)) || f.lobe(m) < 0.25) {
        edgeTop.add(null);
        continue;
      }
      cells.add([f.p(a, top(a)), f.p(b, top(b)), over(b), over(a)].map(s).toList());
      edgeTop.add(s(f.p(a, top(a))));
    }
    for (final q in cells) {
      fill(q, _snow[0]);
    }
    // верхняя кромка снега тонкой голубой линией, кусками по лапам
    var run = <_V>[];
    void flush() {
      if (run.length > 1) c.drawPath(_open(run), _strokePaint(const ui.Color(0xFF9FB6D8), 1.1, roundCap: true));
      run = [];
    }

    for (final p in edgeTop) {
      if (p != null) {
        run.add(p);
      } else {
        flush();
      }
    }
    flush();
  }

  // гирлянда: наклонное кольцо по нижней трети склона, видимая часть
  void _garland(int ti, XtTier f) {
    final ph = ti * 1.7;
    final pts = <(_V, _V)>[];
    for (var e = 0; e <= 96; e++) {
      final th = e / 96 * math.pi * 2, u = 0.82 + 0.07 * math.sin(th + ph);
      final n = f.n(th, u);
      pts.add((n, _add(f.p(th, u), _mul(n, 0.5))));
    }
    var run = <_V>[];
    void flush() {
      if (run.length > 1) c.drawPath(_open(run), _strokePaint(_ink, 1.25, roundCap: true));
      run = [];
    }

    for (final (n, p) in pts) {
      if (vis(n)) {
        run.add(s(p));
      } else {
        flush();
      }
    }
    flush();
    final nb = (f.r * 0.9).round();
    for (var e = 0; e < nb; e++) {
      final (n, p) = pts[(e / nb * 96).round() % 96];
      if (_dot(n, view) < 0.35) continue;
      final sp = s(_add(p, [0, 1.6, 0])), col = _bulbs[e % _bulbs.length];
      final at = ui.Offset(sp[0], sp[1]);
      c.drawCircle(at, 3.4, _fillPaint(col, 0.38));
      c.drawRRect(
        ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(sp[0] - 0.9, sp[1] - 2.6, 1.8, 1.4), const ui.Radius.circular(0.4)),
        _fillPaint(_ink),
      );
      final bulb = ui.Rect.fromCenter(center: at, width: 2.9, height: 3.8);
      c.drawOval(bulb, _fillPaint(col));
      c.drawOval(bulb, _strokePaint(_ink, 0.9));
    }
  }

  // звезда: выдавленная, смотрит вперёд, крутится вместе с ёлкой
  void _star() {
    final cy = tiers[0][0] - 6.8;
    const cR = 7.2, cr = 3.3, d = 1.4;
    final pts = [
      for (var i = 0; i < 10; i++)
        <double>[
          (i.isOdd ? cr : cR) * math.cos(-math.pi / 2 + i * math.pi / 5),
          cy + (i.isOdd ? cr : cR) * math.sin(-math.pi / 2 + i * math.pi / 5),
        ],
    ];
    final fr = [for (final p in pts) <double>[p[0], p[1], d]];
    final bk = [for (final p in pts) <double>[p[0], p[1], -d]];
    final sides = <_Face>[];
    for (var i = 0; i < 10; i++) {
      final j = (i + 1) % 10, e = _sub(fr[j], fr[i]), n = _norm([e[1], -e[0], 0]);
      if (!vis(n)) continue;
      final q = [fr[i], fr[j], bk[j], bk[i]].map(s).toList();
      sides.add(_Face(q, q.fold<double>(0, (z, p) => z + p[2]) / 4, _dot(n, _light) > 0 ? 0 : 1, sides.length));
    }
    sides.sort(_byDepth);
    // стерженёк к верхушке
    lathe([[1.1, cy + 4], [1.1, tiers[0][0] + 1.5]], const [_goldSide, _goldSide, _goldDark], ns: 10, noHatch: true);
    for (final f in sides) {
      final p = hand(f.q, ++key, 0.05);
      c.drawPath(p, _fillPaint(f.tone == 0 ? _goldSide : _goldDark));
      c.drawPath(p, _strokePaint(_ink, 1, roundJoin: true));
    }
    final face = hand((vis([0, 0, 1]) ? fr : bk).map(s).toList(), ++key, 0.12);
    c.drawPath(face, _fillPaint(_gold));
    c.drawPath(face, _strokePaint(_ink, 1.6, roundJoin: true));
    // грань-гребень: от центра к лучам, правая половина каждого луча темнее
    final cc = s([0, cy, d + 1.2]);
    for (var i = 0; i < 10; i += 2) {
      final tip = s([pts[i][0], pts[i][1], d]), mid = s([pts[(i + 1) % 10][0], pts[(i + 1) % 10][1], d]);
      c.drawPath(_poly([cc, tip, mid]), _fillPaint(_goldSide, 0.45));
    }
    final h0 = s([-3.2, cy - 0.6, d]), h1 = s([-1, cy - 4.4, d]);
    c.drawLine(ui.Offset(h0[0], h0[1]), ui.Offset(h1[0], h1[1]), _strokePaint(const ui.Color(0xFFFFFFFF), 1.6, opacity: 0.9, roundCap: true));
  }
}

/// Ярус на экране: кольцо края с полосой толщины, верхушка, передняя дуга и
/// силуэт (верхушка плюс передняя дуга).
class _TierScreen {
  _TierScreen(this.tier, XtCam cam) : band = 2.2 + tier.r * 0.03 {
    for (var i = 0; i < _ns; i++) {
      ring.add(cam.project(_add(tier.p(i / _ns * math.pi * 2, 1), [0, band, 0])));
    }
    apex = cam.project(tier.p(0, 0));
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

    double zAvg(List<int> ix) => ix.fold<double>(0, (a, i) => a + ring[i][2]) / ix.length;
    final a = walk(1), b = walk(-1);
    front = zAvg(a) > zAvg(b) ? a : b;
    sil = [apex, for (final i in front) ring[i]];
  }

  final XtTier tier;
  final double band;
  final List<_V> ring = [];
  late final _V apex;
  late final List<int> front;
  late final List<_V> sil;
}
