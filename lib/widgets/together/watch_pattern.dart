import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_new_shapes/material_new_shapes.dart' hide Cubic;

import '../../models/symbol_catalog.dart';

/// Узоры и отклик на нажатие карточек экрана «Смотрим», вариант «по углам»
/// макета https://claude.ai/artifact/Ji4675yhiELRjRu3YSK5sv (05.10.2026).
///
/// Узор — сетка клеток: тон клетки плюс знак другим тоном. Тона берутся только
/// из цвета самой карточки (чужой цвет на чёрном или жёлтом заказчик отверг),
/// знаки — из словаря карточки: у кино плёнка и билеты, у ленты экранчики и
/// лайки, у игр кубики и масти, у компьютера клавиши и курсор. Раскладку задаёт
/// число пары, поэтому она не скачет от захода к заходу.

/// Словарь знаков карточки.
enum WatchMotifs { kino, reels, games, computer }

const Map<WatchMotifs, List<String>> _kinds = {
  WatchMotifs.kino: ['film', 'reel', 'ticket', 'clap', 'seat', 'playbtn', 'quarter', 'half'],
  WatchMotifs.reels: ['phone', 'stack', 'like', 'swipe', 'dots', 'phone', 'half', 'quarter'],
  WatchMotifs.games: ['die', 'die', 'diamond', 'club', 'pad', 'hearts', 'quarter'],
  WatchMotifs.computer: ['key', 'key', 'window', 'cursor', 'pixels', 'quarter'],
};

/// Знаки, которые кладутся с поворотом на четверть круга.
const Set<String> _rotating = {'quarter', 'half', 'clap', 'film', 'ticket', 'die'};

/// Пять тонов узора от цвета карточки: сама карточка, темнее, светлее и два
/// дальних. Оттенок и насыщенность прежние, двигается только тон HCT — сдвиги
/// сняты с палитр макета. У тёмной карточки тона идут вверх, у светлой
/// пастели — вниз (выше белого светлеть некуда).
List<Color> watchPatternTones(Color base) {
  final h = Hct.fromInt(base.toARGB32());
  final t = h.tone;
  final List<double> shifts = t < 40
      ? const [6, 12, -5, 17]
      : t > 82
          ? const [-7, 4, -14, -21]
          : const [-8, 6, 15, -15];
  return [
    base,
    for (final d in shifts) Color(Hct.from(h.hue, h.chroma, (t + d).clamp(0, 100).toDouble()).toInt()),
  ];
}

/// Число раскладки узора по ключу пары. FNV-1a, а не `hashCode`: тот не
/// обещает одинакового ответа между запусками.
int watchPatternSeed(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Клетка узора: тон фона, тон знака (номера в [watchPatternTones]), знак и
/// поворот в градусах.
class WatchPatternCell {
  const WatchPatternCell(this.col, this.row, this.bg, this.fg, this.kind, this.rot);

  final int col;
  final int row;
  final int bg;
  final int fg;
  final String kind;
  final int rot;
}

/// Раскладка клеток. Порядок выборок тот же, что в генераторе макета.
List<WatchPatternCell> watchPatternCells(WatchMotifs motifs, int seed, int cols, int rows) {
  final r = math.Random(seed);
  final kinds = _kinds[motifs]!;
  final out = <WatchPatternCell>[];
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final bg = r.nextInt(5);
      final others = [for (var k = 0; k < 5; k++) if (k != bg) k];
      final fg = others[r.nextInt(others.length)];
      final kind = kinds[r.nextInt(kinds.length)];
      var rot = _rotating.contains(kind) ? const [0, 90, 180, 270][r.nextInt(4)] : 0;
      if (kind == 'die') rot = const [90, 180, 270, 360, 450, 540][r.nextInt(6)];
      out.add(WatchPatternCell(i, j, bg, fg, kind, rot));
    }
  }
  return out;
}

final Path _heart = MaterialShapes.heart.toPath();
final Path _diamond = MaterialShapes.diamond.toPath();

