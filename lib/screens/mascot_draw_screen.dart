import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../models/draw_stroke.dart';
import '../theme/app_theme.dart';

// ── Palette ──────────────────────────────────────────────────────────────────

const List<Color> _kPalette = [
  Color(0xFF000000), Color(0xFF374151), Color(0xFF6B7280), Color(0xFFD1D5DB),
  Color(0xFFFFFFFF), Color(0xFFEF4444), Color(0xFFF97316), Color(0xFFFBBF24),
  Color(0xFFEAB308), Color(0xFF84CC16), Color(0xFF22C55E), Color(0xFF10B981),
  Color(0xFF06B6D4), Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF8B5CF6),
  Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFF92400E), Color(0xFF065F46),
];

enum _Tool { brush, eraser, line, rect, circle, fill }

// ── Flood-fill data classes (top-level for compute isolate) ──────────────────

class _FillLayer {
  final ui.Image img;
  final int order;
  _FillLayer(this.img, this.order);
}

// Must be top-level for Flutter's compute()
Uint8List _doFloodFill(Map<String, dynamic> args) {
  final pixels = args['pixels'] as Uint8List;
  final w = args['w'] as int;
  final h = args['h'] as int;
  final tx = args['tx'] as int;
  final ty = args['ty'] as int;
  final fillR = args['fillR'] as int;
  final fillG = args['fillG'] as int;
  final fillB = args['fillB'] as int;

  final startIdx = (ty * w + tx) * 4;
  final targetR = pixels[startIdx];
  final targetG = pixels[startIdx + 1];
  final targetB = pixels[startIdx + 2];

  // No-op if target is already the fill colour
  if (targetR == fillR && targetG == fillG && targetB == fillB) return pixels;

  const tolerance = 35;

  // BFS using a list as a queue (head pointer to avoid O(n) removeFirst)
  final queue = <int>[ty * w + tx];
  int head = 0;
  final visited = Uint8List(w * h);

  while (head < queue.length) {
    final pos = queue[head++];
    if (visited[pos] != 0) continue;
    visited[pos] = 1;

    final x = pos % w;
    final y = pos ~/ w;
    final idx = pos * 4;

    if ((pixels[idx] - targetR).abs() > tolerance ||
        (pixels[idx + 1] - targetG).abs() > tolerance ||
        (pixels[idx + 2] - targetB).abs() > tolerance) continue;

    pixels[idx] = fillR;
    pixels[idx + 1] = fillG;
    pixels[idx + 2] = fillB;
    pixels[idx + 3] = 255;

    if (x > 0) queue.add(pos - 1);
    if (x < w - 1) queue.add(pos + 1);
    if (y > 0) queue.add(pos - w);
    if (y < h - 1) queue.add(pos + w);
  }
  return pixels;
}

// ── Result returned when the user saves ─────────────────────────────────────

class MascotDrawResult {
  final Uint8List pngBytes;
  final String name;
  MascotDrawResult({required this.pngBytes, required this.name});
}

