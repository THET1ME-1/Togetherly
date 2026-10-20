import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/canvas_meta.dart';
import '../../models/draw_stroke.dart';
import '../../services/canvas_repository.dart';
import '../../services/canvas_storage_service.dart';
import '../../utils/canvas_image_cache.dart';
import 'stroke_painting.dart';

/// Плитка холста в галерее, нарисованная прямо из штрихов.
///
/// Зачем: снимок холста делается только при выходе с экрана рисования
/// (`_captureThumbnail`), поэтому у холста, в который человек ни разу не
/// заходил, плитка стояла пустой — с кисточкой вместо рисунка. Так выглядели и
/// холсты, которые рисовал партнёр, и все старые. Здесь плитка рисуется тем же
/// кодом, что и сам холст, поэтому заходить внутрь больше не нужно.
///
/// Снятый снимок остаётся главнее: он уже учитывает фон листа. Это превью
/// рисует штрихи и картинки (заливки ведром и вставленные фото); картинки
/// до 20.10.2026 пропускались, и плитка раскраски стояла пустой.

/// Сколько штрихов рисуем в плитке размером с ноготь.
///
/// У пары бывают холсты на сотню тысяч штрихов (самый большой — 185 946), и
/// рисовать их целиком ради миниатюры незачем: на 150 точках разница не видна,
/// а прокрутка галереи встанет. Берём начало — рисунок начинают с главного.
const int kPreviewStrokeLimit = 1500;

/// Потолок, за который плитка не заходит даже ради ластика.
///
/// Ластик снимает краску с того, что нарисовано РАНЬШЕ, поэтому обрезка по
/// первым полутора тысячам штрихов возвращала на плитку всё стёртое: сами
/// мазки в срез попадали, а стиравший их ластик — уже нет. Теперь срез
/// тянется до последнего ластика, но не дальше этого числа: холст на сто
/// тысяч штрихов миниатюре всё равно не нужен.
const int kPreviewEraserLimit = 12000;

class CanvasPreviewPainter extends CustomPainter {
  CanvasPreviewPainter({
    required this.strokes,
    required this.meta,
    this.imageOf,
    Listenable? repaint,
  }) : super(repaint: repaint);

  final List<DrawStroke> strokes;
  final CanvasMeta meta;

  /// Растр заливки или вставленного фото, если он уже приехал. Без него
  /// плитка без снимка стояла пустой: в раскраске почти всё — заливки
  /// (20.10.2026).
  final ui.Image? Function(DrawStroke stroke)? imageOf;

  /// Штрихи, которые реально попадут в плитку.
  ///
  /// Срез идёт до последнего ластика в пределах [kPreviewEraserLimit]:
  /// иначе стёртое на миниатюре остаётся на месте.
  List<DrawStroke> get visibleStrokes {
    if (strokes.length <= kPreviewStrokeLimit) return strokes;

    final edge = strokes.length < kPreviewEraserLimit
        ? strokes.length
        : kPreviewEraserLimit;
    var end = kPreviewStrokeLimit;
    for (var i = edge - 1; i >= kPreviewStrokeLimit; i--) {
      if (strokes[i].isEraser) {
        end = i + 1;
        break;
      }
    }
    return strokes.sublist(0, end);
  }

  @override
  void paint(Canvas canvas, Size tile) {
    final visible = visibleStrokes;
    if (visible.isEmpty) return;

    final cols = meta.isPixel ? meta.pixelW : null;
    final rows = meta.isPixel ? meta.pixelH : null;

    // Лист рисуется в своих пропорциях и обрезается по краям плитки, как
    // снимок. Растянутый под плитку, он сдвигал заливку относительно линий:
    // линии тянулись вслед за плиткой, а картинка заливки сохраняла форму, и
    // рядом с линией белела дырка (20.10.2026).
    final size = _sheetSize(tile);
    canvas.save();
    canvas.clipRect(Offset.zero & tile);
    canvas.translate((tile.width - size.width) / 2, (tile.height - size.height) / 2);

    // Каждый слой рисунка — в своём saveLayer: ластик снимает краску только
    // своего слоя и не выедает ни нижние слои, ни подложку плитки. Тот же
    // приём, что на холсте и в повторе (20.10.2026).
    for (final layer in layersOf(visible)) {
      final own = [for (final s in visible) if (s.layer == layer) s];
      // Буфер нужен только слою с ластиком: остальной ложится прямо на плитку.
      final erases = own.any((s) => s.isEraser);
      if (erases) canvas.saveLayer(Offset.zero & size, Paint());
      _paintLayer(canvas, size, own, cols, rows);
      if (erases) canvas.restore();
    }
    canvas.restore();
  }

  /// Размер листа, накрывающего плитку целиком в пропорциях холста. У холста
  /// без листа пропорций нет — тогда лист и есть плитка.
  Size _sheetSize(Size tile) {
    final ratio = meta.effectiveRatio;
    if (ratio == null || ratio <= 0 || tile.isEmpty) return tile;
    if (tile.width / tile.height > ratio) {
      return Size(tile.width, tile.width / ratio);
    }
    return Size(tile.height * ratio, tile.height);
  }