/// Рисует знак в клетке со стороной [s], начало клетки в (0, 0). Все размеры —
/// десятые доли клетки, как в макете.
void paintWatchMotif(Canvas c, String kind, double s, int rot, Color col, Color bgColor) {
  final u = s / 10;
  final fg = Paint()..color = col;
  final bg = Paint()..color = bgColor;
  void rr(double x, double y, double w, double h, double r, [Paint? p]) =>
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * u, y * u, w * u, h * u), Radius.circular(r * u)), p ?? fg);
  void ci(double x, double y, double r, [Paint? p]) => c.drawCircle(Offset(x * u, y * u), r * u, p ?? fg);
  void poly(List<double> pts, [Paint? p]) {
    final path = Path()..moveTo(pts[0] * u, pts[1] * u);
    for (var i = 2; i < pts.length; i += 2) {
      path.lineTo(pts[i] * u, pts[i + 1] * u);
    }
    c.drawPath(path..close(), p ?? fg);
  }

  void shape(Path unit, double x, double y, double sx, double sy) {
    c.save();
    c.translate(x * u, y * u);
    c.scale(sx * u, sy * u);
    c.drawPath(unit, fg);
    c.restore();
  }

  final turned = rot != 0 && kind != 'die';
  if (turned) {
    c.save();
    c.translate(s / 2, s / 2);
    c.rotate(rot * math.pi / 180);
    c.translate(-s / 2, -s / 2);
  }
  switch (kind) {
    // ── кино ──
    case 'film': // кадр плёнки с перфорацией
      rr(0, 0, 10, 10, 0);
      for (var i = 0; i < 4; i++) {
        rr(0.6, 1 + i * 2.2, 1.2, 1.2, .3, bg);
        rr(8.2, 1 + i * 2.2, 1.2, 1.2, .3, bg);
      }
      rr(2.6, 1.6, 4.8, 6.8, .6, bg);
    case 'reel': // бобина
      ci(5, 5, 4.4);
      for (var a = -90; a < 270; a += 72) {
        ci(5 + 2.3 * math.cos(a * math.pi / 180), 5 + 2.3 * math.sin(a * math.pi / 180), .9, bg);
      }
      ci(5, 5, .6, bg);
    case 'ticket': // билет с вырезами
      rr(0.6, 2.4, 8.8, 5.2, .6);
      ci(.6, 5, 1, bg);
      ci(9.4, 5, 1, bg);
      for (var i = 0; i < 4; i++) {
        rr(6.4, 3.1 + i * 1.1, .4, .6, 0, bg);
      }
    case 'clap': // хлопушка
      rr(0, 3.6, 10, 6.4, .6);
      for (var i = 0; i < 3; i++) {
        poly([i * 3.3, 0, i * 3.3 + 1.7, 0, i * 3.3 + 2.6, 3, i * 3.3 + .9, 3]);
      }
    case 'seat': // кресло зала
      rr(1.6, 1.2, 6.8, 5.6, 2.2);
      rr(.8, 5, 8.4, 2.6, 1.2);
      rr(1.6, 7.4, 1.2, 1.8, .3);
      rr(7.2, 7.4, 1.2, 1.8, .3);
    case 'playbtn': // круг с треугольником «играть»
      ci(5, 5, 4.2);
      poly([4.1, 3.2, 4.1, 6.8, 7, 5], bg);
    // ── лента ──
    case 'phone': // экранчик ролика
      rr(2.6, .6, 4.8, 8.8, 1.2);
      rr(4, 7.6, 2, .5, .25, bg);
      poly([4.4, 3.4, 4.4, 5.8, 6.2, 4.6], bg);
    case 'stack': // стопка роликов
      rr(3.4, .6, 4.6, 6.6, 1);
      rr(2, 2.4, 4.6, 7, 1.1, bg);
      rr(2.4, 2.8, 3.8, 6.2, .8);
    case 'like':
      shape(_heart, 1.4, 1.6, 7.2, 7.2);
    case 'swipe': // стрелки свайпа вверх
      for (final d in const [0.0, 3.0]) {
        poly([2, 5 + d, 5, 2 + d, 8, 5 + d, 8, 6.6 + d, 5, 3.6 + d, 2, 6.6 + d]);
      }
    case 'dots': // точки прогресса ленты
      rr(4.3, 1, 1.4, 2.6, .7);
      ci(5, 5.6, .7);
      ci(5, 7.8, .7);
    // ── игры ──
    case 'die':
      {
        const pips = {
          1: [5.0, 5.0],
          2: [3.0, 3.0, 7.0, 7.0],
          3: [3.0, 3.0, 5.0, 5.0, 7.0, 7.0],
          4: [3.0, 3.0, 7.0, 3.0, 3.0, 7.0, 7.0, 7.0],
          5: [3.0, 3.0, 7.0, 3.0, 5.0, 5.0, 3.0, 7.0, 7.0, 7.0],
          6: [3.0, 2.6, 7.0, 2.6, 3.0, 5.0, 7.0, 5.0, 3.0, 7.4, 7.0, 7.4],
        };
        rr(.8, .8, 8.4, 8.4, 2);
        final p = pips[rot == 0 ? 5 : (rot ~/ 90) % 6 + 1]!;
        for (var i = 0; i < p.length; i += 2) {
          ci(p[i], p[i + 1], .9, bg);
        }
      }
    case 'diamond': // бубны
      shape(_diamond, 1.5, 1, 7, 8);
    case 'club': // трефы
      ci(5, 3.2, 2);
      ci(3, 6, 2);
      ci(7, 6, 2);
      poly([4.4, 6, 5.6, 6, 6.4, 9.4, 3.6, 9.4]);
    case 'pad': // кнопки геймпада
      {
        final stroke = Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7 * u
          ..strokeCap = StrokeCap.round;
        c.drawCircle(Offset(5 * u, 2.4 * u), 1.3 * u, stroke);
        poly([5, 6.2, 6.5, 8.6, 3.5, 8.6]);
        rr(1.1, 4.1, 2.2, 2.2, .3);
        c.drawLine(Offset(7 * u, 4.2 * u), Offset(9 * u, 6.2 * u), stroke);
        c.drawLine(Offset(9 * u, 4.2 * u), Offset(7 * u, 6.2 * u), stroke);
      }
    case 'hearts': // черви
      shape(_heart, 2, 2, 6, 6);
    // ── компьютер ──
    case 'key': // клавиша
      rr(.8, .8, 8.4, 8.4, 1.6);
      rr(2, 1.8, 6, 5.6, 1.2, bg);
      rr(3.2, 3.2, 1.4, 1.4, .3);
    case 'window': // окно с точками в заголовке
      rr(.8, 1.6, 8.4, 6.8, 1);
      ci(2, 2.8, .45, bg);
      ci(3.2, 2.8, .45, bg);
      ci(4.4, 2.8, .45, bg);
      rr(1.6, 4, 6.8, 3.6, .5, bg);
    case 'cursor':
      poly([3, 1.6, 3, 8.4, 4.8, 6.6, 6.2, 9.2, 7.4, 8.6, 6, 6, 8.4, 6]);
    case 'pixels':
      rr(1, 1, 3.6, 3.6, .6);
      rr(5.4, 5.4, 3.6, 3.6, .6);
      rr(5.4, 1, 3.6, 3.6, .6, bg);
      rr(1, 5.4, 3.6, 3.6, .6, bg);
    // ── простая геометрия ──
    case 'quarter': // четверть круга из угла
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(s, 0)
          ..arcToPoint(Offset(0, s), radius: Radius.circular(s))
          ..close(),
        fg,
      );
    case 'half': // полукруг на нижней стороне
      c.drawPath(
        Path()
          ..moveTo(0, s)
          ..arcToPoint(Offset(s, s), radius: Radius.circular(s / 2))
          ..close(),
        fg,
      );
  }
  if (turned) c.restore();
}