// ── Screen ───────────────────────────────────────────────────────────────────

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

  // Fill layers (flood-fill results stored as images)
  final List<_FillLayer> _fillLayers = [];
  final List<_FillLayer> _fillRedoStack = [];
  bool _isFilling = false;

  // Reference image — shown as a semi-transparent guide OUTSIDE RepaintBoundary
  // so it is NEVER included in the exported PNG.
  ui.Image? _refImage;
  bool _showRef = true;

  // Tool state
  _Tool _tool = _Tool.brush;
  Color _color = Colors.black;
  double _strokeWidth = 6.0;
  bool _fillShapes = false;

  bool _saving = false;

  // Canvas transform (two-finger gestures cover the whole canvas area)
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
      _loadRefImage(widget.initialPngBytes!);
    }
  }

  Future<void> _loadRefImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _refImage = frame.image);
  }

  // ── Drawing ──────────────────────────────────────────────────────────────

  bool get _isShapeTool =>
      _tool == _Tool.line || _tool == _Tool.rect || _tool == _Tool.circle;

  DrawShapeType? get _activeShape => switch (_tool) {
        _Tool.line => DrawShapeType.line,
        _Tool.rect => DrawShapeType.rect,
        _Tool.circle => DrawShapeType.circle,
        _ => null,
      };

  void _onPointerDown(PointerDownEvent e, Size canvasSize) {
    _activePointers++;
    if (_activePointers > 1) {
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
    _fillRedoStack.clear();
    _currentPoints.clear();
    setState(() {});
  }

  DrawPoint _normalize(Offset local, Size size) => DrawPoint(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  // ── Flood fill ───────────────────────────────────────────────────────────

  Future<void> _applyFill(Size canvasSize, Offset tapLocal) async {
    if (_isFilling) return;
    setState(() => _isFilling = true);
    try {
      final w = canvasSize.width.round();
      final h = canvasSize.height.round();

      // Render current canvas state to off-screen image
      final recorder = ui.PictureRecorder();
      final offCanvas = Canvas(recorder);
      // White background (so the fill correctly sees stroke boundaries)
      offCanvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = Colors.white,
      );
      _MascotCanvasPainter(
        strokes: _strokes,
        fillLayers: _fillLayers,
        currentPoints: const [],
        currentColor: Colors.black,
        currentWidth: 1,
        isEraser: false,
        shapeType: null,
        fillShapes: false,
        canvasSize: canvasSize.width,
      ).paint(offCanvas, Size(w.toDouble(), h.toDouble()));

      final picture = recorder.endRecording();
      final snapshot = await picture.toImage(w, h);
      final byteData =
          await snapshot.toByteData(format: ui.ImageByteFormat.rawRgba);
      snapshot.dispose();
      if (byteData == null || !mounted) return;

      final pixels = Uint8List.fromList(byteData.buffer.asUint8List());
      final tx = tapLocal.dx.round().clamp(0, w - 1);
      final ty = tapLocal.dy.round().clamp(0, h - 1);

      // Flood fill in a background isolate so the UI stays responsive
      final filled = await compute(_doFloodFill, {
        'pixels': pixels,
        'w': w,
        'h': h,
        'tx': tx,
        'ty': ty,
        'fillR': _color.red,
        'fillG': _color.green,
        'fillB': _color.blue,
      });

      // Decode filled pixels back to ui.Image
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          filled, w, h, ui.PixelFormat.rgba8888, completer.complete);
      final fillImage = await completer.future;

      if (!mounted) {
        fillImage.dispose();
        return;
      }
      setState(() {
        _fillLayers.add(_FillLayer(fillImage, _orderCounter++));
        _redoStack.clear();
        _fillRedoStack.clear();
      });
    } catch (e) {
      debugPrint('[Fill] error: $e');
    } finally {
      if (mounted) setState(() => _isFilling = false);
    }
  }

  // ── History (undo/redo handles both strokes and fill layers) ─────────────

  void _undo() {
    final lastStroke = _strokes.isEmpty ? -1 : _strokes.last.orderIndex;
    final lastFill = _fillLayers.isEmpty ? -1 : _fillLayers.last.order;
    if (lastStroke == -1 && lastFill == -1) return;
    setState(() {
      if (lastFill > lastStroke) {
        _fillRedoStack.add(_fillLayers.removeLast());
      } else {
        _redoStack.add(_strokes.removeLast());
      }
    });
  }

  void _redo() {
    final redoStroke = _redoStack.isEmpty ? -1 : _redoStack.last.orderIndex;
    final redoFill =
        _fillRedoStack.isEmpty ? -1 : _fillRedoStack.last.order;
    if (redoStroke == -1 && redoFill == -1) return;
    setState(() {
      if (redoFill > redoStroke) {
        _fillLayers.add(_fillRedoStack.removeLast());
      } else {
        _strokes.add(_redoStack.removeLast());
      }
    });
  }

  void _clear() {
    setState(() {
      _redoStack.addAll(_strokes.reversed);
      _strokes.clear();
      _fillRedoStack.addAll(_fillLayers.reversed);
      _fillLayers.clear();
    });
  }

  bool get _canUndo => _strokes.isNotEmpty || _fillLayers.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty || _fillRedoStack.isNotEmpty;

  // ── Canvas transform (two-finger, works over entire canvas area) ─────────

  void _onScaleStart(ScaleStartDetails _) {
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

  void _resetTransform() => setState(() {
        _canvasScale = 1.0;
        _canvasRotation = 0.0;
        _canvasPan = Offset.zero;
      });

  bool get _isTransformed =>
      _canvasScale != 1.0 ||
      _canvasRotation != 0.0 ||
      _canvasPan != Offset.zero;

  // ── Reference image ──────────────────────────────────────────────────────

  Future<void> _pickRefImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _refImage = frame.image;
        _showRef = true;
      });
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_strokes.isEmpty && _fillLayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нарисуйте что-нибудь сначала')),
      );
      return;
    }
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
    final controller = TextEditingController(text: widget.initialName ?? '');
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
                  child: CircularProgressIndicator(strokeWidth: 2)),
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
          // Canvas area — GestureDetector covers the ENTIRE area so two-finger
          // zoom/rotate/pan works even outside the canvas square.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onDoubleTap: _resetTransform,
              child: Center(child: _buildCanvas()),
            ),
          ),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight) - 16;
        return Transform.translate(
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
                child: Stack(
                  children: [
                    // Reference image — rendered OUTSIDE RepaintBoundary so it
                    // is NEVER included in the exported PNG.
                    if (_refImage != null && _showRef)
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.35,
                          child: RawImage(
                            image: _refImage!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    // Drawing canvas — only strokes and fill layers are exported.
                    RepaintBoundary(
                      key: _canvasKey,
                      child: Listener(
                        onPointerDown: (e) =>
                            _onPointerDown(e, Size(side, side)),
                        onPointerMove: (e) =>
                            _onPointerMove(e, Size(side, side)),
                        onPointerUp: (e) =>
                            _onPointerUp(e, Size(side, side)),
                        child: CustomPaint(
                          size: Size(side, side),
                          painter: _MascotCanvasPainter(
                            strokes: _strokes,
                            fillLayers: _fillLayers,
                            currentPoints: _currentPoints,
                            currentColor: _color,
                            currentWidth: _strokeWidth,
                            isEraser: _tool == _Tool.eraser,
                            shapeType: _activeShape,
                            fillShapes: _fillShapes,
                            canvasSize: side,
                          ),
                        ),
                      ),
                    ),
                    // Filling spinner overlay
                    if (_isFilling)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x22000000),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
                  ],
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
                  onTap: _canUndo ? _undo : null,
                ),
                _ToolBtn(
                  icon: Icons.redo,
                  label: 'Повтор',
                  active: false,
                  color: Colors.grey,
                  onTap: _canRedo ? _redo : null,
                ),
                _ToolBtn(
                  icon: Icons.delete_outline,
                  label: 'Очистить',
                  active: false,
                  color: Colors.red.shade300,
                  onTap: _canUndo ? _clear : null,
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
          // Stroke size slider
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
          // Colour palette
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
                        color:
                            selected ? _t.primary : Colors.grey.shade300,
                        width: selected ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: _t.primary.withAlpha(80),
                                blurRadius: 4,
                              )
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isTransformed)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
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

