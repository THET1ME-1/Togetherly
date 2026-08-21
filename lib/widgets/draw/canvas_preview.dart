import 'package:flutter/material.dart';

import '../../models/canvas_meta.dart';
import '../../models/draw_stroke.dart';
import '../../services/canvas_repository.dart';
import '../../services/canvas_storage_service.dart';
import 'stroke_painting.dart';

/// Плитка холста в галерее, нарисованная прямо из штрихов.
///
/// Зачем: снимок холста делается только при выходе с экрана рисования
/// (`_captureThumbnail`), поэтому у холста, в который человек ни разу не
/// заходил, плитка стояла пустой — с кисточкой вместо рисунка. Так выглядели и
/// холсты, которые рисовал партнёр, и все старые. Здесь плитка рисуется тем же
/// кодом, что и сам холст, поэтому заходить внутрь больше не нужно.
///
/// Снятый снимок остаётся главнее: он уже учитывает фон листа и картинки, а
/// это превью рисует только штрихи.

/// Сколько штрихов рисуем в плитке размером с ноготь.
///
/// У пары бывают холсты на сотню тысяч штрихов (самый большой — 185 946), и
/// рисовать их целиком ради миниатюры незачем: на 150 точках разница не видна,
/// а прокрутка галереи встанет. Берём начало — рисунок начинают с главного.
const int kPreviewStrokeLimit = 1500;

class CanvasPreviewPainter extends CustomPainter {
  CanvasPreviewPainter({required this.strokes, required this.meta});

  final List<DrawStroke> strokes;
  final CanvasMeta meta;

  /// Штрихи, которые реально попадут в плитку.
  List<DrawStroke> get visibleStrokes => strokes.length <= kPreviewStrokeLimit
      ? strokes
      : strokes.sublist(0, kPreviewStrokeLimit);

  @override
  void paint(Canvas canvas, Size size) {
    final visible = visibleStrokes;
    if (visible.isEmpty) return;

    final cols = meta.isPixel ? meta.pixelW : null;
    final rows = meta.isPixel ? meta.pixelH : null;

    // Ластик снимает краску, поэтому штрихи живут в своём слое — иначе он
    // выел бы и подложку плитки. Тот же приём, что на холсте и в повторе.
    final needsLayer = visible.any((s) => s.isEraser);
    if (needsLayer) canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in visible) {
      if (s.shapeType != null && s.points.length >= 2) {
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
    if (needsLayer) canvas.restore();
  }

  /// Во сколько раз плитка меньше листа, на котором рисовали.
  double _widthScale(Size size) {
    const drawnOn = 1000.0; // порядок величины холста в точках
    final scale = size.longestSide / drawnOn;
    return scale.clamp(0.12, 1.0);
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

  String get _key => '${widget.uid}|${widget.groupId}|${widget.meta.id}';

  @override
  void initState() {
    super.initState();
    _load();
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
        painter: CanvasPreviewPainter(strokes: strokes, meta: widget.meta),
        size: Size.infinite,
      ),
    );
  }
}
