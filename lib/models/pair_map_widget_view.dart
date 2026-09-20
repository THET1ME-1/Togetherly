import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;

import 'geo_arc.dart';
import 'globe_math.dart';

/// Геометрия виджета «Где мы» на рабочем столе (19.09.2026).
///
/// Виджет не умеет показывать живую карту: и RemoteViews, и WidgetKit рисуют
/// только готовые картинки. Поэтому картинку собирает приложение — подложку в
/// цветах темы, двух людей, дугу и расстояние на ней, — а виджет её
/// показывает. Здесь всё, что про расстановку: размеры, безопасные поля,
/// выбор между картой, глобусом и «рядом», зум и плитки. Под тестами
/// `test/models/pair_map_widget_view_test.dart`.

/// Три размера виджета. Размер в точках — по умолчанию (крупный iPhone);
/// настоящий присылает лончер Android или считается по экрану iPhone.
enum MapWidgetSize {
  /// 2×2: двое, дуга и расстояние — больше ничего.
  s('s', 170, 170, EdgeInsets.fromLTRB(30, 62, 30, 18)),

  /// 4×2: широкая карта, внизу подпись, когда партнёр был на месте.
  m('m', 364, 170, EdgeInsets.fromLTRB(40, 66, 40, 34)),

  /// 4×4: карта с округой и панель внизу — кто где и когда.
  l('l', 364, 382, EdgeInsets.fromLTRB(44, 76, 44, 128));

  const MapWidgetSize(this.id, this.width, this.height, this.safe);

  final String id;
  final double width;
  final double height;

  /// Поля, внутрь которых должны встать сами точки. Сверху запас на шарик с
  /// аватаркой над точкой, снизу — на подпись и панель.
  final EdgeInsets safe;

  Size get size => Size(width, height);

  /// Размер из строки «ширина,высота» в dp, которую пишет лончер Android.
  Size sizeFrom(String? raw) {
    final parts = (raw ?? '').split(',');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0]), h = double.tryParse(parts[1]);
      if (w != null && h != null && w >= 60 && h >= 60) return Size(w, h);
    }
    return size;
  }

  /// Безопасные поля под фактический размер: доля от стандартной ячейки.
  EdgeInsets safeFor(Size actual) {
    final kx = actual.width / width, ky = actual.height / height;
    final k = math.min(kx, ky).clamp(.75, 1.25);
    return EdgeInsets.fromLTRB(safe.left * k, safe.top * k, safe.right * k, safe.bottom * k);
  }
}

/// Предел точек на картинку одного виджета. Рисуем под настоящую плотность
/// экрана, а упираемся сюда только на огромных ячейках.
///
/// Android: картинка уходит лончеру через общую память, предел системы —
/// полтора экрана в ARGB (около 20 МБ на современном телефоне). Два миллиона
/// точек — 8 МБ. Прежний бюджет в 950 КБ «под Binder» давал 4×4 плотность 1,9
/// при экране 3,25 и мыло (19.09.2026). Если лончер всё же откажет, провайдер
/// повторит вдвое меньшей картинкой.
const int kMapWidgetMaxPixelsAndroid = 2000000;

/// iPhone: картинку разжимает расширение виджетов, а ему на все виджеты
/// приложения отведены десятки мегабайт (на парном виджете оно уже падало).
/// 1,1 млн точек — 4,4 МБ: крупный виджет на экране 3x рисуется с плотностью
/// 2,8, на глаз неотличимо.
const int kMapWidgetMaxPixelsIos = 1100000;

/// Масштаб картинки: плотность экрана [dpr], но в пределах [maxPixels].
double pixelScaleFor(Size size, {required double dpr, required int maxPixels}) {
  final byBudget = math.sqrt(maxPixels / (size.width * size.height));
  return math.min(dpr.clamp(1.0, 4.0), byBudget);
}

/// Размер картинки в точках. Округление вниз: вверх оно выводило за предел.
(int, int) mapWidgetPixels(Size size, double k) =>
    ((size.width * k).floor(), (size.height * k).floor());