/// Кривая «подпрыгнуть» у клеток: от 1 к 0,78 за треть и обратно с лёгким
/// перелётом. Задержка — расстояние от точки нажатия, 1,4 мс на точку.
const Curve _popCurve = Cubic(.34, 1.4, .64, 1);
const double _popMs = 500;
const double _popDelayPerPx = 1.4;

double watchPopScale(double ms) {
  if (ms <= 0 || ms >= _popMs) return 1;
  final t = ms / _popMs;
  if (t < .35) return 1 - .22 * _popCurve.transform(t / .35);
  return .78 + .22 * _popCurve.transform((t - .35) / .65);
}

/// Узор карточки. Растягивается как `preserveAspectRatio="xMidYMid slice"`:
/// сетка [cols]×[rows] клеток по [cell] точек покрывает область целиком, лишнее
/// срезается по краям поровну.
class WatchPattern extends StatefulWidget {
  const WatchPattern({
    super.key,
    required this.motifs,
    required this.seed,
    required this.tones,
    required this.cols,
    required this.rows,
    this.cell = 40,
  });

  final WatchMotifs motifs;
  final int seed;
  final List<Color> tones;
  final int cols;
  final int rows;
  final double cell;

  @override
  State<WatchPattern> createState() => _WatchPatternState();
}