// ── Tool button ───────────────────────────────────────────────────────────────

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

// ── Canvas painter ────────────────────────────────────────────────────────────

class _MascotCanvasPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<_FillLayer> fillLayers;
  final List<DrawPoint> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final bool isEraser;
  final DrawShapeType? shapeType;
  final bool fillShapes;
  final double canvasSize;

  const _MascotCanvasPainter({
    required this.strokes,
    required this.fillLayers,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.isEraser,
    required this.shapeType,
    required this.fillShapes,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Merge strokes and fill layers, render in creation order.
    final items = <(int order, Object item)>[
      for (final s in strokes) (s.orderIndex, s as Object),
      for (final f in fillLayers) (f.order, f as Object),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    for (final (_, item) in items) {
      if (item is DrawStroke) {
        _drawStroke(canvas, size, item);
      } else if (item is _FillLayer) {
        final src = Rect.fromLTWH(
            0, 0, item.img.width.toDouble(), item.img.height.toDouble());
        final dst = Rect.fromLTWH(0, 0, size.width, size.height);
        canvas.drawImageRect(item.img, src, dst, Paint());
      }
    }

    // In-progress stroke
    if (currentPoints.isNotEmpty) {
      _drawStroke(
        canvas,
        size,
        DrawStroke(
          id: '_live',
          userId: 'local',
          colorValue: currentColor.toARGB32(),
          strokeWidth: currentWidth,
          points: currentPoints,
          isEraser: isEraser,
          isFilledShape: fillShapes && shapeType != null,
          shapeType: shapeType,
          orderIndex: 0,
        ),
      );
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
      _drawShape(
        canvas,
        paint,
        stroke.shapeType!,
        Offset(p1.x * size.width, p1.y * size.height),
        Offset(p2.x * size.width, p2.y * size.height),
        stroke.isFilledShape,
      );
      return;
    }

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

    final path = Path()
      ..moveTo(pts[0].x * size.width, pts[0].y * size.height);
    for (int i = 1; i < pts.length - 1; i++) {
      final midX = (pts[i].x + pts[i + 1].x) / 2 * size.width;
      final midY = (pts[i].y + pts[i + 1].y) / 2 * size.height;
      path.quadraticBezierTo(
        pts[i].x * size.width, pts[i].y * size.height, midX, midY,
      );
    }
    path.lineTo(pts.last.x * size.width, pts.last.y * size.height);
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
            RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
      case DrawShapeType.circle:
        canvas.drawOval(rect, paint);
      case DrawShapeType.triangle:
        canvas.drawPath(
          Path()
            ..moveTo((start.dx + end.dx) / 2, start.dy)
            ..lineTo(end.dx, end.dy)
            ..lineTo(start.dx, end.dy)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_MascotCanvasPainter old) => true;
}
