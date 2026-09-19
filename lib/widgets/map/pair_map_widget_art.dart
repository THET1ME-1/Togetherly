import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../models/globe_math.dart';
import '../../models/pair_map_widget_view.dart';
import '../../services/map/map_palette.dart';
import 'arc_paint.dart';
import 'globe_view.dart';
import 'land_shapes.dart';

/// Строка панели крупного виджета: чей шарик, имя и где/когда.
class MapWidgetRow {
  final bool mine;
  final String name;
  final String detail;
  const MapWidgetRow({required this.mine, required this.name, required this.detail});
}

/// Всё, из чего складывается картинка виджета «Где мы». Координаты — в
/// точках картинки; масштаб в пиксели задаёт вызывающий (`canvas.scale`).
class PairMapWidgetArt {
  final MapWidgetSize kind;
  final Size size;
  final PairMapMode mode;
  final MapPalette palette;

  /// Заливка темы и надпись на ней: пилюля расстояния.
  final Color fill;
  final Color onFill;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;

  /// Кружки аватарок без фотографии.
  final Color meBg, meFg, partnerBg, partnerFg;

  /// Плитки карты в режиме карты: где лежит и что внутри.
  final List<(TilePlacement, vtr.Tile)> tiles;
  final vtr.Theme? mapTheme;
  final double zoom;

  /// Шар в режиме глобуса, суша для него и проекция дуги большого круга
  /// между двумя людьми (без подъёма — его добавляет художник).
  final GlobeFrame? globe;
  final List<LandRing> land;
  final List<Offset> globeArcBase;

  /// Точки людей на картинке (в режиме карты и глобуса).
  final Offset? me, partner;
  final ui.Image? meAvatar, partnerAvatar;
  final String meInitial, partnerInitial;

  /// Точка партнёра старая — его шарик приглушён.
  final bool partnerStale;

  /// Подпись на дуге: «2,9 км» или «Рядом».
  final String distance;

  /// Подпись внизу среднего виджета и плашка режимов «точка у одного».
  final String? caption;

  /// Панель крупного виджета.
  final List<MapWidgetRow> rows;

  /// Заглушки «нет пары» и «нет точек».
  final String? title, subtitle;

  const PairMapWidgetArt({
    required this.kind,
    required this.size,
    required this.mode,
    required this.palette,
    required this.fill,
    required this.onFill,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.meBg,
    required this.meFg,
    required this.partnerBg,
    required this.partnerFg,
    this.tiles = const [],
    this.mapTheme,
    this.zoom = 13,
    this.globe,
    this.land = const [],
    this.globeArcBase = const [],
    this.me,
    this.partner,
    this.meAvatar,
    this.partnerAvatar,
    this.meInitial = '',
    this.partnerInitial = '',
    this.partnerStale = false,
    this.distance = '',
    this.caption,
    this.rows = const [],
    this.title,
    this.subtitle,
  });

  // Размеры деталей по размеру виджета: шарик, пилюля, подписи.
  double get _avatar => switch (kind) { MapWidgetSize.s => 38, MapWidgetSize.m => 42, MapWidgetSize.l => 48 };
  double get _pillFont => switch (kind) { MapWidgetSize.s => 12.5, MapWidgetSize.m => 14, MapWidgetSize.l => 15.5 };
  double get _panelHeight => kind == MapWidgetSize.l ? 112 : 0;