/// Размеры виджетов iPhone по ширине экрана в точках (таблица Apple).
Map<MapWidgetSize, Size> iosWidgetSizes(double screenWidth) {
  final (s, mw, lh) = switch (screenWidth) {
    >= 428 => (170.0, 364.0, 382.0),
    >= 414 => (169.0, 360.0, 379.0),
    >= 390 => (158.0, 338.0, 354.0),
    >= 375 => (155.0, 329.0, 345.0),
    >= 360 => (148.0, 321.0, 324.0),
    _ => (141.0, 292.0, 311.0),
  };
  return {
    MapWidgetSize.s: Size(s, s),
    MapWidgetSize.m: Size(mw, s),
    MapWidgetSize.l: Size(mw, lh),
  };
}

/// Что рисует виджет.
enum PairMapMode {
  /// Пары нет — зовём партнёра.
  noPair,

  /// Ни у кого нет точки — просим включить «Где мы».
  noPoints,

  /// Точка есть только у меня.
  onlyMe,

  /// Точка есть только у партнёра.
  onlyPartner,

  /// Ближе пятидесяти метров — «рядом», без дуги.
  near,

  /// Карта в цветах темы.
  map,

  /// Слишком далеко для карты — глобус с дугой, как на экране «Где мы».
  globe,
}

/// Ближе этого — «рядом»: GPS ошибается на 5–15 метров.
const double kMapWidgetNearMeters = 50;

/// Дальше этого приближаться бессмысленно: плитки кончаются на 14-м зуме.
const double kMapWidgetMaxZoom = 15.5;

/// Если двоих вписать можно только мельче этого зума, рисуем глобус: на
/// карте целой страны не видно ни улиц, ни людей.
const double kMapWidgetGlobeBelowZoom = 5.5;

const _distance = Distance();

double metersBetween(LatLng a, LatLng b) => _distance.distance(a, b).toDouble();

PairMapMode pairMapMode({
  required bool paired,
  required LatLng? me,
  required LatLng? partner,
  required Size size,
  required EdgeInsets safe,
}) {
  if (!paired) return PairMapMode.noPair;
  if (me == null && partner == null) return PairMapMode.noPoints;
  if (partner == null) return PairMapMode.onlyMe;
  if (me == null) return PairMapMode.onlyPartner;
  if (metersBetween(me, partner) < kMapWidgetNearMeters) return PairMapMode.near;
  final fit = fitTwo(me, partner, size, safe);
  return fit.rawZoom < kMapWidgetGlobeBelowZoom ? PairMapMode.globe : PairMapMode.map;
}

/// Центр и зум, при которых обе точки встают в безопасную зону.
class MapFit {
  final LatLng center;
  final double zoom;

  /// Зум до ограничения сверху: по нему решается, карта это или глобус.
  final double rawZoom;
  const MapFit(this.center, this.zoom, this.rawZoom);
}

double _mercX(double lon) => (lon + 180) / 360;
double _mercY(double lat) {
  final l = lat.clamp(-85.05, 85.05) * math.pi / 180;
  return (1 - math.log(math.tan(math.pi / 4 + l / 2)) / math.pi) / 2;
}

