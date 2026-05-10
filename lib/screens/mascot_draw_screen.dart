import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../models/draw_stroke.dart';
import '../theme/app_theme.dart';

// ── Palette (same as shared draw screen) ────────────────────────────────────

const List<Color> _kPalette = [
  Color(0xFF000000), Color(0xFF374151), Color(0xFF6B7280), Color(0xFFD1D5DB),
  Color(0xFFFFFFFF), Color(0xFFEF4444), Color(0xFFF97316), Color(0xFFFBBF24),
  Color(0xFFEAB308), Color(0xFF84CC16), Color(0xFF22C55E), Color(0xFF10B981),
  Color(0xFF06B6D4), Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF8B5CF6),
  Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFF92400E), Color(0xFF065F46),
];

enum _Tool { brush, eraser, line, rect, circle, fill }

// ── Result returned when the user saves ─────────────────────────────────────

class MascotDrawResult {
  final Uint8List pngBytes;
  final String name;
  MascotDrawResult({required this.pngBytes, required this.name});
}

// ── Screen ───────────────────────────────────────────────────────────────────

/// Standalone drawing canvas for creating a mascot PNG.
/// Returns [MascotDrawResult] via Navigator.pop when the user saves.
/// Pass [initialPngBytes] to edit an existing mascot.
class MascotDrawScreen extends StatefulWidget {
  final AppTheme theme;
  final String? initialName;
  final Uint8List? initialPngBytes;
  final bool isGalleryFull;

  const MascotDrawScreen({
    super.key,
    required this.theme,
    this.initialName,
    this.initialPngBytes,
    this.isGalleryFull = false,
  });

  @override
  State<MascotDrawScreen> createState() => _MascotDrawScreenState();
}