  void paint(Canvas canvas) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = palette.land);

    switch (mode) {
      case PairMapMode.noPair:
      case PairMapMode.noPoints:
        _paintEmpty(canvas);
      case PairMapMode.globe:
        _paintGlobe(canvas);
      default:
        _paintTiles(canvas);
        _paintPeople(canvas);
    }

    if (mode != PairMapMode.noPair && mode != PairMapMode.noPoints) {
      if (kind == MapWidgetSize.l) {
        _paintPanel(canvas);
      } else if (caption != null && caption!.isNotEmpty) {
        _paintCaption(canvas, caption!);
      }
    }
    canvas.restore();
  }

  // ── Подложка ──────────────────────────────────────────────────────────────

  void _paintTiles(Canvas canvas) {
    final theme = mapTheme;
    if (theme == null) return;
    final renderer = vtr.Renderer(theme: theme);
    for (final (place, tile) in tiles) {
      canvas.save();
      canvas.translate(place.rect.left, place.rect.top);
      canvas.scale(place.overzoom);
      renderer.render(
        canvas,
        vtr.TileSource(tileset: vtr.Tileset({'openmaptiles': tile})),
        zoomScaleFactor: place.overzoom,
        zoom: zoom,
        rotation: 0,
      );
      canvas.restore();
    }
  }

  void _paintGlobe(Canvas canvas) {
    final f = globe;
    if (f == null) return;
    // Вокруг шара — ночь цвета поверхности, чуть темнее суши: так шар
    // держится на картинке, а не растворяется в ней.
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.lerp(surface, palette.water, .35)!);
    final scene = GlobeScene.globe(f);
    final a = me, b = partner;
    final placed = (a != null && b != null) ? _arcAndPill(a, b, globeArcBase) : null;
    GlobePainter(scene: scene, land: land, palette: palette, arc: placed?.$1 ?? const []).paint(canvas, size);
    if (placed != null) {
      _paintBalloons(canvas);
      _pill(canvas, placed.$2, distance);
    }
  }

  // ── Люди ──────────────────────────────────────────────────────────────────

  void _paintPeople(Canvas canvas) {
    final a = me, b = partner;
    if (mode == PairMapMode.near && a != null && b != null) {
      final mid = Offset.lerp(a, b, .5)!;
      final d = _avatar;
      _balloon(canvas, mid.translate(-d * .42, 0), meAvatar, meInitial, meBg, meFg, stale: false);
      _balloon(canvas, mid.translate(d * .42, 0), partnerAvatar, partnerInitial, partnerBg, partnerFg,
          stale: partnerStale);
      _pill(canvas, mid.translate(0, -(d + 22 + _pillFont)), distance, heart: true);
      return;
    }
    if (a != null && b != null) {
      final (arc, at) = _arcAndPill(a, b, const []);
      paintDottedArc(canvas, arc, color: palette.thread, halo: palette.halo);
      _paintBalloons(canvas);
      _pill(canvas, at, distance);
      return;
    }
    _paintBalloons(canvas);
  }

  /// Дуга и место пилюли с расстоянием.
  ///
  /// Пилюля стоит на вершине дуги, но не ложится на шарики: когда двое стоят
  /// друг над другом или близко, дуга поднимается выше, пока вершина не
  /// выйдет на свободное место. Не вышла — пилюля встаёт над головами.
  (List<Offset>, Offset) _arcAndPill(Offset a, Offset b, List<Offset> base) {
    final line = base.length > 2 ? base : [for (var i = 0; i <= 32; i++) Offset.lerp(a, b, i / 32)!];
    final pill = _pillSize(distance);
    final room = math.max(0.0, (a.dy + b.dy) / 2 - pill.height / 2 - 8);
    final heads = [_balloonRect(a), _balloonRect(b)];
    bool clear(Offset at) {
      final r = Rect.fromCenter(center: at, width: pill.width + 8, height: pill.height + 6);
      return heads.every((h) => !h.overlaps(r));
    }

    final natural = liftAlong(line, maxLift: room);
    if (clear(arcApex(natural))) return (natural, arcApex(natural));
    for (var lift = 24.0; lift <= room; lift += 6) {
      final arc = liftAlong(line, maxLift: room, minLift: lift);
      final at = arcApex(arc);
      if (clear(at)) return (arc, at);
    }
    final arc = liftAlong(line, maxLift: room, minLift: room);
    final apex = arcApex(arc);
    final top = heads.map((h) => h.top).reduce(math.min);
    final y = math.max(pill.height / 2 + 6, math.min(apex.dy, top - pill.height / 2 - 4));
    return (arc, Offset(apex.dx, y));
  }

  /// Где на картинке шарик человека с точкой в [dot].
  Rect _balloonRect(Offset dot) {
    final d = _avatar;
    return Rect.fromLTRB(dot.dx - d / 2 - 3, dot.dy - (9 + d + 6), dot.dx + d / 2 + 3, dot.dy + 5);
  }

  Size _pillSize(String text) {
    final fs = _pillFont;
    final tp = _painter(text, fontSize: fs, color: onFill, weight: 800, display: true);
    final icon = _iconPainter(Icons.favorite_rounded, fs * .95, onFill);
    final size = Size(fs * 1.6 + icon.width + fs * .35 + tp.width, fs * 2.15);
    tp.dispose();
    icon.dispose();
    return size;
  }

  void _paintBalloons(Canvas canvas) {
    final people = <(Offset, ui.Image?, String, Color, Color, bool)>[
      if (partner != null) (partner!, partnerAvatar, partnerInitial, partnerBg, partnerFg, partnerStale),
      if (me != null) (me!, meAvatar, meInitial, meBg, meFg, false),
    ]..sort((x, y) => x.$1.dy.compareTo(y.$1.dy));
    for (final p in people) {
      _balloon(canvas, p.$1, p.$2, p.$3, p.$4, p.$5, stale: p.$6);
    }
  }

  /// Шарик: точка на месте, ножка вверх и аватарка в кольце цвета поверхности.
  void _balloon(Canvas canvas, Offset dot, ui.Image? img, String initial, Color bg, Color fg,
      {required bool stale}) {
    final d = _avatar;
    const stem = 9.0, ring = 3.0;
    final c = dot.translate(0, -(stem + d / 2 + ring));
    // Старая точка: шарик обесцвечен, но плотный — сквозь полупрозрачный
    // просвечивали точки дуги.
    if (stale) {
      canvas.saveLayer(
        null,
        Paint()
          ..colorFilter = const ColorFilter.matrix(<double>[
            .33, .5, .17, 0, 0, //
            .33, .5, .17, 0, 0, //
            .33, .5, .17, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
      );
    }
    final pin = Paint()..color = fill;
    canvas.drawLine(dot, c.translate(0, d / 2), pin..strokeWidth = 2);
    canvas.drawCircle(dot, 5, Paint()..color = surface);
    canvas.drawCircle(dot, 3.2, Paint()..color = fill);
    canvas.drawCircle(c, d / 2 + ring, Paint()..color = surface);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: d / 2)));
    final box = Rect.fromCircle(center: c, radius: d / 2);
    if (img != null) {
      final src = _coverSrc(img, box.size);
      canvas.drawImageRect(img, src, box, Paint()..filterQuality = FilterQuality.medium);
    } else {
      canvas.drawRect(box, Paint()..color = bg);
      _text(canvas, initial, c, fontSize: d * .42, color: fg, weight: 700, center: true);
    }
    canvas.restore();
    if (stale) canvas.restore();
  }

  Rect _coverSrc(ui.Image img, Size box) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final s = math.max(box.width / iw, box.height / ih);
    final w = box.width / s, h = box.height / s;
    return Rect.fromLTWH((iw - w) / 2, (ih - h) / 2, w, h);
  }

  /// Пилюля расстояния на дуге: заливка темы, кольцо цвета поверхности.
  void _pill(Canvas canvas, Offset at, String text, {bool heart = true}) {
    if (text.isEmpty) return;
    final fs = _pillFont;
    final tp = _painter(text, fontSize: fs, color: onFill, weight: 800, display: true);
    final icon = heart ? _iconPainter(Icons.favorite_rounded, fs * .95, onFill) : null;
    final gap = icon == null ? 0.0 : fs * .35;
    final h = fs * 2.15;
    final w = fs * 1.6 + (icon?.width ?? 0) + gap + tp.width;
    var r = Rect.fromCenter(center: at, width: w, height: h);
    // Не даём пилюле уйти за край картинки.
    final dx = r.left < 6 ? 6 - r.left : (r.right > size.width - 6 ? size.width - 6 - r.right : 0.0);
    final dy = r.top < 6 ? 6 - r.top : 0.0;
    r = r.shift(Offset(dx, dy));
    final rr = RRect.fromRectAndRadius(r, Radius.circular(h / 2));
    canvas.drawRRect(rr.inflate(3), Paint()..color = surface);
    canvas.drawRRect(rr, Paint()..color = fill);
    var x = r.left + fs * .8;
    if (icon != null) {
      icon.paint(canvas, Offset(x, r.center.dy - icon.height / 2));
      x += icon.width + gap;
    }
    tp.paint(canvas, Offset(x, r.center.dy - tp.height / 2));
    tp.dispose();
    icon?.dispose();
  }

  // ── Подписи ───────────────────────────────────────────────────────────────

  void _paintCaption(Canvas canvas, String text) {
    final fs = kind == MapWidgetSize.s ? 10.5 : 11.5;
    final tp = _painter(text, fontSize: fs, color: onSurface, weight: 600, maxWidth: size.width - 40);
    final h = fs * 2.2;
    final r = Rect.fromLTWH(12, size.height - 10 - h, tp.width + fs * 1.6, h);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)), Paint()..color = surface.withValues(alpha: .94));
    tp.paint(canvas, Offset(r.left + fs * .8, r.center.dy - tp.height / 2));
    tp.dispose();
  }

  void _paintPanel(Canvas canvas) {
    final top = size.height - _panelHeight;
    final panel = RRect.fromLTRBAndCorners(0, top, size.width, size.height + 1,
        topLeft: const Radius.circular(24), topRight: const Radius.circular(24));
    canvas.drawRRect(panel, Paint()..color = surface);
    var y = top + 14.0;
    for (final row in rows.take(2)) {
      const d = 30.0;
      final c = Offset(16 + d / 2, y + d / 2);
      final img = row.mine ? meAvatar : partnerAvatar;
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: d / 2)));
      final box = Rect.fromCircle(center: c, radius: d / 2);
      if (img != null) {
        canvas.drawImageRect(img, _coverSrc(img, box.size), box, Paint()..filterQuality = FilterQuality.medium);
      } else {
        canvas.drawRect(box, Paint()..color = row.mine ? meBg : partnerBg);
        _text(canvas, row.mine ? meInitial : partnerInitial, c,
            fontSize: 13, color: row.mine ? meFg : partnerFg, weight: 700, center: true);
      }
      canvas.restore();
      final name = _painter(row.name, fontSize: 14, color: onSurface, weight: 700, maxWidth: 120);
      name.paint(canvas, Offset(16 + d + 10, c.dy - name.height / 2));
      final detail = _painter(row.detail, fontSize: 12.5, color: onSurfaceVariant, weight: 500,
          maxWidth: size.width - (16 + d + 10 + name.width + 8) - 16);
      detail.paint(canvas, Offset(size.width - 16 - detail.width, c.dy - detail.height / 2));
      name.dispose();
      detail.dispose();
      y += 44;
    }
  }

  void _paintEmpty(Canvas canvas) {
    // Тихий шар за текстом: даже заглушка остаётся картой, а не серой плашкой.
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);
    final r = math.max(size.width, size.height) * .62;
    final frame = GlobeFrame(
      lat: 30,
      lon: 25,
      radius: r,
      center: Offset(size.width * .5, size.height * .62 + r * .55),
      tilt: 0,
    );
    canvas.saveLayer(null, Paint()..color = const Color(0x8CFFFFFF));
    GlobePainter(scene: GlobeScene.globe(frame), land: land, palette: palette, arc: const []).paint(canvas, size);
    canvas.restore();
    final t = title ?? '';
    final st = subtitle ?? '';
    final small = kind == MapWidgetSize.s;
    final titleTp = _painter(t,
        fontSize: switch (kind) { MapWidgetSize.s => 14, MapWidgetSize.m => 17, MapWidgetSize.l => 21 },
        color: onSurface, weight: 800, display: true,
        maxWidth: size.width - 32, align: TextAlign.center, lines: 3);
    final subTp = small || st.isEmpty
        ? null
        : _painter(st, fontSize: kind == MapWidgetSize.l ? 14.5 : 13, color: onSurfaceVariant, weight: 500,
            maxWidth: size.width - 48, align: TextAlign.center, lines: 3);
    final total = titleTp.height + (subTp == null ? 0 : 6 + subTp.height);
    var y = (size.height * (kind == MapWidgetSize.l ? .38 : .42)) - total / 2;
    titleTp.paint(canvas, Offset((size.width - titleTp.width) / 2, y));
    y += titleTp.height + 6;
    subTp?.paint(canvas, Offset((size.width - subTp.width) / 2, y));
    titleTp.dispose();
    subTp?.dispose();
  }

  // ── Текст ─────────────────────────────────────────────────────────────────

  TextPainter _painter(
    String text, {
    required double fontSize,
    required Color color,
    required int weight,
    bool display = false,
    double? maxWidth,
    TextAlign align = TextAlign.left,
    int lines = 1,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: display ? 'Unbounded' : 'Onest',
          fontSize: fontSize,
          fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
          fontVariations: [FontVariation('wght', weight.toDouble())],
          color: color,
          height: 1.2,
          letterSpacing: display ? -.2 : 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return tp;
  }

  TextPainter _iconPainter(IconData icon, double size, Color color) => TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, String text, Offset at,
      {required double fontSize, required Color color, required int weight, bool center = false}) {
    final tp = _painter(text, fontSize: fontSize, color: color, weight: weight);
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
    tp.dispose();
  }
}

/// Вспомогательное для глобуса: дуга большого круга, спроецированная на шар
/// и поднятая от хорды. Живёт снаружи, потому что художнику нужна уже готовая
/// ломаная — в [PairMapWidgetArt.globeArc].
List<Offset> projectGreatCircle(GlobeFrame frame, List<Vec3> gc) {
  final b = frame.basis;
  return [for (final v in gc) b.project(v, frame.radius, frame.center)];
}