double _lonOf(double x) => x * 360 - 180;
double _latOf(double y) {
  final n = math.pi - 2 * math.pi * y;
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

MapFit fitTwo(LatLng a, LatLng b, Size size, EdgeInsets safe) {
  final ax = _mercX(a.longitude), bx0 = _mercX(b.longitude);
  // Через антимеридиан — короткой стороной.
  var bx = bx0;
  if (bx - ax > .5) bx -= 1;
  if (ax - bx > .5) bx += 1;
  final ay = _mercY(a.latitude), by = _mercY(b.latitude);
  final availW = math.max(1.0, size.width - safe.horizontal);
  final availH = math.max(1.0, size.height - safe.vertical);
  final dx = (ax - bx).abs() * 256, dy = (ay - by).abs() * 256;
  final zx = dx < 1e-9 ? 30.0 : math.log(availW / dx) / math.ln2;
  final zy = dy < 1e-9 ? 30.0 : math.log(availH / dy) / math.ln2;
  final raw = math.min(zx, zy);
  final zoom = raw.clamp(1.0, kMapWidgetMaxZoom);
  final ws = worldSize(zoom);
  // Центр ставим так, чтобы середина пары пришлась на середину безопасной
  // зоны, а не всей картинки: сверху запас под шарики больше, чем снизу.
  final midX = (ax + bx) / 2 * ws, midY = (ay + by) / 2 * ws;
  final shiftX = (safe.left - safe.right) / 2, shiftY = (safe.top - safe.bottom) / 2;
  var cx = (midX - shiftX) / ws;
  cx = cx - cx.floorToDouble();
  final cy = ((midY - shiftY) / ws).clamp(0.0, 1.0);
  return MapFit(LatLng(_latOf(cy), _lonOf(cx)), zoom, raw);
}

/// Одна точка (у партнёра нет места или вы рядом): точка — в середине
/// безопасной зоны, зум задан.
MapFit fitOne(LatLng p, Size size, EdgeInsets safe, {required double zoom}) {
  final ws = worldSize(zoom);
  final shiftX = (safe.left - safe.right) / 2, shiftY = (safe.top - safe.bottom) / 2;
  var cx = (_mercX(p.longitude) * ws - shiftX) / ws;
  cx = cx - cx.floorToDouble();
  final cy = ((_mercY(p.latitude) * ws - shiftY) / ws).clamp(0.0, 1.0);
  return MapFit(LatLng(_latOf(cy), _lonOf(cx)), zoom, zoom);
}

/// Одна плитка на картинке: адрес в сетке и где она лежит в точках картинки.
class TilePlacement {
  final int z, x, y;
  final Rect rect;
  const TilePlacement(this.z, this.x, this.y, this.rect);

  /// Во сколько раз плитка растянута против своего зума.
  double get overzoom => rect.width / 256;
}

/// Плитки, покрывающие картинку [size] с центром [center] на зуме [zoom].
/// Зум плиток не выше 14 — дальше OpenFreeMap плиток не отдаёт, их растягиваем.
List<TilePlacement> tilesFor(LatLng center, double zoom, Size size) {
  final zt = math.min(14, zoom.floor()).clamp(0, 14);
  final n = 1 << zt;
  final tileSizePts = 256 * math.pow(2, zoom - zt).toDouble();
  final worldPts = tileSizePts * n;
  final cx = _mercX(center.longitude) * worldPts;
  final cy = _mercY(center.latitude) * worldPts;
  final left = cx - size.width / 2, top = cy - size.height / 2;
  final x0 = (left / tileSizePts).floor(), x1 = ((left + size.width) / tileSizePts).ceil() - 1;
  final y0 = math.max(0, (top / tileSizePts).floor());
  final y1 = math.min(n - 1, ((top + size.height) / tileSizePts).ceil() - 1);
  final out = <TilePlacement>[];
  for (var ty = y0; ty <= y1; ty++) {
    for (var tx = x0; tx <= x1; tx++) {
      final rect = Rect.fromLTWH(tx * tileSizePts - left, ty * tileSizePts - top, tileSizePts, tileSizePts);
      out.add(TilePlacement(zt, ((tx % n) + n) % n, ty, rect));
    }
  }
  return out;
}

/// Дуга между двумя людьми на картинке: подъём от хорды той же формулой, что
/// на карте приложения (`arcHeight`), но не выше [maxLift] — у виджета над
/// точками мало места, и вершина уходила бы за край.
List<Offset> liftedArc(Offset a, Offset b, {required double maxLift, int segments = 48}) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return [a, b];
  var nx = -dy / len, ny = dx / len;
  if (ny > 0) {
    nx = -nx;
    ny = -ny;
  }
  final lift = math.min((len * .3).clamp(18.0, 110.0), math.max(0.0, maxLift));
  return [
    a,
    for (var i = 1; i < segments; i++)
      () {
        final u = i / segments;
        final h = lift * math.sin(math.pi * u);
        return Offset(a.dx + dx * u + nx * h, a.dy + dy * u + ny * h);
      }(),
    b,
  ];
}

