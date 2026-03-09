import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/draw_stroke.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette & user colours
// ─────────────────────────────────────────────────────────────────────────────
const List<Color> _kPalette = [
  Color(0xFF000000),
  Color(0xFF6B7280),
  Color(0xFFFFFFFF),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFF472B6),
  Color(0xFF92400E),
  Color(0xFF065F46),
  Color(0xFF1E3A5F),
  Color(0xFFFFF7ED),
];

const List<Color> _kUserColors = [
  Color(0xFF3B82F6),
  Color(0xFFEC4899),
  Color(0xFF22C55E),
  Color(0xFFF97316),
];

// ─────────────────────────────────────────────────────────────────────────────
// DrawScreen
// ─────────────────────────────────────────────────────────────────────────────
class DrawScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final AppTheme theme;

  const DrawScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.theme,
  });

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  // ── Tool state ───────────────────────────────────────────────────────────
  DrawTool _activeTool = DrawTool.brush;
  late Color _activeColor;
  double _strokeWidth = 5.0;
  Color _bgColor = Colors.white;

  // ── Canvas data ──────────────────────────────────────────────────────────
  // Completed strokes received from Firestore
  List<DrawStroke> _strokes = [];

  // Mutable point list for the current in-progress gesture (no allocation per point)
  final List<DrawPoint> _currentPoints = [];
  int _currentColorValue = 0xFF000000;
  double _currentStrokeWidth = 5.0;
  bool _currentIsEraser = false;
  bool _isDrawing = false;

  // Partner live strokes keyed by uid
  final Map<String, DrawStroke?> _partnerLiveStrokes = {};

  // Canvas size — captured once by LayoutBuilder, eagerly set for first gesture
  Size _canvasSize = Size.zero;
  final _canvasKey = GlobalKey();

  // ValueNotifier drives canvas repaints without rebuilding the full widget tree
  final _repaintNotifier = ValueNotifier<int>(0);

  // ── Images ───────────────────────────────────────────────────────────────
  final Map<String, ui.Image> _imageCache = {};
  final _imagePicker = ImagePicker();
  bool _uploadingImage = false;

  // ── Undo / Redo ──────────────────────────────────────────────────────────
  final List<String> _myStrokeIds = [];
  final List<DrawStroke> _redoStack = [];

  // ── Firebase ─────────────────────────────────────────────────────────────
  final _fb = FirebaseService();
  StreamSubscription? _strokesSub;
  StreamSubscription? _liveSub;

  // Throttle live-push to at most 1 write per _liveThrottleMs milliseconds
  static const int _liveThrottleMs = 80;
  DateTime _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);

  int _orderCounter = 0;

  // ── UI ───────────────────────────────────────────────────────────────────
  bool _showHint = true;
  bool _saving = false;
  bool _sidebarVisible = true;

  // ── Zoom / Pan ────────────────────────────────────────────────────────────
  double _scale = 1.0;
  Offset _canvasOffset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  bool _isZooming = false;

  // ── Helpers ───────────────────────────────────────────────────────────────
  String get _myUid => widget.userData.uid;
  String get _groupId => widget.pairData.pairId;

  Color _colorForUser(String uid) {
    final members = widget.pairData.members;
    final idx = members.indexWhere((m) => m.uid == uid);
    if (idx < 0) return _kUserColors[0];
    return _kUserColors[idx % _kUserColors.length];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _activeColor = _colorForUser(_myUid);
    _currentColorValue = _activeColor.value;
    _startFirebaseListeners();
    // Auto-dismiss hint
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _strokesSub?.cancel();
    _liveSub?.cancel();
    _repaintNotifier.dispose();
    _clearLiveStroke(); // fire-and-forget
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Firebase
  // ─────────────────────────────────────────────────────────────────────────

  void _startFirebaseListeners() {
    if (_groupId.isEmpty) return;

    // Completed strokes
    _strokesSub = _fb
        .listenToDrawingStrokes(groupId: _groupId)
        .handleError((e) => debugPrint('[Draw] strokes error: $e'))
        .listen((rawList) {
          if (!mounted) return;
          final parsed = <DrawStroke>[];
          for (final r in rawList) {
            try {
              parsed.add(DrawStroke.fromFirestore(r.data, r.id));
            } catch (e) {
              debugPrint('[Draw] parse stroke error: $e');
            }
          }
          // Pre-load images
          for (final s in parsed) {
            if (s.isImageStroke &&
                s.imageUrl != null &&
                !_imageCache.containsKey(s.imageUrl)) {
              _loadNetworkImage(s.imageUrl!);
            }
          }
          if (parsed.isNotEmpty) {
            _orderCounter =
                parsed.map((s) => s.orderIndex).reduce(math.max) + 1;
          }
          setState(() => _strokes = parsed);
        });

    // Partner live strokes
    _liveSub = _fb
        .listenToLiveDrawingStrokes(groupId: _groupId, myUserId: _myUid)
        .handleError((e) => debugPrint('[Draw] live error: $e'))
        .listen((liveMap) {
          if (!mounted) return;
          bool changed = false;

          for (final entry in liveMap.entries) {
            final uid = entry.key;
            final data = entry.value;
            DrawStroke? stroke;
            try {
              stroke =
                  data.isEmpty ? null : DrawStroke.fromLiveMap(data, uid);
            } catch (e) {
              debugPrint('[Draw] parse live error: $e');
            }
            _partnerLiveStrokes[uid] = stroke;
            changed = true;
          }

          // Remove stale partners
          final toRemove = _partnerLiveStrokes.keys
              .where((uid) => !liveMap.containsKey(uid))
              .toList();
          for (final uid in toRemove) {
            _partnerLiveStrokes.remove(uid);
            changed = true;
          }

          if (changed) {
            // Only need repaint, not full rebuild
            _repaintNotifier.value++;
            setState(() {});
          }
        });
  }

  Future<void> _loadNetworkImage(String url) async {
    try {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
        },
        onError: (e, _) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );
      stream.addListener(listener);
      final img = await completer.future;
      stream.removeListener(listener);
      if (mounted) setState(() => _imageCache[url] = img);
    } catch (e) {
      debugPrint('[Draw] image load error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gestures
  // ─────────────────────────────────────────────────────────────────────────

  // ── Scale-aware gestures (1 finger = draw, 2 fingers = zoom/pan) ─────────

  /// Convert a touch position (local to GestureDetector) → canvas-space pixels.
  Offset _screenToCanvas(Offset screenLocal) =>
      (screenLocal - _canvasOffset) / _scale;

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount >= 2) {
      // Two fingers → zoom/pan; cancel any ongoing drawing
      _isZooming = true;
      if (_isDrawing) {
        _isDrawing = false;
        _currentPoints.clear();
        _clearLiveStroke();
        _repaintNotifier.value++;
      }
      _baseScale = _scale;
      _baseOffset = _canvasOffset;
      _baseFocalPoint = d.localFocalPoint;
      return;
    }

    // Single finger → draw
    _isZooming = false;
    if (_canvasSize.isEmpty) return;
    if (_activeTool == DrawTool.fill) {
      _applyFill();
      return;
    }
    _currentPoints
      ..clear()
      ..add(DrawPoint.fromOffset(_screenToCanvas(d.localFocalPoint), _canvasSize));
    _currentColorValue = _activeTool == DrawTool.eraser
        ? _bgColor.value
        : _activeColor.value;
    _currentStrokeWidth = _strokeWidth;
    _currentIsEraser = _activeTool == DrawTool.eraser;
    _isDrawing = true;
    _redoStack.clear();
    if (_showHint) setState(() => _showHint = false);
    _repaintNotifier.value++;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_isZooming || d.pointerCount >= 2) {
      _isZooming = true;
      final newScale = (_baseScale * d.scale).clamp(0.3, 8.0);
      // Keep the focal point anchored in canvas-space while scaling
      final focalCanvas = (_baseFocalPoint - _baseOffset) / _baseScale;
      final newOffset = d.localFocalPoint - focalCanvas * newScale;
      setState(() {
        _scale = newScale;
        _canvasOffset = newOffset;
      });
      return;
    }

    if (!_isDrawing || _canvasSize.isEmpty) return;
    _currentPoints.add(
        DrawPoint.fromOffset(_screenToCanvas(d.localFocalPoint), _canvasSize));
    _repaintNotifier.value++;

    final now = DateTime.now();
    if (now.difference(_lastLivePush).inMilliseconds >= _liveThrottleMs) {
      _lastLivePush = now;
      _pushLiveStroke();
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_isZooming) {
      _isZooming = false;
      return;
    }
    if (!_isDrawing) return;
    _isDrawing = false;
    _commitCurrentStroke();
  }

  void _commitCurrentStroke() {
    if (_currentPoints.length < 2) {
      // Single tap → draw a dot
      if (_currentPoints.length == 1 && !_currentIsEraser) {
        // Duplicate the point so the painter draws a circle
        _currentPoints.add(_currentPoints[0]);
      } else {
        _currentPoints.clear();
        _clearLiveStroke();
        _repaintNotifier.value++;
        return;
      }
    }

    // Snapshot before clearing (List.of makes an unmodifiable copy)
    final points = List<DrawPoint>.unmodifiable(_currentPoints);
    final colorValue = _currentColorValue;
    final sw = _currentStrokeWidth;
    final isEraser = _currentIsEraser;
    final order = _orderCounter;

    _currentPoints.clear();
    _clearLiveStroke();
    _orderCounter++;

    // ── Optimistic update ──────────────────────────────────────────────────
    // Add the stroke to the local list immediately so the canvas keeps
    // showing it while the Firestore write happens in the background.
    // The Firestore listener will later replace it with the confirmed copy.
    final tempId = '_temp_${DateTime.now().millisecondsSinceEpoch}';
    final stroke = DrawStroke(
      id: tempId,
      userId: _myUid,
      colorValue: colorValue,
      strokeWidth: sw,
      points: points,
      isEraser: isEraser,
      orderIndex: order,
    );
    setState(() {
      _strokes = [..._strokes, stroke];
    });

    _fb
        .addDrawingStroke(
          groupId: _groupId,
          strokeData: stroke.toFirestore(),
        )
        .then((id) {
          if (id.isNotEmpty && mounted) _myStrokeIds.add(id);
        })
        .catchError((e) {
          debugPrint('[Draw] commit error: $e');
          // Roll back the optimistic stroke if Firebase rejected the write
          if (mounted) {
            setState(() {
              _strokes = _strokes.where((s) => s.id != tempId).toList();
            });
          }
        });
  }

  void _pushLiveStroke() {
    if (_groupId.isEmpty || _currentPoints.isEmpty) return;
    final data = <String, dynamic>{
      'userId': _myUid,
      'colorValue': _currentColorValue,
      'strokeWidth': _currentStrokeWidth,
      'isEraser': _currentIsEraser,
      'points': _currentPoints.map((p) => {'x': p.x, 'y': p.y}).toList(),
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _fb
        .updateLiveDrawingStroke(
          groupId: _groupId,
          userId: _myUid,
          liveData: data,
        )
        .catchError((e) => debugPrint('[Draw] live push error: $e'));
  }

  void _clearLiveStroke() {
    if (_groupId.isEmpty) return;
    _fb
        .clearLiveDrawingStroke(groupId: _groupId, userId: _myUid)
        .catchError((e) => debugPrint('[Draw] clear live error: $e'));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Undo / Redo
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _undo() async {
    if (_myStrokeIds.isEmpty) return;
    final id = _myStrokeIds.removeLast();
    final removed = _strokes.where((s) => s.id == id).firstOrNull;
    if (removed != null) _redoStack.add(removed);
    setState(() {});
    try {
      await _fb.deleteDrawingStroke(groupId: _groupId, strokeId: id);
    } catch (e) {
      debugPrint('[Draw] undo error: $e');
      _myStrokeIds.add(id); // rollback
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final stroke = _redoStack.removeLast();
    setState(() {});
    try {
      final id = await _fb.addDrawingStroke(
        groupId: _groupId,
        strokeData: stroke.toFirestore(),
      );
      if (id.isNotEmpty) {
        _myStrokeIds.add(id);
        _orderCounter++;
      }
    } catch (e) {
      debugPrint('[Draw] redo error: $e');
      _redoStack.add(stroke); // rollback
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fill / Clear / Photo
  // ─────────────────────────────────────────────────────────────────────────

  void _applyFill() => setState(() => _bgColor = _activeColor);

  Future<void> _confirmClear() async {
    final s = LocaleService.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s.clearCanvas),
        content: Text(s.clearCanvasConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(s.clearCanvas),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      // Snapshot for rollback in case Firebase fails
      final previousStrokes = List<DrawStroke>.from(_strokes);
      final previousBg = _bgColor;
      _myStrokeIds.clear();
      _redoStack.clear();
      // Optimistic clear — canvas is empty immediately
      setState(() {
        _strokes = [];
        _bgColor = Colors.white;
      });
      try {
        await _fb.clearDrawingCanvas(groupId: _groupId);
      } catch (e) {
        debugPrint('[Draw] clear error: $e');
        // Rollback if Firebase rejected the delete
        if (mounted) {
          setState(() {
            _strokes = previousStrokes;
            _bgColor = previousBg;
          });
        }
      }
    }
  }

  Future<void> _insertPhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1200,
      );
      if (picked == null || !mounted) return;

      setState(() => _uploadingImage = true);
      String? url;
      try {
        url = await _fb.uploadDrawingImage(
          groupId: _groupId,
          localPath: picked.path,
        );
      } finally {
        if (mounted) setState(() => _uploadingImage = false);
      }
      if (url == null || url.isEmpty || !mounted) return;

      final img = await _decodeImageFromFile(picked.path);
      final ar = (img != null && img.height > 0)
          ? img.width / img.height
          : 1.0;
      const w = 0.8;
      final h = (w / ar).clamp(0.01, 1.0);
      final x = (1.0 - w) / 2;
      final y = ((1.0 - h) / 2).clamp(0.0, 0.99);

      final stroke = DrawStroke(
        id: 'local',
        userId: _myUid,
        colorValue: 0xFF000000,
        strokeWidth: 0,
        points: const [],
        orderIndex: _orderCounter,
        imageUrl: url,
        imageX: x,
        imageY: y,
        imageWidth: w,
        imageHeight: h,
      );
      final id = await _fb.addDrawingStroke(
        groupId: _groupId,
        strokeData: stroke.toFirestore(),
      );
      if (id.isNotEmpty) {
        _myStrokeIds.add(id);
        _orderCounter++;
      }
    } catch (e) {
      debugPrint('[Draw] insert photo error: $e');
    }
  }

  Future<ui.Image?> _decodeImageFromFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (img) {
        if (!completer.isCompleted) completer.complete(img);
      });
      return completer.future;
    } catch (e) {
      debugPrint('[Draw] decode error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Save / Share
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveOrShare({bool share = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _canvasKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      final bytes = bd.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: share ? '🎨 ${LocaleService.current.drawTogether}' : null,
      );
    } catch (e) {
      debugPrint('[Draw] save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(s, t),
            Expanded(
              child: Stack(
                children: [
                  // Canvas fills the entire area
                  Positioned.fill(child: _buildCanvasArea(s)),
                  // Floating transparent sidebar overlaid on left
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: _buildSidebar(s, t),
                  ),
                  // Toggle tab on the right edge of the sidebar
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    left: _sidebarVisible ? 58 : 0,
                    top: 0,
                    bottom: 0,
                    child: Center(child: _buildSidebarToggleBtn(t)),
                  ),
                ],
              ),
            ),
            _buildBottomColorBar(t),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Top bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(AppStrings s, AppTheme t) {
    final drawingPartners = _partnerLiveStrokes.entries
        .where((e) => (e.value?.points.length ?? 0) > 1)
        .map((e) {
          return widget.pairData.partners
                  .where((p) => p.uid == e.key)
                  .map((p) => p.name)
                  .firstOrNull ??
              '?';
        })
        .toList();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.drawTogether,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (drawingPartners.isNotEmpty)
                  Text(
                    s.partnerIsDrawing(drawingPartners.join(', ')),
                    style: TextStyle(
                        fontSize: 11,
                        color: t.primary,
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
          _topIconBtn(Icons.undo_rounded,
              _myStrokeIds.isNotEmpty ? _undo : null,
              tooltip: s.undoAction),
          _topIconBtn(Icons.redo_rounded,
              _redoStack.isNotEmpty ? _redo : null,
              tooltip: s.redoAction),
          _saving
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _topIconBtn(Icons.save_alt_rounded,
                  () => _saveOrShare(share: false),
                  tooltip: s.saveDrawing),
          _topIconBtn(Icons.share_rounded, () => _saveOrShare(share: true),
              tooltip: s.shareDrawing),
        ],
      ),
    );
  }

  Widget _topIconBtn(IconData icon, VoidCallback? onTap,
      {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon,
                size: 22,
                color: onTap != null
                    ? Colors.grey.shade700
                    : Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sidebar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSidebar(AppStrings s, AppTheme t) {
    return ClipRect(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: _sidebarVisible ? 58.0 : 0.0,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.80),
              border: Border(
                right: BorderSide(
                    color: Colors.white.withOpacity(0.4), width: 0.5),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _sidebarTool(
                    icon: Icons.brush_rounded,
                    tool: DrawTool.brush,
                    tooltip: s.brush,
                    t: t),
                _sidebarTool(
                    icon: Icons.auto_fix_normal_rounded,
                    tool: DrawTool.eraser,
                    tooltip: s.eraser,
                    t: t),
                _sidebarTool(
                    icon: Icons.format_color_fill_rounded,
                    tool: DrawTool.fill,
                    tooltip: s.fillBg,
                    t: t),
                const SizedBox(height: 4),
                Divider(
                    height: 1,
                    indent: 10,
                    endIndent: 10,
                    color: Colors.grey.shade300),
                const SizedBox(height: 8),
                _uploadingImage
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _sidebarIconBtn(
                        Icons.add_photo_alternate_rounded,
                        _insertPhoto,
                        tooltip: s.insertPhoto,
                      ),
                const SizedBox(height: 4),
                Divider(
                    height: 1,
                    indent: 10,
                    endIndent: 10,
                    color: Colors.grey.shade300),
                const SizedBox(height: 8),
                _buildThicknessBtn(s),
                const Spacer(),
                _sidebarIconBtn(
                  Icons.delete_outline_rounded,
                  _confirmClear,
                  tooltip: s.clearCanvas,
                  color: Colors.red.shade300,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarToggleBtn(AppTheme t) {
    return GestureDetector(
      onTap: () => setState(() => _sidebarVisible = !_sidebarVisible),
      child: Container(
        width: 18,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.80),
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(10)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 6,
                offset: const Offset(2, 0)),
          ],
        ),
        child: Icon(
          _sidebarVisible
              ? Icons.chevron_left_rounded
              : Icons.chevron_right_rounded,
          size: 16,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _sidebarTool({
    required IconData icon,
    required DrawTool tool,
    required String tooltip,
    required AppTheme t,
  }) {
    final active = _activeTool == tool;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => setState(() => _activeTool = tool),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color:
                active ? t.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(
                    color: t.primary.withOpacity(0.4), width: 1.5)
                : null,
          ),
          child: Icon(icon,
              size: 22,
              color: active ? t.primary : Colors.grey.shade500),
        ),
      ),
    );
  }

  Widget _sidebarIconBtn(
    IconData icon,
    VoidCallback? onTap, {
    String? tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon,
              size: 22, color: color ?? Colors.grey.shade500),
        ),
      ),
    );
  }

  Widget _buildThicknessBtn(AppStrings s) {
    final clamped = _strokeWidth.clamp(3.0, 20.0);
    return Tooltip(
      message: s.strokeThickness,
      child: GestureDetector(
        onTap: _showThicknessPicker,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12)),
          child: Center(
            child: Container(
              width: clamped,
              height: clamped,
              decoration: BoxDecoration(
                  color: _activeColor, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }

  void _showThicknessPicker() {
    double temp = _strokeWidth;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, inner) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(LocaleService.current.strokeThickness,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('${temp.round()}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _activeColor)),
                  const SizedBox(width: 8),
                  Container(
                    width: temp.clamp(3.0, 30.0),
                    height: temp.clamp(3.0, 30.0),
                    decoration: BoxDecoration(
                        color: _activeColor, shape: BoxShape.circle),
                  ),
                ],
              ),
              Slider(
                value: temp,
                min: 1,
                max: 40,
                divisions: 39,
                activeColor: _activeColor,
                onChanged: (v) {
                  inner(() => temp = v);
                  setState(() => _strokeWidth = v);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [2.0, 5.0, 10.0, 20.0, 35.0].map((w) {
                  final sel = (temp - w).abs() < 0.5;
                  return GestureDetector(
                    onTap: () {
                      inner(() => temp = w);
                      setState(() => _strokeWidth = w);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? _activeColor
                              : Colors.grey.shade200,
                          width: sel ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: w.clamp(2.0, 30.0),
                          height: w.clamp(2.0, 30.0),
                          decoration: BoxDecoration(
                              color: _activeColor,
                              shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom colour bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomColorBar(AppTheme t) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showColorPicker,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _activeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 6),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              dragStartBehavior: DragStartBehavior.down,
              itemCount: _kPalette.length,
              itemBuilder: (_, i) {
                final c = _kPalette[i];
                final sel = _activeColor.value == c.value;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _activeColor = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 3, vertical: 8),
                    width: sel ? 38 : 32,
                    height: sel ? 38 : 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? t.primary : Colors.grey.shade300,
                        width: sel ? 2.5 : 1,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                  color: c.withOpacity(0.5),
                                  blurRadius: 6,
                                  spreadRadius: 1)
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(LocaleService.current.brush,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _kPalette.length,
              itemBuilder: (_, i) {
                final c = _kPalette[i];
                final sel = _activeColor.value == c.value;
                return GestureDetector(
                  onTap: () {
                    setState(() => _activeColor = c);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel
                            ? widget.theme.primary
                            : Colors.grey.shade300,
                        width: sel ? 3 : 1,
                      ),
                    ),
                    child: sel
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Canvas area
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCanvasArea(AppStrings s) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final newSize = constraints.biggest;
        if (!newSize.isEmpty && newSize != _canvasSize) {
          _canvasSize = newSize;
        }

        final partnerStrokes = _partnerLiveStrokes.values
            .whereType<DrawStroke>()
            .toList();

        return Stack(
          children: [
            // Canvas with zoom/pan transform
            Positioned.fill(
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_canvasOffset.dx, _canvasOffset.dy)
                    ..scale(_scale),
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: _CanvasWidget(
                      bgColor: _bgColor,
                      strokes: _strokes,
                      currentPoints: _currentPoints,
                      currentColorValue: _currentColorValue,
                      currentStrokeWidth: _currentStrokeWidth,
                      currentIsEraser: _currentIsEraser,
                      partnerStrokes: partnerStrokes,
                      canvasSize: _canvasSize,
                      repaintNotifier: _repaintNotifier,
                    ),
                  ),
                ),
              ),
            ),
            // Gesture layer — onScale handles both 1-finger draw and 2-finger zoom
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _buildPartnerBadges(),
            ),
            if (_showHint)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(child: _buildHintBubble(s)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPartnerBadges() {
    final partners = widget.pairData.partners;
    if (partners.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: partners.map((p) {
        final isDrawing =
            (_partnerLiveStrokes[p.uid]?.points.length ?? 0) > 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(left: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _colorForUser(p.uid)
                .withOpacity(isDrawing ? 0.9 : 0.4),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isDrawing
                ? [
                    BoxShadow(
                        color:
                            _colorForUser(p.uid).withOpacity(0.4),
                        blurRadius: 8)
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDrawing)
                const Text('✏️ ', style: TextStyle(fontSize: 11)),
              Text(
                p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHintBubble(AppStrings s) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        s.drawHint,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CanvasWidget  — owns the painter, reacts to ValueNotifier for fast repaints
// ─────────────────────────────────────────────────────────────────────────────
class _CanvasWidget extends StatefulWidget {
  final Color bgColor;
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final List<DrawStroke> partnerStrokes;
  final Size canvasSize;
  final ValueNotifier<int> repaintNotifier;

  const _CanvasWidget({
    required this.bgColor,
    required this.strokes,
    required this.currentPoints,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.partnerStrokes,
    required this.canvasSize,
    required this.repaintNotifier,
  });

  @override
  State<_CanvasWidget> createState() => _CanvasWidgetState();
}

class _CanvasWidgetState extends State<_CanvasWidget> {
  @override
  void initState() {
    super.initState();
    widget.repaintNotifier.addListener(_onRepaint);
  }

  @override
  void didUpdateWidget(_CanvasWidget old) {
    super.didUpdateWidget(old);
    if (old.repaintNotifier != widget.repaintNotifier) {
      old.repaintNotifier.removeListener(_onRepaint);
      widget.repaintNotifier.addListener(_onRepaint);
    }
  }

  @override
  void dispose() {
    widget.repaintNotifier.removeListener(_onRepaint);
    super.dispose();
  }

  void _onRepaint() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.bgColor,
      child: Stack(
        children: [
          // Images below vector strokes
          if (!widget.canvasSize.isEmpty)
            ...widget.strokes
                .where((s) => s.isImageStroke && s.imageUrl != null)
                .map((s) {
              final x = (s.imageX ?? 0) * widget.canvasSize.width;
              final y = (s.imageY ?? 0) * widget.canvasSize.height;
              final w = (s.imageWidth ?? 1) * widget.canvasSize.width;
              final h = (s.imageHeight ?? 1) * widget.canvasSize.height;
              return Positioned(
                left: x,
                top: y,
                width: w,
                height: h,
                child: Image.network(
                  s.imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox.shrink(),
                ),
              );
            }),
          // Vector strokes
          Positioned.fill(
            child: CustomPaint(
              painter: _DrawingPainter(
                strokes: widget.strokes
                    .where((s) => !s.isImageStroke)
                    .toList(),
                currentPoints: widget.currentPoints,
                currentColorValue: widget.currentColorValue,
                currentStrokeWidth: widget.currentStrokeWidth,
                currentIsEraser: widget.currentIsEraser,
                partnerStrokes: widget.partnerStrokes,
                canvasSize: widget.canvasSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────
class _DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final List<DrawStroke> partnerStrokes;
  final Size canvasSize;

  const _DrawingPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.partnerStrokes,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // saveLayer is required for BlendMode.dstOut (eraser) to work
    canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final s in strokes) {
      _drawStroke(canvas, s.points, s.colorValue, s.strokeWidth,
          s.isEraser, size);
    }

    if (currentPoints.isNotEmpty) {
      _drawStroke(canvas, currentPoints, currentColorValue,
          currentStrokeWidth, currentIsEraser, size);
    }

    for (final s in partnerStrokes) {
      _drawPartnerStroke(canvas, s.points, s.colorValue,
          s.strokeWidth, s.isEraser, size);
    }

    canvas.restore();
  }

  void _drawStroke(
    Canvas canvas,
    List<DrawPoint> pts,
    int colorValue,
    double strokeWidth,
    bool isEraser,
    Size size,
  ) {
    if (pts.isEmpty) return;

    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (isEraser) {
      paint
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xFFFFFFFF);
    } else {
      paint.color = Color(colorValue);
    }

    if (pts.length == 1) {
      if (!isEraser) {
        canvas.drawCircle(
            pts[0].toOffset(size), strokeWidth / 2, paint..style = PaintingStyle.fill);
      }
      return;
    }

    final path = Path();
    final o0 = pts[0].toOffset(size);
    path.moveTo(o0.dx, o0.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final p0 = pts[i].toOffset(size);
      final p1 = pts[i + 1].toOffset(size);
      final mid =
          Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    final last = pts.last.toOffset(size);
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  void _drawPartnerStroke(
    Canvas canvas,
    List<DrawPoint> pts,
    int colorValue,
    double strokeWidth,
    bool isEraser,
    Size size,
  ) {
    if (pts.length < 2) return;

    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (isEraser) {
      paint
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xFFFFFFFF);
    } else {
      paint.color = Color(colorValue).withOpacity(0.8);
    }

    final path = Path();
    path.moveTo(pts[0].toOffset(size).dx, pts[0].toOffset(size).dy);
    for (int i = 1; i < pts.length; i++) {
      final o = pts[i].toOffset(size);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) =>
      !identical(old.currentPoints, currentPoints) ||
      old.strokes != strokes ||
      old.partnerStrokes != partnerStrokes ||
      old.currentColorValue != currentColorValue ||
      old.currentStrokeWidth != currentStrokeWidth ||
      old.currentIsEraser != currentIsEraser;
}