class _WatchPatternState extends State<WatchPattern> {
  List<ui.Picture>? _pictures;
  List<WatchPatternCell> _cells = const [];

  @override
  void didUpdateWidget(WatchPattern old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed ||
        old.motifs != widget.motifs ||
        old.cols != widget.cols ||
        old.rows != widget.rows ||
        old.cell != widget.cell ||
        !_sameTones(old.tones, widget.tones)) {
      _drop();
    }
  }

  static bool _sameTones(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _drop() {
    for (final p in _pictures ?? const <ui.Picture>[]) {
      p.dispose();
    }
    _pictures = null;
  }

  /// Каждая клетка пишется в картинку один раз: подпрыгивая, клетки только
  /// масштабируются, и перерисовывать знаки на каждом кадре незачем.
  List<ui.Picture> _ensure() {
    final ready = _pictures;
    if (ready != null) return ready;
    final s = widget.cell;
    _cells = watchPatternCells(widget.motifs, widget.seed, widget.cols, widget.rows);
    return _pictures = [
      for (final cell in _cells)
        () {
          final rec = ui.PictureRecorder();
          final c = Canvas(rec);
          final bg = widget.tones[cell.bg];
          // Фон клетки чуть шире самой клетки: иначе между соседями при
          // дробном масштабе проступает волосяная щель.
          c.drawRect(Rect.fromLTWH(-.4, -.4, s + .8, s + .8), Paint()..color = bg);
          paintWatchMotif(c, cell.kind, s, cell.rot, widget.tones[cell.fg], bg);
          return rec.endRecording();
        }(),
    ];
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  Offset? _localOrigin(Offset? global) {
    if (global == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final fx = WatchFx.maybeOf(context);
    return CustomPaint(
      painter: _PatternPainter(
        pictures: _ensure(),
        cells: _cells,
        cols: widget.cols,
        rows: widget.rows,
        cell: widget.cell,
        pop: fx?.pop,
        origin: () => _localOrigin(fx?.origin),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.pictures,
    required this.cells,
    required this.cols,
    required this.rows,
    required this.cell,
    required this.pop,
    required this.origin,
  }) : super(repaint: pop);

  final List<ui.Picture> pictures;
  final List<WatchPatternCell> cells;
  final int cols;
  final int rows;
  final double cell;
  final Animation<double>? pop;
  final Offset? Function() origin;

  @override
  void paint(Canvas canvas, Size size) {
    final vw = cols * cell, vh = rows * cell;
    final k = math.max(size.width / vw, size.height / vh);
    final dx = (size.width - vw * k) / 2, dy = (size.height - vh * k) / 2;
    final ms = (pop?.value ?? 0) * WatchFx.popWindowMs;
    final at = ms > 0 ? origin() : null;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dx, dy);
    canvas.scale(k);
    for (var i = 0; i < cells.length; i++) {
      final cl = cells[i];
      final cx = (cl.col + .5) * cell, cy = (cl.row + .5) * cell;
      var sc = 1.0;
      if (at != null) {
        final d = (Offset(dx + cx * k, dy + cy * k) - at).distance;
        sc = watchPopScale(ms - d * _popDelayPerPx);
      }
      canvas.save();
      canvas.translate(cx, cy);
      if (sc != 1) canvas.scale(sc);
      canvas.translate(-cell / 2, -cell / 2);
      canvas.drawPicture(pictures[i]);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pictures != pictures || old.cols != cols || old.rows != rows || old.cell != cell || old.pop != pop;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Отклик на нажатие
// ─────────────────────────────────────────────────────────────────────────────

/// Чем кнопка отвечает после нажатия: загрузкой, галочкой «скопировано»,
/// плашкой Togetherly+ (плитка платная) или ничем, кроме волны.
enum WatchFxAfter { none, spin, check, plus }

/// Цвет волны: по светлой карточке — белым, по тёмной — почти незаметно её
/// же подписью (белая волна высветляла бы чёрную плитку целиком).
Color watchRippleColor(Color bg, Color fg, double light) =>
    Hct.fromInt(bg.toARGB32()).tone < 40 ? fg.withValues(alpha: .06) : Colors.white.withValues(alpha: light);

/// Карточка с откликом. Нажал — карточка вдавливается, кнопка проседает в
/// «печенье»; отпустил — кнопка пружинит, от пальца по карточке идёт волна,
/// клетки узора подпрыгивают, потом итог ([WatchFxAfter]).
///
/// [onTap] задан — нажимается вся карточка, реагирует кнопка [focusId].
/// Иначе нажимаются только кнопки [WatchFxButton] внутри.
class WatchFx extends StatefulWidget {
  const WatchFx({
    super.key,
    required this.color,
    required this.radius,
    required this.rippleColor,
    required this.child,
    this.pressedScale = .975,
    this.onTap,
    this.focusId,
    this.after = WatchFxAfter.none,
    this.semanticLabel,
  });

  final Color color;
  final double radius;
  final Color rippleColor;
  final double pressedScale;
  final Widget child;
  final VoidCallback? onTap;
  final Object? focusId;
  final WatchFxAfter after;
  final String? semanticLabel;

  /// Окно анимации клеток: 500 мс самого прыжка плюс задержка до дальнего угла.
  static const double popWindowMs = 1300;

  static WatchFxState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WatchFxScope>()?.state;

  @override
  State<WatchFx> createState() => WatchFxState();
}

class WatchFxState extends State<WatchFx> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: Duration(milliseconds: WatchFx.popWindowMs.round()));

  Object? _pressId;
  Object? _springId;
  Object? _resultId;
  WatchFxAfter _result = WatchFxAfter.none;
  int _resultGen = 0;
  Timer? _resultTimer;
  Offset? _origin;
  Offset _rippleCenter = Offset.zero;
  double _rippleRadius = 0;

  Animation<double> get press => _press;
  Animation<double> get spring => _spring;
  Animation<double> get pop => _pop;
  Offset? get origin => _origin;
  Object? get pressId => _pressId;
  Object? get springId => _springId;

  /// Итог нажатия, если он сейчас показан у кнопки [id].
  WatchFxAfter resultFor(Object id) => _resultId == id ? _result : WatchFxAfter.none;

  /// Растёт с каждым новым итогом: по нему плашка Плюса заново качает замок.
  int get resultGen => _resultGen;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void down(Object id, Offset global) {
    setState(() {
      _pressId = id;
      _origin = global;
    });
    if (_still) {
      _press.value = 1;
    } else {
      _press.forward();
    }
  }

  void cancel() {
    if (_still) {
      _press.value = 0;
    } else {
      _press.reverse();
    }
  }

  void release(Object id, WatchFxAfter after, Offset global) {
    cancel();
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final c = box.globalToLocal(global);
      final w = box.size.width, h = box.size.height;
      _rippleCenter = c;
      _rippleRadius = math.sqrt(math.pow(math.max(c.dx, w - c.dx), 2) + math.pow(math.max(c.dy, h - c.dy), 2));
    }
    _resultTimer?.cancel();
    setState(() {
      _origin = global;
      _springId = id;
      _resultId = after == WatchFxAfter.none ? null : id;
      _result = after;
      _resultGen++;
    });
    if (!_still) {
      _spring.forward(from: 0);
      _ripple.forward(from: 0);
      _pop.forward(from: 0);
    }
    if (after != WatchFxAfter.none) {
      _resultTimer = Timer(Duration(milliseconds: after == WatchFxAfter.check ? 1200 : 1600), () {
        if (!mounted) return;
        setState(() {
          _resultId = null;
          _result = WatchFxAfter.none;
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _press.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) setState(() => _pressId = null);
    });
  }

  @override
  void dispose() {
    _resultTimer?.cancel();
    _press.dispose();
    _spring.dispose();
    _ripple.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    Widget surface = AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final p = Curves.easeInOutCubicEmphasized.transform(_pressId == null ? 0 : _press.value);
        final focusOwnsCard = widget.onTap != null || _pressId != null;
        return Transform.scale(scale: focusOwnsCard ? 1 - (1 - widget.pressedScale) * p : 1, child: child);
      },
      child: ClipRRect(
        borderRadius: r,
        child: ColoredBox(
          color: widget.color,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _RipplePainter(
                        anim: _ripple,
                        center: () => _rippleCenter,
                        radius: () => _rippleRadius,
                        color: widget.rippleColor,
                      ),
                    ),
                  ),
                ),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
    final tap = widget.onTap;
    if (tap != null) {
      final id = widget.focusId ?? this;
      surface = Semantics(
        button: true,
        label: widget.semanticLabel,
        onTap: tap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => down(id, d.globalPosition),
          onTapCancel: cancel,
          onTapUp: (d) {
            release(id, widget.after, d.globalPosition);
            tap();
          },
          child: surface,
        ),
      );
    }
    return _WatchFxScope(state: this, gen: Object.hash(_pressId, _springId, _resultId, _result, _resultGen), child: surface);
  }
}

class _WatchFxScope extends InheritedWidget {
  const _WatchFxScope({required this.state, required this.gen, required super.child});

  final WatchFxState state;
  final int gen;

  @override
  bool updateShouldNotify(_WatchFxScope old) => old.gen != gen;
}

/// Волна: круг от пальца до дальнего угла карточки за 750 мс, гаснет в
/// последние 30%.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.anim, required this.center, required this.radius, required this.color})
      : super(repaint: anim);

  final Animation<double> anim;
  final Offset Function() center;
  final double Function() radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    if (t <= 0 || t >= 1) return;
    final scale = Curves.easeInOutCubicEmphasized.transform(t);
    final fade = t < .7 ? 1.0 : 1 - Curves.easeInOutCubicEmphasized.transform((t - .7) / .3);
    canvas.drawCircle(center(), radius() * scale, Paint()..color = color.withValues(alpha: color.a * fade));
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.color != color || old.anim != anim;
}