  void _paintLayer(Canvas canvas, Size size, List<DrawStroke> visible, int? cols, int? rows) {
    for (final s in visible) {
      if (s.isImageStroke) {
        // Заливка и фото лежат в том же порядке, что и линии: так же, как на
        // холсте. Пока растр едет, картинки на плитке просто нет.
        final image = imageOf?.call(s);
        if (image != null) paintImageStroke(canvas, image, s, size);
      } else if (s.shapeType != null && s.points.length >= 2) {
        paintShape(
          canvas,
          s.points,
          s.colorValue,
          s.strokeWidth,
          s.shapeType!,
          size,
          isFilledShape: s.isFilledShape,
          pixelCols: cols,
          pixelRows: rows,
        );
      } else if (s.shapeType == null && s.points.isNotEmpty) {
        paintStroke(
          canvas,
          s.points,
          s.colorValue,
          // Толщина задана в точках холста, а плитка меньше листа в разы:
          // без пересчёта пара мазков закрашивала бы её целиком.
          s.strokeWidth * _widthScale(size),
          s.isEraser,
          size,
          pixelCols: cols,
          pixelRows: rows,
        );
      }
    }
  }

  /// Во сколько раз плитка меньше листа, на котором рисовали.
  ///
  /// Толщина линии записана в точках холста, а холст на телефоне около 400
  /// точек в ширину. До 20.10.2026 здесь стояла тысяча по длинной стороне:
  /// линия выходила в 2,5 раза тоньше дырки, которую она оставляет в заливке,
  /// и вокруг неё белел ободок.
  double _widthScale(Size size) {
    const drawnOn = 400.0; // ширина холста на телефоне в точках
    final scale = size.width / drawnOn;
    return scale.clamp(0.12, 2.0);
  }

  @override
  bool shouldRepaint(covariant CanvasPreviewPainter old) =>
      old.strokes != strokes || old.meta != meta;
}

/// Плитка, которая сама достаёт штрихи холста и рисует их.
///
/// Пока штрихи едут с диска, показывается [placeholder] — прежняя заглушка с
/// кисточкой. Ничего не нашлось (холст пустой или лежит только на сервере) —
/// заглушка и остаётся.
class CanvasPreview extends StatefulWidget {
  const CanvasPreview({
    super.key,
    required this.meta,
    required this.uid,
    required this.groupId,
    required this.placeholder,
    this.background,
  });

  final CanvasMeta meta;
  final String uid;
  final String groupId;
  final Widget placeholder;

  /// Подложка под штрихами: у плитки свой светлый фон, как у листа.
  final Color? background;

  @override
  State<CanvasPreview> createState() => _CanvasPreviewState();
}

class _CanvasPreviewState extends State<CanvasPreview> {
  /// Штрихи держим на весь экран галереи: прокрутка туда-обратно не должна
  /// каждый раз ходить на диск.
  static final Map<String, List<DrawStroke>> _cache = {};

  List<DrawStroke>? _strokes;

  /// Растры заливок, сжатые под плитку: в раскраске почти всё — заливки, и
  /// без них плитка стояла пустой (20.10.2026).
  final CanvasImageCache _images = CanvasImageCache(decodeSide: 480);

  String get _key => '${widget.uid}|${widget.groupId}|${widget.meta.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _images.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CanvasPreview old) {
    super.didUpdateWidget(old);
    if (old.meta.id != widget.meta.id) _load();
  }

  Future<void> _load() async {
    final cached = _cache[_key];
    if (cached != null) {
      setState(() => _strokes = cached);
      return;
    }
    var loaded = await CanvasStorageService.instance.loadLocalStrokes(
      widget.uid,
      widget.meta.id,
      groupId: widget.groupId,
    );

    // На диске пусто — значит холст рисовал партнёр, а этот телефон в него не
    // заходил ни разу. Тогда берём начало рисунка с сервера: плитка важнее
    // одного запроса, а иначе человек видит пустую карточку и думает, что
    // холст пустой.
    if (loaded.isEmpty && widget.groupId.isNotEmpty) {
      loaded = await CanvasRepository.instance
          .previewStrokes(widget.groupId, widget.meta.id);
    }

    _cache[_key] = loaded;
    if (mounted) setState(() => _strokes = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final strokes = _strokes;
    if (strokes == null || strokes.isEmpty) return widget.placeholder;
    return ColoredBox(
      color: widget.background ?? const Color(0xFFFFFFFF),
      child: CustomPaint(
        painter: CanvasPreviewPainter(
          strokes: strokes,
          meta: widget.meta,
          imageOf: _images.imageFor,
          repaint: _images,
        ),
        size: Size.infinite,
      ),
    );
  }
}