/// Подъём любой ломаной от её хорды: так поднимается проекция дуги большого
/// круга на глобусе. Концы остаются на месте, вершина не выше [maxLift].
List<Offset> liftAlong(List<Offset> base, {required double maxLift, double minLift = 0}) {
  if (base.length < 2) return base;
  final a = base.first, b = base.last;
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return base;
  var nx = -dy / len, ny = dx / len;
  if (ny > 0) {
    nx = -nx;
    ny = -ny;
  }
  final top = math.max(0.0, maxLift);
  final lift = math.max(math.min(minLift, top), math.min((len * .3).clamp(18.0, 110.0), top));
  final last = base.length - 1;
  return [
    for (var i = 0; i <= last; i++)
      i == 0 || i == last
          ? base[i]
          : base[i] + Offset(nx, ny) * (lift * math.sin(math.pi * i / last)),
  ];
}

/// Шар для пары, которой тесно на карте.
///
/// Шар повёрнут так, чтобы линия между двумя людьми легла горизонтально: пара
/// стоит симметрично и влезает в любой размер, даже если между ними пол
/// планеты. Шар наклонён к смотрящему — сверху читается горизонт, пара ниже.
/// Север при этом смотрит вверх настолько, насколько позволяет поворот.
GlobeFrame globeFrameFor(LatLng a, LatLng b, Size size, EdgeInsets safe) {
  final inner = safe.deflateRect(Offset.zero & size);
  final p = Vec3.fromLatLng(a.latitude, a.longitude);
  final q = Vec3.fromLatLng(b.latitude, b.longitude);
  var m = (p + q).normalized;
  if ((p + q).length < 1e-6) m = Vec3.fromLatLng(0, a.longitude + 90);
  // Направление от меня к партнёру в точке середины — это «вправо».
  final d = q - p;
  var g = (d - m * m.dot(d)).normalized;
  if (d.length < 1e-9) g = Vec3.fromLatLng(0, a.longitude + 90);
  var h = m.cross(g);
  // «Вверх» ближе к северу: иначе пара встала бы вверх ногами.
  if (h.z < 0) {
    g = g * -1;
    h = m.cross(g);
  }
  final half = math.acos(p.dot(q).clamp(-1.0, 1.0)) / 2;
  final yTop = size.height * .14;
  final yPair = inner.top + inner.height * .56;
  final spread = math.max(1e-6, math.sin(half));
  // Двое не должны слипаться: между шариками не меньше трети ширины. Для
  // близкой пары шар выходит огромным — горизонт всё равно виден сверху.
  final minHalf = math.min(inner.width * .32, 78.0);
  final r = math.min(
    math.max(math.max(size.width, size.height) * .66, minHalf / spread),
    (inner.width / 2 - 2) / spread,
  );
  // Наклон: пара на высоте yPair, верх шара на yTop.
  final need = (1 - (yPair - yTop) / r) / math.max(1e-6, math.cos(half));
  final sinT = need.clamp(0.0, .9);
  final t = math.asin(sinT);
  final c = m * math.cos(t) - h * math.sin(t);
  final e = g;
  final n = c.cross(e);
  // Пара встаёт на yPair: центр шара — ниже неё на проекцию наклона.
  final cy = yPair + r * math.cos(half) * sinT;
  final mid = greatCircle(a, b, segments: 2)[1];
  return GlobeFrame(
    lat: mid.latitude,
    lon: mid.longitude,
    radius: r,
    center: Offset(size.width / 2, cy),
    tilt: t * 180 / math.pi,
    axes: GlobeBasis.axes(c, e, n),
  );
}

/// Середина дуги по длине — там стоит расстояние.
Offset arcApex(List<Offset> pts) {
  if (pts.length < 2) return pts.isEmpty ? Offset.zero : pts.first;
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  var run = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final seg = (pts[i] - pts[i - 1]).distance;
    if (run + seg >= total / 2) {
      return Offset.lerp(pts[i - 1], pts[i], seg == 0 ? 0 : (total / 2 - run) / seg)!;
    }
    run += seg;
  }
  return pts.last;
}