final Morph _cookieMorph = Morph(MaterialShapes.circle, MaterialShapes.cookie12Sided);

/// Круг, который на нажатии перетекает в «печенье».
class _MorphClipper extends CustomClipper<Path> {
  const _MorphClipper(this.t);

  final double t;

  @override
  Path getClip(Size size) {
    final unit = t <= 0 ? (Path()..addOval(const Rect.fromLTWH(0, 0, 1, 1))) : _cookieMorph.toPath(progress: t);
    return unit.transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);
  }

  @override
  bool shouldReclip(_MorphClipper old) => old.t != t;
}

const Curve _springCurve = Cubic(.34, 1.56, .64, 1);

/// Круглая кнопка карточки. [onTap] задан — нажимается сама; без него она
/// только показывает отклик, когда нажали карточку целиком (кнопка
/// «играть» у кино, значок у игр).
class WatchFxButton extends StatelessWidget {
  const WatchFxButton({
    super.key,
    required this.id,
    required this.size,
    required this.color,
    required this.icon,
    required this.iconSize,
    required this.iconColor,
    required this.spinColor,
    this.spinInset = 11,
    this.spinWidth = 3,
    this.after = WatchFxAfter.spin,
    this.selfTap = false,
    this.onTap,
    this.tooltip,
  });