class _MascotDrawScreenState extends State<MascotDrawScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  // Strokes
  final List<DrawStroke> _strokes = [];
  final List<DrawStroke> _redoStack = [];
  final List<DrawPoint> _currentPoints = [];
  int _orderCounter = 0;

  // Reference image (not exported)
  ui.Image? _refImage;
  bool _showRef = true;

  // Tool state
  _Tool _tool = _Tool.brush;
  Color _color = Colors.black;
  double _strokeWidth = 6.0;
  bool _fillShapes = false;

  bool _saving = false;

  // Canvas transform (zoom + rotate + pan via two-finger gestures)
  double _canvasScale = 1.0;
  double _canvasRotation = 0.0;
  Offset _canvasPan = Offset.zero;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  int _activePointers = 0;

  AppTheme get _t => widget.theme;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.initialPngBytes != null) {
      _loadInitialImage(widget.initialPngBytes!);
    }
  }

  Future<void> _loadInitialImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() => _refImage = frame.image);
  }

  // ── Drawing ──────────────────────────────────────────────────────────────

  bool get _isShapeTool =>
      _tool == _Tool.line || _tool == _Tool.rect || _tool == _Tool.circle;

  DrawShapeType? get _activeShape {
    return switch (_tool) {
      _Tool.line => DrawShapeType.line,
      _Tool.rect => DrawShapeType.rect,
      _Tool.circle => DrawShapeType.circle,
      _ => null,
    };
  }

  void _onPointerDown(PointerDownEvent e, Size canvasSize) {
    _activePointers++;
    if (_activePointers > 1) {
      // Second finger down — cancel any in-progress stroke and let scale gesture take over
      _currentPoints.clear();
      setState(() {});
      return;
    }
    if (_tool == _Tool.fill) {
      _applyFill(canvasSize, e.localPosition);
      return;
    }
    final pt = _normalize(e.localPosition, canvasSize);
    _currentPoints.clear();
    _currentPoints.add(pt);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e, Size canvasSize) {
    if (_activePointers != 1) return;
    if (_tool == _Tool.fill) return;
    final pt = _normalize(e.localPosition, canvasSize);
    _currentPoints.add(pt);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent e, Size canvasSize) {
    final wasDrawing = _activePointers == 1;
    _activePointers = math.max(0, _activePointers - 1);
    if (!wasDrawing || _tool == _Tool.fill || _currentPoints.isEmpty) {
      if (_activePointers == 0) _currentPoints.clear();
      return;
    }

    final pts = List<DrawPoint>.from(_currentPoints);
    final stroke = DrawStroke(
      id: 'local_${_orderCounter++}',
      userId: 'local',
      colorValue: _color.toARGB32(),
      strokeWidth: _strokeWidth,
      points: pts,
      isEraser: _tool == _Tool.eraser,
      isFilledShape: _fillShapes && _isShapeTool,
      shapeType: _activeShape,
      orderIndex: _orderCounter,
    );

    _strokes.add(stroke);
    _redoStack.clear();
    _currentPoints.clear();
    setState(() {});
  }

  DrawPoint _normalize(Offset local, Size size) {
    return DrawPoint(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _applyFill(Size canvasSize, Offset tap) {
    final fillStroke = DrawStroke(
      id: 'fill_${_orderCounter++}',
      userId: 'local',
      colorValue: _color.toARGB32(),
      strokeWidth: 1,
      points: [
        const DrawPoint(0, 0),
        const DrawPoint(1, 0),
        const DrawPoint(1, 1),
        const DrawPoint(0, 1),
      ],
      isEraser: false,
      isFilledShape: true,
      shapeType: DrawShapeType.rect,
      orderIndex: _orderCounter,
    );
    setState(() {
      _strokes.insert(0, fillStroke);
      _redoStack.clear();
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redoStack.add(_strokes.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _strokes.add(_redoStack.removeLast());
    });
  }

  void _clear() {
    setState(() {
      _redoStack.addAll(_strokes.reversed);
      _strokes.clear();
    });
  }

  // ── Canvas transform gestures ────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _canvasScale;
    _baseRotation = _canvasRotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    setState(() {
      _canvasScale = (_baseScale * details.scale).clamp(0.3, 5.0);
      _canvasRotation = _baseRotation + details.rotation;
      _canvasPan += details.focalPointDelta;
    });
  }

  // ── Reference image ──────────────────────────────────────────────────────

  Future<void> _pickRefImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    setState(() {
      _refImage = frame.image;
      _showRef = true;
    });
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нарисуйте что-нибудь сначала')),
      );
      return;
    }

    // Ask for name
    final name = await _showNameDialog();
    if (name == null) return;

    setState(() => _saving = true);
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Canvas not found');

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('PNG conversion failed');

      if (!mounted) return;
      Navigator.of(context).pop(
        MascotDrawResult(
          pngBytes: byteData.buffer.asUint8List(),
          name: name,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController(
      text: widget.initialName ?? '',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя маскота'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: 'Введите имя'),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.of(ctx).pop(n);
            },
            child: Text('Сохранить', style: TextStyle(color: _t.primary)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Нарисовать маскота',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: widget.isGalleryFull ? null : _save,
              child: Text(
                'Сохранить',
                style: TextStyle(
                  color: widget.isGalleryFull ? Colors.grey : _t.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.isGalleryFull)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Достигнут лимит. Удалите маскота из галереи.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // Canvas
          Expanded(
            child: Center(
              child: _buildCanvas(),
            ),
          ),
          // Toolbar
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight) - 16;
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onDoubleTap: () => setState(() {
            _canvasScale = 1.0;
            _canvasRotation = 0.0;
            _canvasPan = Offset.zero;
          }),
          child: Transform.translate(
            offset: _canvasPan,
            child: Transform(
              transform: Matrix4.identity()
                ..rotateZ(_canvasRotation)
                ..scale(_canvasScale),
              alignment: Alignment.center,
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: Listener(
                      onPointerDown: (e) => _onPointerDown(e, Size(side, side)),
                      onPointerMove: (e) => _onPointerMove(e, Size(side, side)),
                      onPointerUp: (e) => _onPointerUp(e, Size(side, side)),
                      child: CustomPaint(
                        size: Size(side, side),
                        painter: _MascotCanvasPainter(
                          strokes: _strokes,
                          currentPoints: _currentPoints,
                          currentColor: _color,
                          currentWidth: _strokeWidth,
                          isEraser: _tool == _Tool.eraser,
                          shapeType: _activeShape,
                          fillShapes: _fillShapes,
                          refImage: _showRef ? _refImage : null,
                          canvasSize: side,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 4,
        top: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tool row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _ToolBtn(
                  icon: Icons.brush,
                  label: 'Кисть',
                  active: _tool == _Tool.brush,
                  color: _t.primary,
                  onTap: () => setState(() => _tool = _Tool.brush),
                ),
                _ToolBtn(
                  icon: Icons.auto_fix_normal,
                  label: 'Ластик',
                  active: _tool == _Tool.eraser,
                  color: _t.primary,
                  onTap: () => setState(() => _tool = _Tool.eraser),
                ),
                _ToolBtn(
                  icon: Icons.format_color_fill,
                  label: 'Заливка',
                  active: _tool == _Tool.fill,
                  color: _t.primary,
                  onTap: () => setState(() => _tool = _Tool.fill),
                ),
                _ToolBtn(
                  icon: Icons.horizontal_rule,
                  label: 'Линия',
                  active: _tool == _Tool.line,
                  color: _t.primary,
                  onTap: () => setState(() => _tool = _Tool.line),
                ),
                _ToolBtn(
                  icon: Icons.rectangle_outlined,
                  label: 'Прямоугольник',
                  active: _tool == _Tool.rect,
                  color: _t.primary,
                  onTap: () => setState(() => _tool = _Tool.rect),
                ),
                _ToolBtn(
                  icon: Icons.circle_outlined,
                  label: 'Круг',
                  active: _tool == _Tool.circle,
                  color: _t.primary,
                  onTap: () => setState(() => _tool = _Tool.circle),
                ),
                if (_isShapeTool)
                  _ToolBtn(
                    icon: _fillShapes
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    label: 'Заполнить',
                    active: _fillShapes,
                    color: _t.primary,
                    onTap: () => setState(() => _fillShapes = !_fillShapes),
                  ),
                const SizedBox(width: 8),
                _ToolBtn(
                  icon: Icons.undo,
                  label: 'Отмена',
                  active: false,
                  color: Colors.grey,
                  onTap: _strokes.isNotEmpty ? _undo : null,
                ),
                _ToolBtn(
                  icon: Icons.redo,
                  label: 'Повтор',
                  active: false,
                  color: Colors.grey,
                  onTap: _redoStack.isNotEmpty ? _redo : null,
                ),
                _ToolBtn(
                  icon: Icons.delete_outline,
                  label: 'Очистить',
                  active: false,
                  color: Colors.red.shade300,
                  onTap: _strokes.isNotEmpty ? _clear : null,
                ),
                _ToolBtn(
                  icon: Icons.image_outlined,
                  label: 'Подложка',
                  active: _showRef && _refImage != null,
                  color: Colors.blue.shade400,
                  onTap: _pickRefImage,
                ),
                if (_refImage != null)
                  _ToolBtn(
                    icon: _showRef
                        ? Icons.visibility
                        : Icons.visibility_off_outlined,
                    label: _showRef ? 'Скрыть' : 'Показать',
                    active: false,
                    color: Colors.grey,
                    onTap: () => setState(() => _showRef = !_showRef),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Size slider
          Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.brush, size: 14, color: Colors.grey),
              Expanded(
                child: Slider(
                  value: _strokeWidth,
                  min: 1.0,
                  max: 40.0,
                  activeColor: _t.primary,
                  onChanged: (v) => setState(() => _strokeWidth = v),
                ),
              ),
              Text(
                '${_strokeWidth.round()}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 16),
            ],
          ),
          // Color palette
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _kPalette.length,
              itemBuilder: (ctx, i) {
                final c = _kPalette[i];
                final selected = c.toARGB32() == _color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? _t.primary : Colors.grey.shade300,
                        width: selected ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: _t.primary.withAlpha(80),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_canvasScale != 1.0 || _canvasRotation != 0.0 || _canvasPan != Offset.zero)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Двойной тап — сбросить вид',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Tool button ──────────────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback? onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : Colors.grey.shade200,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null
              ? Colors.grey.shade300
              : (active ? color : Colors.grey.shade600),
        ),
      ),
    );
  }
}

// ── Canvas painter ───────────────────────────────────────────────────────────

class _MascotCanvasPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final bool isEraser;
  final DrawShapeType? shapeType;
  final bool fillShapes;
  final ui.Image? refImage;
  final double canvasSize;

  const _MascotCanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.isEraser,
    required this.shapeType,
    required this.fillShapes,
    required this.refImage,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Reference image (semi-transparent, not exported)
    if (refImage != null) {
      final paint = Paint()..color = Colors.white.withAlpha(160);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, size.width, size.height),
        image: refImage!,
        fit: BoxFit.contain,
        opacity: 0.35,
      );
    }

    // Committed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, size, stroke);
    }

    // In-progress stroke
    if (currentPoints.isNotEmpty) {
      final liveStroke = DrawStroke(
        id: '_live',
        userId: 'local',
        colorValue: currentColor.toARGB32(),
        strokeWidth: currentWidth,
        points: currentPoints,
        isEraser: isEraser,
        isFilledShape: fillShapes && shapeType != null,
        shapeType: shapeType,
        orderIndex: 0,
      );
      _drawStroke(canvas, size, liveStroke);
    }
  }

  void _drawStroke(Canvas canvas, Size size, DrawStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..strokeWidth = stroke.strokeWidth * (size.width / 500.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (stroke.isEraser) {
      paint
        ..blendMode = BlendMode.clear
        ..color = Colors.transparent;
    } else {
      paint.color = Color(stroke.colorValue);
    }

    if (stroke.shapeType != null && stroke.points.length >= 2) {
      final p1 = stroke.points.first;
      final p2 = stroke.points.last;
      final start = Offset(p1.x * size.width, p1.y * size.height);
      final end = Offset(p2.x * size.width, p2.y * size.height);
      _drawShape(canvas, paint, stroke.shapeType!, start, end,
          stroke.isFilledShape);
      return;
    }

    final path = Path();
    final pts = stroke.points;
    if (pts.length == 1) {
      final p = pts.first;
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        stroke.strokeWidth * (size.width / 500.0) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    path.moveTo(pts[0].x * size.width, pts[0].y * size.height);
    for (int i = 1; i < pts.length - 1; i++) {
      final midX = (pts[i].x + pts[i + 1].x) / 2 * size.width;
      final midY = (pts[i].y + pts[i + 1].y) / 2 * size.height;
      path.quadraticBezierTo(
        pts[i].x * size.width,
        pts[i].y * size.height,
        midX,
        midY,
      );
    }
    final last = pts.last;
    path.lineTo(last.x * size.width, last.y * size.height);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  void _drawShape(Canvas canvas, Paint paint, DrawShapeType type,
      Offset start, Offset end, bool filled) {
    paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
    final rect = Rect.fromPoints(start, end);
    switch (type) {
      case DrawShapeType.line:
        paint.style = PaintingStyle.stroke;
        canvas.drawLine(start, end, paint);
      case DrawShapeType.rect:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          paint,
        );
      case DrawShapeType.circle:
        canvas.drawOval(rect, paint);
      case DrawShapeType.triangle:
        final path = Path()
          ..moveTo((start.dx + end.dx) / 2, start.dy)
          ..lineTo(end.dx, end.dy)
          ..lineTo(start.dx, end.dy)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MascotCanvasPainter old) => true;
}