  final Object id;
  final double size;
  final Color color;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color spinColor;
  final double spinInset;
  final double spinWidth;
  final WatchFxAfter after;

  /// Кнопка ловит нажатие сама (кнопки плитки «С компьютера»).
  final bool selfTap;
  final VoidCallback? onTap;
  final String? tooltip;

  static const IconData _check = IconData(0xe668, fontFamily: SymbolCatalog.fontFamily);

  @override
  Widget build(BuildContext context) {
    final fx = WatchFx.maybeOf(context);
    final result = fx?.resultFor(id) ?? WatchFxAfter.none;
    final hideIcon = result == WatchFxAfter.spin || result == WatchFxAfter.check;
    const fade = Duration(milliseconds: 200);
    Widget face = SizedBox(
      width: size,
      height: size,
      child: ColoredBox(
        color: color,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              opacity: hideIcon ? 0 : 1,
              duration: fade,
              child: AnimatedScale(scale: hideIcon ? .5 : 1, duration: fade, child: Icon(icon, size: iconSize, color: iconColor)),
            ),
            if (after == WatchFxAfter.check)
              AnimatedOpacity(
                opacity: result == WatchFxAfter.check ? 1 : 0,
                duration: fade,
                child: AnimatedScale(
                  scale: result == WatchFxAfter.check ? 1 : .4,
                  duration: fade,
                  child: Icon(_check, size: iconSize, color: iconColor),
                ),
              ),
            if (after == WatchFxAfter.spin)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(spinInset),
                  child: AnimatedOpacity(
                    opacity: result == WatchFxAfter.spin ? 1 : 0,
                    duration: fade,
                    child: AnimatedScale(
                      scale: result == WatchFxAfter.spin ? 1 : .6,
                      duration: fade,
                      child: result == WatchFxAfter.spin ? _ArcSpinner(color: spinColor, width: spinWidth) : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (fx != null) {
      face = AnimatedBuilder(
        animation: Listenable.merge([fx.press, fx.spring]),
        builder: (context, child) {
          final p = fx.pressId == id ? Curves.easeInOutCubicEmphasized.transform(fx.press.value) : 0.0;
          double scale = 1 - .14 * p, turn = -18 * p;
          if (fx.springId == id && fx.spring.isAnimating) {
            final c = _springCurve.transform(fx.spring.value);
            scale = .86 + .14 * c;
            turn = -18 * (1 - c);
          }
          return Transform.rotate(
            angle: turn * math.pi / 180,
            child: Transform.scale(scale: scale, child: ClipPath(clipper: _MorphClipper(p), child: child)),
          );
        },
        child: face,
      );
    } else {
      face = ClipOval(child: face);
    }
    if (selfTap) {
      final tap = onTap;
      face = Semantics(
        button: true,
        label: tooltip,
        enabled: tap != null,
        onTap: tap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: tap == null || fx == null ? null : (d) => fx.down(id, d.globalPosition),
          onTapCancel: tap == null || fx == null ? null : fx.cancel,
          onTapUp: tap == null
              ? null
              : (d) {
                  fx?.release(id, after, d.globalPosition);
                  tap();
                },
          child: face,
        ),
      );
      if (tooltip != null) face = Tooltip(message: tooltip!, excludeFromSemantics: true, child: face);
    }
    return face;
  }
}

/// Кольцо загрузки на три четверти, оборот за 0,8 с — как в макете.
class _ArcSpinner extends StatefulWidget {
  const _ArcSpinner({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  State<_ArcSpinner> createState() => _ArcSpinnerState();
}

class _ArcSpinnerState extends State<_ArcSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: CustomPaint(painter: _ArcPainter(widget.color, widget.width), size: Size.infinite),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color, this.width);

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(width / 2);
    canvas.drawArc(
      r,
      math.pi / 4,
      math.pi * 1.5,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color || old.width != width;
}

/// Плашка «Togetherly+» платной плитки. На нажатии плитки сжимается к
/// левому краю; после — наливается цветом подписи, замок качается и
/// выезжает стрелка: дальше откроется экран Плюса.
class WatchPlusChip extends StatefulWidget {
  const WatchPlusChip({super.key, required this.id, required this.label, required this.fg, required this.bg});

  final Object id;
  final String label;
  final Color fg;
  final Color bg;

  @override
  State<WatchPlusChip> createState() => _WatchPlusChipState();
}

class _WatchPlusChipState extends State<WatchPlusChip> with SingleTickerProviderStateMixin {
  late final AnimationController _swing = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  int _seenGen = -1;

  @override
  void dispose() {
    _swing.dispose();
    super.dispose();
  }

  /// Качание замка: −16°, 12°, −5° и на место.
  static double _angle(double t) {
    const keys = [0.0, .25, .55, .8, 1.0];
    const vals = [0.0, -16.0, 12.0, -5.0, 0.0];
    for (var i = 1; i < keys.length; i++) {
      if (t <= keys[i]) {
        final u = Curves.easeInOutCubicEmphasized.transform((t - keys[i - 1]) / (keys[i] - keys[i - 1]));
        return vals[i - 1] + (vals[i] - vals[i - 1]) * u;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final fx = WatchFx.maybeOf(context);
    final on = fx?.resultFor(widget.id) == WatchFxAfter.plus;
    if (on && fx != null && fx.resultGen != _seenGen) {
      _seenGen = fx.resultGen;
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) _swing.forward(from: 0);
    }
    const dur = Duration(milliseconds: 300);
    final ink = on ? widget.bg : widget.fg;
    final chip = AnimatedContainer(
      duration: dur,
      curve: Curves.easeInOutCubicEmphasized,
      height: 32,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      decoration: BoxDecoration(
        color: on ? widget.fg : widget.fg.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _swing,
            builder: (context, child) => Transform.rotate(
              angle: _angle(_swing.value) * math.pi / 180,
              alignment: const Alignment(0, -.6),
              child: child,
            ),
            child: Icon(const IconData(0xe899, fontFamily: SymbolCatalog.fontFamily), size: 16, color: ink),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: dur,
              style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 12, fontWeight: FontWeight.w700, color: ink),
              child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          AnimatedContainer(
            duration: dur,
            curve: Curves.easeInOutCubicEmphasized,
            width: on ? 20 : 0,
            alignment: Alignment.centerRight,
            child: ClipRect(
              child: AnimatedOpacity(
                opacity: on ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(const IconData(0xe5c8, fontFamily: SymbolCatalog.fontFamily), size: 16, color: ink),
              ),
            ),
          ),
        ],
      ),
    );
    if (fx == null) return chip;
    return AnimatedBuilder(
      animation: fx.press,
      builder: (context, child) {
        final p = fx.pressId == widget.id ? Curves.easeInOutCubicEmphasized.transform(fx.press.value) : 0.0;
        return Transform.scale(scale: 1 - .06 * p, alignment: Alignment.centerLeft, child: child);
      },
      child: chip,
    );
  }
}
