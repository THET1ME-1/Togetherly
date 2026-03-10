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

//  Palette

const List<Color> _kPalette = [
  Color(0xFF000000),
  Color(0xFF374151),
  Color(0xFF6B7280),
  Color(0xFFD1D5DB),
  Color(0xFFFFFFFF),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFFBBF24),
  Color(0xFFEAB308),
  Color(0xFF84CC16),
  Color(0xFF22C55E),
  Color(0xFF10B981),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFF43F5E),
  Color(0xFF92400E),
  Color(0xFF065F46),
];

const List<Color> _kUserColors = [
  Color(0xFF3B82F6),
  Color(0xFFEC4899),
  Color(0xFF22C55E),
  Color(0xFFF97316),
];

//  DrawScreen

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

class _DrawScreenState extends State<DrawScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _kCanvasPad = 16.0;
  static const int _liveThrottleMs = 60;
  static const double _kMinScale = 0.2;
  static const double _kMaxScale = 10.0;

  final FirebaseService _fb = FirebaseService();
  final GlobalKey _canvasKey = GlobalKey();

  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<DrawStroke>> _partnerNotifier =
      ValueNotifier<List<DrawStroke>>([]);

  final List<_UndoItem> _undoStack = [];
  final List<_RedoItem> _redoStack = [];
  final Map<String, DrawStroke> _pendingLocalStrokes = {};
  final Set<String> _cancelledPendingStrokeIds = {};
  final Map<String, DrawStroke> _partnerLiveMap = {};
  final Map<String, int> _partnerTimestamps = {};
  final Set<int> _activePointers = <int>{};

  List<DrawStroke> _remoteStrokes = [];
  List<DrawStroke> _visibleStrokes = [];
  final List<DrawPoint> _currentPoints = [];

  DrawTool _activeTool = DrawTool.brush;
  Color _activeColor = const Color(0xFF000000);
  double _strokeWidth = 5.0;
  Color _bgColor = Colors.white;
  bool _clearVersionSeeded = false;

  int _currentColorValue = 0xFF000000;
  double _currentStrokeWidth = 5.0;
  bool _currentIsEraser = false;
  DrawShapeType? _currentShapeType;
  bool _isDrawing = false;
  int _lastClearVersion = 0;

  /// Текущий угол поворота холста (в радианах). Обновляется
  /// как жестом двумя пальцами, так и кнопкой (+π/2).
  double _canvasRotation = 0.0;

  // Hint / onboarding
  bool _showHint = true;
  int _hintStep = 0; // 0=draw, 1=tools, 2=pinch - auto-dismiss

  bool _saving = false;

  // Pan / zoom
  Size _canvasSize = Size.zero;
  double _scale = 1.0;
  Offset _canvasOffset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  double _baseRotation = 0.0;
  bool _isZooming = false;

  /// true с момента касания вторым пальцем и до подъёма ВСЕХ пальцев.
  /// Блокирует начало и продолжение рисования надёжнее, чем _isZooming,
  /// который сбрасывается onScaleEnd ещё до снятия последнего пальца.
  bool _multiTouchActive = false;

  /// Идентификатор пальца, который панирует холст инструментом «Рука».
  int? _handPanPointer;
  Offset _handPanLast = Offset.zero;
  int? _drawingPointerId;
  int _orderCounter = 0;
  DateTime _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);

  // Toolbar expansion
  bool _toolbarExpanded = false;
  late AnimationController _toolbarAnim;

  // Partner cursor pulse animation
  late AnimationController _pulseAnim;

  StreamSubscription? _strokesSub;
  StreamSubscription? _liveSub;
  StreamSubscription? _bgColorSub;
  StreamSubscription? _clearVersionSub;
  StreamSubscription? _rotationSub;
  Timer? _staleTimer;
  Timer? _hintTimer;

  String get _myUid => widget.userData.uid;
  String get _groupId => widget.pairData.pairId;
  bool get _hasSharedCanvas => _groupId.isNotEmpty;

  bool get _isShapeTool =>
      _activeTool == DrawTool.line ||
      _activeTool == DrawTool.rect ||
      _activeTool == DrawTool.circle;

  DrawShapeType? get _activeShapeType {
    switch (_activeTool) {
      case DrawTool.line:
        return DrawShapeType.line;
      case DrawTool.rect:
        return DrawShapeType.rect;
      case DrawTool.circle:
        return DrawShapeType.circle;
      default:
        return null;
    }
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  /// Угол поворота холста в радианах.
  double get _rotationRadians => _canvasRotation;

  /// Масштабный коэффициент, чтобы повёрнутый холст умещался в область.
  double get _rotationFitScale {
    if (_canvasSize.isEmpty) return 1.0;
    final a = _canvasRotation % (math.pi * 2);
    // sin²+cos² даёт нам фактические проекции повёрнутого прямоугольника.
    final sinA = math.sin(a).abs();
    final cosA = math.cos(a).abs();
    final w = _canvasSize.width;
    final h = _canvasSize.height;
    final projW = w * cosA + h * sinA;
    final projH = w * sinA + h * cosA;
    return math.min(w / projW, h / projH);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _activeColor = widget.pairData.isPaired
        ? _colorForUser(_myUid)
        : const Color(0xFF000000);
    _currentColorValue = _activeColor.toARGB32();

    _toolbarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _startFirebaseListeners();
    _scheduleHints();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _strokesSub?.cancel();
    _liveSub?.cancel();
    _bgColorSub?.cancel();
    _clearVersionSub?.cancel();
    _rotationSub?.cancel();
    _staleTimer?.cancel();
    _hintTimer?.cancel();
    _toolbarAnim.dispose();
    _pulseAnim.dispose();
    _clearLiveStroke();
    _repaintNotifier.dispose();
    _partnerNotifier.dispose();
    super.dispose();
  }

  /// Сбрасываем все состояния жестов при уходе приложения в фон.
  /// Это предотвращает «залипание» после того, как система
  /// пропустила PointerUp-событие (шторка уведомлений, звонок и т.д.).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _activePointers.clear();
      _isZooming = false;
      _multiTouchActive = false;
      _handPanPointer = null;
      _cancelCurrentGesture();
    }
  }

  void _scheduleHints() {
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_showHint) return;
      setState(() => _hintStep = 1);
      _hintTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || !_showHint) return;
        setState(() => _hintStep = 2);
        _hintTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _showHint = false);
        });
      });
    });
  }

  //  Colour helpers

  Color _colorForUser(String uid) {
    final members = widget.pairData.members;
    final idx = members.indexWhere((m) => m.uid == uid);
    if (idx < 0) return _kUserColors.first;
    return _kUserColors[idx % _kUserColors.length];
  }

  //  Snackbar

  void _showMessage(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  //  Firebase listeners

  void _startFirebaseListeners() {
    if (!_hasSharedCanvas) return;

    _strokesSub = _fb
        .listenToDrawingStrokes(groupId: _groupId)
        .handleError((e) => debugPrint('[Draw] strokes error: $e'))
        .listen(_onRemoteStrokes);

    _liveSub = _fb
        .listenToLiveDrawingStrokes(groupId: _groupId, myUserId: _myUid)
        .handleError((e) => debugPrint('[Draw] live error: $e'))
        .listen(_onLiveStrokes);

    _bgColorSub = _fb
        .listenToCanvasBgColor(groupId: _groupId)
        .handleError((e) => debugPrint('[Draw] bgColor error: $e'))
        .listen(_onBgColor);

    _clearVersionSub = _fb
        .listenToCanvasClearVersion(groupId: _groupId)
        .handleError((e) => debugPrint('[Draw] clearVersion error: $e'))
        .listen(_onClearVersion);

    _rotationSub = _fb
        .listenToCanvasRotation(groupId: _groupId)
        .handleError((e) => debugPrint('[Draw] rotation error: $e'))
        .listen(_onRotation);

    _staleTimer = Timer.periodic(
      const Duration(seconds: 2),
      _removeStalePartners,
    );
  }

  void _onRemoteStrokes(List<dynamic> rawList) {
    if (!mounted) return;

    final parsed = <DrawStroke>[];
    for (final raw in rawList) {
      try {
        // Отфильтровываем «призрачные» штрихи: они были записаны в Firestore
        // в промежутке между локальной очисткой и завершением батч-удаления.
        // createdAt хранится как millisecondsSinceEpoch при toFirestore().
        final createdAt = (raw.data['createdAt'] as num?)?.toInt() ?? 0;
        if (_lastClearVersion > 0 &&
            createdAt > 0 &&
            createdAt < _lastClearVersion) {
          continue;
        }
        parsed.add(DrawStroke.fromFirestore(raw.data, raw.id));
      } catch (e) {
        debugPrint('[Draw] parse stroke error: $e');
      }
    }
    parsed.sort(_compareStrokes);
    _remoteStrokes = parsed;

    final remainingPending = Map<String, DrawStroke>.from(_pendingLocalStrokes);
    final updatedStack = List<_UndoItem>.from(_undoStack);

    for (final remote in parsed) {
      final matchKey = remainingPending.entries
          .where((e) => _looksLikeSameStroke(remote, e.value))
          .map((e) => e.key)
          .firstOrNull;
      if (matchKey != null) {
        remainingPending.remove(matchKey);
        for (int i = 0; i < updatedStack.length; i++) {
          final e = updatedStack[i];
          if (e.isStroke && e.strokeId == matchKey) {
            updatedStack[i] = _UndoItem.stroke(remote.id);
          }
        }
      }
    }

    _pendingLocalStrokes
      ..clear()
      ..addAll(remainingPending);
    _undoStack
      ..clear()
      ..addAll(updatedStack);

    if (parsed.isNotEmpty || remainingPending.isNotEmpty) {
      final maxOrder = [
        ...parsed.map((s) => s.orderIndex),
        ...remainingPending.values.map((s) => s.orderIndex),
      ].reduce(math.max);
      _orderCounter = maxOrder + 1;
    }

    setState(() => _visibleStrokes = _composeVisibleStrokes());
  }

  void _onLiveStrokes(Map<String, Map<String, dynamic>> liveMap) {
    if (!mounted) return;
    bool changed = false;

    for (final entry in liveMap.entries) {
      final uid = entry.key;
      final data = entry.value;

      if (data.isEmpty) {
        if (_partnerLiveMap.containsKey(uid)) {
          _partnerLiveMap.remove(uid);
          _partnerTimestamps.remove(uid);
          changed = true;
        }
        continue;
      }

      try {
        final stroke = DrawStroke.fromLiveMap(data, uid);
        _partnerLiveMap[uid] = stroke;
        _partnerTimestamps[uid] =
            (data['ts'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        _partnerNotifier.value = List.of(_partnerLiveMap.values);
        changed = true;
      } catch (e) {
        debugPrint('[Draw] parse live error: $e');
      }
    }

    final missing = _partnerLiveMap.keys
        .where((uid) => !liveMap.containsKey(uid))
        .toList();
    if (missing.isNotEmpty) {
      for (final uid in missing) {
        _partnerLiveMap.remove(uid);
        _partnerTimestamps.remove(uid);
      }
      _partnerNotifier.value = List.of(_partnerLiveMap.values);
      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  void _onBgColor(int? value) {
    if (!mounted || value == null) return;
    final next = Color(value);
    if (next.toARGB32() != _bgColor.toARGB32()) {
      setState(() => _bgColor = next);
    }
  }

  void _onClearVersion(int? value) {
    if (!mounted || value == null) return;
    // On initial subscription event, just seed the value so we don't
    // incorrectly wipe strokes that were drawn after the last clear.
    if (!_clearVersionSeeded) {
      _clearVersionSeeded = true;
      // Keep the higher value in case the user already cleared locally.
      if (value > _lastClearVersion) _lastClearVersion = value;
      return;
    }
    if (value <= _lastClearVersion) return;
    _lastClearVersion = value;
    _cancelCurrentGesture();
    _undoStack.clear();
    _redoStack.clear();
    _pendingLocalStrokes.clear();
    _cancelledPendingStrokeIds.clear();
    _remoteStrokes = [];
    _visibleStrokes = [];
    _partnerLiveMap.clear();
    _partnerTimestamps.clear();
    _partnerNotifier.value = [];
    _orderCounter = 0;
    setState(() => _bgColor = Colors.white);
  }

  void _onRotation(int? value) {
    if (!mounted || value == null) return;
    // Firebase stores angle as milli-radians (int) for precision.
    final next = value / 1000.0;
    if ((next - _canvasRotation).abs() > 0.001) {
      setState(() => _canvasRotation = next);
    }
  }

  void _removeStalePartners(Timer _) {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = _partnerTimestamps.entries
        .where((e) => now - e.value > 4000)
        .map((e) => e.key)
        .toList();
    if (stale.isEmpty) return;
    for (final uid in stale) {
      _partnerLiveMap.remove(uid);
      _partnerTimestamps.remove(uid);
    }
    _partnerNotifier.value = List.of(_partnerLiveMap.values);
    setState(() {});
  }

  //  Stroke helpers

  int _compareStrokes(DrawStroke a, DrawStroke b) {
    final o = a.orderIndex.compareTo(b.orderIndex);
    return o != 0 ? o : a.id.compareTo(b.id);
  }

  List<DrawStroke> _composeVisibleStrokes() {
    final combined = <DrawStroke>[
      ..._remoteStrokes,
      ..._pendingLocalStrokes.values,
    ];
    combined.sort(_compareStrokes);
    return combined;
  }

  bool _looksLikeSameStroke(DrawStroke remote, DrawStroke local) {
    if (remote.userId != local.userId) return false;
    if (remote.orderIndex != local.orderIndex) return false;
    if (remote.colorValue != local.colorValue) return false;
    if ((remote.strokeWidth - local.strokeWidth).abs() > 0.01) return false;
    if (remote.isEraser != local.isEraser) return false;
    if (remote.isFill != local.isFill) return false;
    if (remote.shapeType != local.shapeType) return false;
    if (remote.isImageStroke != local.isImageStroke) return false;

    if (remote.isImageStroke) {
      return remote.imageUrl == local.imageUrl &&
          ((remote.imageX ?? 0) - (local.imageX ?? 0)).abs() < 0.0001 &&
          ((remote.imageY ?? 0) - (local.imageY ?? 0)).abs() < 0.0001 &&
          ((remote.imageWidth ?? 0) - (local.imageWidth ?? 0)).abs() < 0.0001 &&
          ((remote.imageHeight ?? 0) - (local.imageHeight ?? 0)).abs() < 0.0001;
    }

    if (remote.points.length != local.points.length) return false;
    if (remote.points.isEmpty) return true;

    final rf = remote.points.first;
    final lf = local.points.first;
    final rl = remote.points.last;
    final ll = local.points.last;
    return (rf.x - lf.x).abs() < 0.0001 &&
        (rf.y - lf.y).abs() < 0.0001 &&
        (rl.x - ll.x).abs() < 0.0001 &&
        (rl.y - ll.y).abs() < 0.0001;
  }

  //  Coordinate transforms

  Offset _screenToCanvas(Offset localPoint) =>
      _unrotateCanvasPoint((localPoint - _canvasOffset) / _scale);

  Offset _canvasToScreen(Offset canvasPoint) =>
      _rotateCanvasPoint(canvasPoint) * _scale + _canvasOffset;

  Offset _rotateCanvasPoint(Offset point) {
    if (_canvasSize.isEmpty || _canvasRotation == 0.0) return point;
    final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    final rotated = _rotateOffset(point - center, _rotationRadians);
    return center + rotated * _rotationFitScale;
  }

  Offset _unrotateCanvasPoint(Offset point) {
    if (_canvasSize.isEmpty || _canvasRotation == 0.0) return point;
    final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    final normalized = (point - center) / _rotationFitScale;
    return center + _rotateOffset(normalized, -_rotationRadians);
  }

  Offset _rotateOffset(Offset point, double angle) {
    final sinA = math.sin(angle);
    final cosA = math.cos(angle);
    return Offset(
      point.dx * cosA - point.dy * sinA,
      point.dx * sinA + point.dy * cosA,
    );
  }

  //  Tool selection

  void _selectTool(DrawTool tool) {
    _cancelCurrentGesture();
    setState(() => _activeTool = tool);
    if (_showHint) setState(() => _showHint = false);
  }

  void _cancelCurrentGesture() {
    final had = _isDrawing || _currentPoints.isNotEmpty;
    _isDrawing = false;
    _drawingPointerId = null;
    _currentShapeType = null;
    _currentPoints.clear();
    if (had) {
      _clearLiveStroke();
      _repaintNotifier.value++;
    }
  }

  //  Drawing gestures

  void _startStroke(Offset localPoint) {
    if (_canvasSize.isEmpty) return;
    // Инструменты “Рука” и “Фото” не рисуют штрихи.
    if (_activeTool == DrawTool.hand || _activeTool == DrawTool.image) return;

    if (_activeTool == DrawTool.fill) {
      _applyFill(localPoint);
      return;
    }

    _redoStack.clear();
    _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);
    if (_showHint) setState(() => _showHint = false);

    if (_isShapeTool) {
      final pt = DrawPoint.fromOffset(_screenToCanvas(localPoint), _canvasSize);
      _currentPoints
        ..clear()
        ..add(pt)
        ..add(pt);
      _currentShapeType = _activeShapeType;
      _currentColorValue = _activeColor.toARGB32();
      _currentStrokeWidth = _strokeWidth;
      _currentIsEraser = false;
      _isDrawing = true;
      _repaintNotifier.value++;
      return;
    }

    _currentPoints
      ..clear()
      ..add(DrawPoint.fromOffset(_screenToCanvas(localPoint), _canvasSize));
    _currentShapeType = null;
    _currentColorValue = _activeTool == DrawTool.eraser
        ? _bgColor.toARGB32()
        : _activeColor.toARGB32();
    _currentStrokeWidth = _strokeWidth;
    _currentIsEraser = _activeTool == DrawTool.eraser;
    _isDrawing = true;
    _repaintNotifier.value++;
  }

  void _updateStroke(Offset localPoint) {
    if (!_isDrawing || _canvasSize.isEmpty) return;
    if (_currentShapeType != null) {
      final end = DrawPoint.fromOffset(
        _screenToCanvas(localPoint),
        _canvasSize,
      );
      if (_currentPoints.length >= 2) {
        _currentPoints[1] = end;
      } else {
        _currentPoints.add(end);
      }
    } else {
      _currentPoints.add(
        DrawPoint.fromOffset(_screenToCanvas(localPoint), _canvasSize),
      );
    }
    _repaintNotifier.value++;
    _pushLiveStrokeIfNeeded();
  }

  void _finishStroke() {
    if (!_isDrawing) return;
    _isDrawing = false;
    _drawingPointerId = null;
    _commitCurrentStroke();
  }

  void _pushLiveStrokeIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastLivePush).inMilliseconds >= _liveThrottleMs) {
      _lastLivePush = now;
      unawaited(_pushLiveStrokeAsync());
    }
  }

  Future<void> _pushLiveStrokeAsync() async {
    if (!_hasSharedCanvas || _currentPoints.isEmpty) return;
    final stroke = DrawStroke(
      id: 'live_$_myUid',
      userId: _myUid,
      colorValue: _currentColorValue,
      strokeWidth: _currentStrokeWidth,
      points: List<DrawPoint>.unmodifiable(_currentPoints),
      isEraser: _currentIsEraser,
      shapeType: _currentShapeType,
      orderIndex: -1,
    );
    try {
      await _fb.updateLiveDrawingStroke(
        groupId: _groupId,
        userId: _myUid,
        liveData: stroke.toLiveMap(),
      );
    } catch (e) {
      debugPrint('[Draw] live push error: $e');
    }
  }

  void _clearLiveStroke() {
    if (!_hasSharedCanvas) return;
    _fb
        .clearLiveDrawingStroke(groupId: _groupId, userId: _myUid)
        .catchError((e) => debugPrint('[Draw] clear live error: $e'));
  }

  void _onPointerDown(PointerDownEvent event) {
    // Если перед новым касанием в Set нет активных пальцев, но
    // флаги жеста остались — это признак пропущенного PointerUp
    // (уведомление, звонок). Очищаем «зависший» стейт.
    if (_activePointers.isEmpty) {
      _isZooming = false;
      _multiTouchActive = false;
      if (_isDrawing) _cancelCurrentGesture();
    }

    _activePointers.add(event.pointer);

    if (_activePointers.length >= 2) {
      // Второй (и более) палец: помечаем мульти-тач и отменяем любое рисование.
      _isZooming = false; // будет перехвачено onScaleStart
      _multiTouchActive = true;
      _cancelCurrentGesture();
      return;
    }

    // Один палец — рисуем только если до этого не было мульти-тач жеста.
    if (_multiTouchActive) return;
    _isZooming = false;
    // Инструмент «Рука»: единственный палец панирует холст, рисование не начинается.
    if (_activeTool == DrawTool.hand) {
      _handPanPointer = event.pointer;
      _handPanLast = event.localPosition;
      return;
    }
    _drawingPointerId = event.pointer;
    _startStroke(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isZooming || _multiTouchActive || _activePointers.length != 1) return;
    // Инструмент «Рука»: панируем холст одним пальцем.
    if (_handPanPointer == event.pointer) {
      final delta = event.localPosition - _handPanLast;
      _handPanLast = event.localPosition;
      setState(() => _canvasOffset += delta);
      return;
    }
    if (_drawingPointerId != event.pointer) return;
    _updateStroke(event.localPosition);
  }

  void _onPointerUp(PointerEvent event) {
    final wasDrawing = _drawingPointerId == event.pointer;
    final wasPanning = _handPanPointer == event.pointer;
    _activePointers.remove(event.pointer);

    if (wasPanning) _handPanPointer = null;
    if (wasDrawing && !_isZooming && !_multiTouchActive) {
      _finishStroke();
    }

    // Когда все пальцы подняты — сбрасываем ВСЕ состояния.
    if (_activePointers.isEmpty) {
      _drawingPointerId = null;
      _handPanPointer = null;
      _isZooming = false;
      _multiTouchActive = false;
      if (_isDrawing) _cancelCurrentGesture();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) return;
    _isZooming = true;
    _cancelCurrentGesture();
    _baseScale = _scale;
    _baseOffset = _canvasOffset;
    _baseFocalPoint = details.localFocalPoint;
    _baseRotation = _canvasRotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_isZooming && details.pointerCount < 2) return;
    _isZooming = true;
    final nextScale = (_baseScale * details.scale).clamp(
      _kMinScale,
      _kMaxScale,
    );
    final focalCanvas = (_baseFocalPoint - _baseOffset) / _baseScale;
    final nextOffset = details.localFocalPoint - focalCanvas * nextScale;
    final nextRotation = _baseRotation + details.rotation;
    setState(() {
      _scale = nextScale;
      _canvasOffset = nextOffset;
      _canvasRotation = nextRotation;
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _isZooming = false;
    // После pinch-жеста — синхронизируем финальный угол поворота с партнёром.
    if (_hasSharedCanvas) {
      _fb
          .setCanvasRotation(
            groupId: _groupId,
            rotationQuarterTurns: (_canvasRotation * 1000).round(),
          )
          .catchError((e) => debugPrint('[Draw] rotation sync error: $e'));
    }
    // После pinch-zoom все пальцы подняты — убедимся, что
    // рисование не осталось в «подвешенном» состоянии.
    if (_activePointers.isEmpty) {
      _drawingPointerId = null;
      if (_isDrawing) _cancelCurrentGesture();
    }
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _canvasOffset = Offset.zero;
    });
  }

  //  Commit stroke

  void _commitCurrentStroke() {
    final shapeType = _currentShapeType;

    if (shapeType != null) {
      if (_currentPoints.length < 2 ||
          (_currentPoints[0].x == _currentPoints[1].x &&
              _currentPoints[0].y == _currentPoints[1].y)) {
        _currentPoints.clear();
        _currentShapeType = null;
        _clearLiveStroke();
        _repaintNotifier.value++;
        return;
      }
    } else if (_currentPoints.length < 2) {
      if (_currentPoints.length == 1 && !_currentIsEraser) {
        _currentPoints.add(_currentPoints.first);
      } else {
        _currentPoints.clear();
        _currentShapeType = null;
        _clearLiveStroke();
        _repaintNotifier.value++;
        return;
      }
    }

    final stroke = DrawStroke(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter',
      userId: _myUid,
      colorValue: _currentColorValue,
      strokeWidth: _currentStrokeWidth,
      points: List<DrawPoint>.unmodifiable(_currentPoints),
      isEraser: _currentIsEraser,
      isFill: false,
      shapeType: shapeType,
      orderIndex: _orderCounter,
    );

    _currentPoints.clear();
    _currentShapeType = null;
    _clearLiveStroke();
    _repaintNotifier.value++;
    _orderCounter++;
    _submitStroke(stroke);
  }

  void _submitStroke(DrawStroke stroke) {
    if (!_hasSharedCanvas) {
      setState(() {
        _visibleStrokes = [..._visibleStrokes, stroke]..sort(_compareStrokes);
      });
      _undoStack.add(_UndoItem.stroke(stroke.id));
      return;
    }

    setState(() {
      _pendingLocalStrokes[stroke.id] = stroke;
      _visibleStrokes = _composeVisibleStrokes();
    });
    _undoStack.add(_UndoItem.stroke(stroke.id));

    _fb
        .addDrawingStroke(groupId: _groupId, strokeData: stroke.toFirestore())
        .then((remoteId) async {
          if (remoteId.isEmpty) throw Exception('Empty stroke id');
          if (_cancelledPendingStrokeIds.remove(stroke.id)) {
            await _fb.deleteDrawingStroke(
              groupId: _groupId,
              strokeId: remoteId,
            );
          }
        })
        .catchError((e) {
          debugPrint('[Draw] commit error: $e');
          if (!mounted) return;
          setState(() {
            _pendingLocalStrokes.remove(stroke.id);
            _visibleStrokes = _composeVisibleStrokes();
          });
          _undoStack.removeWhere((e) => e.isStroke && e.strokeId == stroke.id);
        });
  }

  //  Undo / Redo

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();

    // --- Bg-fill undo ---
    if (entry.isBg) {
      final oldColor = entry.oldBg!;
      final currentColor = entry.newBg!;
      setState(() => _bgColor = oldColor);
      _redoStack.add(_RedoItem.bg(currentColor));
      if (_hasSharedCanvas) {
        _fb
            .setCanvasBgColor(
              groupId: _groupId,
              colorValue: oldColor.toARGB32(),
            )
            .catchError((e) => debugPrint('[Draw] undo bg error: $e'));
      }
      return;
    }

    // --- Stroke undo ---
    final undoKey = entry.strokeId!;
    DrawStroke? removed;
    String? remoteIdForDelete;

    if (_pendingLocalStrokes.containsKey(undoKey)) {
      removed = _pendingLocalStrokes.remove(undoKey);
      _cancelledPendingStrokeIds.add(undoKey);
    } else {
      removed = _visibleStrokes.where((s) => s.id == undoKey).firstOrNull;
      if (removed != null) {
        _remoteStrokes = _remoteStrokes.where((s) => s.id != undoKey).toList();
        remoteIdForDelete = undoKey;
      }
    }

    if (removed == null) return;
    _redoStack.add(_RedoItem.stroke(removed));
    setState(() => _visibleStrokes = _composeVisibleStrokes());

    if (!_hasSharedCanvas || remoteIdForDelete == null) return;

    try {
      await _fb.deleteDrawingStroke(
        groupId: _groupId,
        strokeId: remoteIdForDelete,
      );
    } catch (e) {
      debugPrint('[Draw] undo error: $e');
      if (!mounted) return;
      _undoStack.add(_UndoItem.stroke(undoKey));
      _redoStack.removeLast();
      setState(() {
        _remoteStrokes = [..._remoteStrokes, removed!]..sort(_compareStrokes);
        _visibleStrokes = _composeVisibleStrokes();
      });
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();

    // --- Bg-fill redo ---
    if (!entry.isStroke) {
      final color = entry.bgColor!;
      _undoStack.add(_UndoItem.bg(old: _bgColor, current: color));
      setState(() => _bgColor = color);
      if (_hasSharedCanvas) {
        _fb
            .setCanvasBgColor(groupId: _groupId, colorValue: color.toARGB32())
            .catchError((e) => debugPrint('[Draw] redo bg error: $e'));
      }
      return;
    }

    // --- Stroke redo ---
    final base = entry.stroke!;
    final stroke = DrawStroke(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter',
      userId: _myUid,
      colorValue: base.colorValue,
      strokeWidth: base.strokeWidth,
      points: List<DrawPoint>.unmodifiable(base.points),
      isEraser: base.isEraser,
      isFill: base.isFill,
      shapeType: base.shapeType,
      orderIndex: _orderCounter,
      imageUrl: base.imageUrl,
      imageX: base.imageX,
      imageY: base.imageY,
      imageWidth: base.imageWidth,
      imageHeight: base.imageHeight,
    );
    _orderCounter++;
    _submitStroke(stroke);
  }

  //  Fill / Clear

  void _applyFill(Offset localPoint) {
    _cancelCurrentGesture();
    _redoStack.clear();

    final canvasPoint = _screenToCanvas(localPoint);
    final fillTarget = _findFillTarget(canvasPoint);

    if (fillTarget != null) {
      final stroke = DrawStroke(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter',
        userId: _myUid,
        colorValue: _activeColor.toARGB32(),
        strokeWidth: 1,
        points: List<DrawPoint>.unmodifiable(fillTarget.points),
        isFill: true,
        shapeType: fillTarget.shapeType,
        orderIndex: _orderCounter,
      );
      _orderCounter++;
      _submitStroke(stroke);
      return;
    }

    final next = _activeColor;
    _undoStack.add(_UndoItem.bg(old: _bgColor, current: next));
    setState(() => _bgColor = next);
    if (_hasSharedCanvas) {
      _fb
          .setCanvasBgColor(groupId: _groupId, colorValue: next.toARGB32())
          .catchError((e) => debugPrint('[Draw] fill error: $e'));
    }
  }

  DrawStroke? _findFillTarget(Offset canvasPoint) {
    for (final stroke in _visibleStrokes.reversed) {
      if (_strokeContainsPoint(stroke, canvasPoint)) return stroke;
    }
    return null;
  }

  bool _strokeContainsPoint(DrawStroke stroke, Offset canvasPoint) {
    if (stroke.isImageStroke || stroke.isEraser) return false;

    switch (stroke.shapeType) {
      case DrawShapeType.line:
        return false;
      case DrawShapeType.rect:
        if (stroke.points.length < 2) return false;
        return Rect.fromPoints(
          stroke.points.first.toOffset(_canvasSize),
          stroke.points.last.toOffset(_canvasSize),
        ).contains(canvasPoint);
      case DrawShapeType.circle:
        if (stroke.points.length < 2) return false;
        final start = stroke.points.first.toOffset(_canvasSize);
        final end = stroke.points.last.toOffset(_canvasSize);
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final radius = (end - start).distance / 2;
        return (canvasPoint - center).distance <= radius;
      case null:
        final path = _buildClosedFreehandPath(stroke.points, _canvasSize);
        return path?.contains(canvasPoint) ?? false;
    }
  }

  Path? _buildClosedFreehandPath(List<DrawPoint> points, Size size) {
    if (points.length < 3) return null;

    final path = Path();
    final first = points.first.toOffset(size);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i].toOffset(size);
      final p1 = points[i + 1].toOffset(size);
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }

    final last = points.last.toOffset(size);
    path.lineTo(last.dx, last.dy);
    path.close();
    return path;
  }

  void _rotateCanvasClockwise() {
    _cancelCurrentGesture();
    // Snap to the nearest multiple of π/2 that is 90° ahead.
    final snapped =
        ((_canvasRotation / (math.pi / 2)).round() + 1) * (math.pi / 2);
    setState(() => _canvasRotation = snapped);
    if (_hasSharedCanvas) {
      // Store as milli-radians to avoid floating-point loss in Firestore int.
      _fb
          .setCanvasRotation(
            groupId: _groupId,
            rotationQuarterTurns: (snapped * 1000).round(),
          )
          .catchError((e) => debugPrint('[Draw] rotation sync error: $e'));
    }
  }

  //  Image insertion

  void _showImageSourcePicker() {
    final s = LocaleService.current;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(s.photoFromGallery),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndInsertImage(fromCamera: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: Text(s.photoFromCamera),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndInsertImage(fromCamera: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndInsertImage({required bool fromCamera}) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = fromCamera
          ? await picker.pickImage(source: ImageSource.camera, imageQuality: 85)
          : await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
    } catch (e) {
      debugPrint('[Draw] pick error: $e');
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _saving = true);
    try {
      // Determine aspect ratio from file before upload.
      final bytes = await File(picked.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imgW = frame.image.width;
      final imgH = frame.image.height;
      frame.image.dispose();

      // Place image centred at 60 % canvas width, preserving aspect ratio.
      const normW = 0.6;
      final normH = imgW > 0 ? normW * imgH / imgW : normW;
      final normX = (1.0 - normW) / 2;
      final normY = ((1.0 - normH) / 2).clamp(0.0, 1.0 - normH);

      String imageUrl = picked.path;
      if (_hasSharedCanvas) {
        final url = await _fb.uploadDrawingImage(
          groupId: _groupId,
          localPath: picked.path,
        );
        if (url == null) throw Exception('Upload failed');
        imageUrl = url;
      }

      final stroke = DrawStroke(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter',
        userId: _myUid,
        colorValue: 0xFF000000,
        strokeWidth: 1,
        points: const [],
        orderIndex: _orderCounter,
        imageUrl: imageUrl,
        imageX: normX,
        imageY: normY,
        imageWidth: normW,
        imageHeight: normH,
      );
      _orderCounter++;
      _submitStroke(stroke);
    } catch (e) {
      debugPrint('[Draw] image insert error: $e');
      if (mounted) {
        _showMessage(
          LocaleService.current.failedUploadImage,
          backgroundColor: Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmClear() async {
    final s = LocaleService.current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s.clearCanvas),
        content: Text(s.clearCanvasConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: Text(s.clearCanvas),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final prevVisible = List<DrawStroke>.from(_visibleStrokes);
    final prevRemote = List<DrawStroke>.from(_remoteStrokes);
    final prevPending = Map<String, DrawStroke>.from(_pendingLocalStrokes);
    final prevBg = _bgColor;

    // Помечаем все штрихи, ещё не подтверждённые Firebase, как отменённые.
    // Когда их запись завершится, .then()-коллбэк удалит их из Firestore.
    _cancelledPendingStrokeIds.addAll(_pendingLocalStrokes.keys);
    _undoStack.clear();
    _redoStack.clear();
    _pendingLocalStrokes.clear();
    _remoteStrokes = [];
    setState(() {
      _visibleStrokes = [];
      _bgColor = Colors.white;
    });

    if (!_hasSharedCanvas) return;

    try {
      final clearVersion = DateTime.now().millisecondsSinceEpoch;
      _lastClearVersion = clearVersion;
      await _fb.clearDrawingCanvas(
        groupId: _groupId,
        clearVersion: clearVersion,
        bgColorValue: Colors.white.toARGB32(),
      );
    } catch (e) {
      debugPrint('[Draw] clear error: $e');
      if (!mounted) return;
      _remoteStrokes = prevRemote;
      _pendingLocalStrokes
        ..clear()
        ..addAll(prevPending);
      setState(() {
        _visibleStrokes = prevVisible;
        _bgColor = prevBg;
      });
    }
  }

  //  Save / Share

  Future<Directory> _resolveSaveDirectory() async {
    if (Platform.isAndroid) {
      final d = Directory('/storage/emulated/0/Download');
      if (await d.exists()) return d;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> _saveOrShare({required bool share}) async {
    if (_saving) return;
    final s = LocaleService.current;
    setState(() => _saving = true);
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final name = 'drawing_${DateTime.now().millisecondsSinceEpoch}.png';

      if (share) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles([XFile(file.path)], text: ' ${s.drawTogether}');
      } else {
        final dir = await _resolveSaveDirectory();
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        _showMessage(s.drawingSavedTo(file.path));
      }
    } catch (e) {
      debugPrint('[Draw] save/share error: $e');
      _showMessage(
        share ? s.failedToShareDrawing : s.failedToSaveDrawing,
        backgroundColor: Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  //  Bottom sheet pickers

  void _showThicknessPicker() {
    double temp = _strokeWidth;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  LocaleService.current.strokeThickness,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.brush, size: 16, color: Colors.grey.shade400),
                    Expanded(
                      child: Slider(
                        value: temp,
                        min: 1,
                        max: 40,
                        divisions: 39,
                        activeColor: _activeColor,
                        onChanged: (v) {
                          ss(() => temp = v);
                          setState(() => _strokeWidth = v);
                        },
                      ),
                    ),
                    Icon(Icons.brush, size: 28, color: Colors.grey.shade400),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [2.0, 5.0, 10.0, 20.0, 35.0].map((w) {
                    final sel = (temp - w).abs() < 0.1;
                    return GestureDetector(
                      onTap: () {
                        ss(() => temp = w);
                        setState(() => _strokeWidth = w);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: sel
                              ? _activeColor.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? _activeColor : Colors.grey.shade300,
                            width: sel ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: w.clamp(2.0, 30.0),
                            height: w.clamp(2.0, 30.0),
                            decoration: BoxDecoration(
                              color: _activeColor,
                              shape: BoxShape.circle,
                            ),
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
      ),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                LocaleService.current.brush,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _kPalette.length,
                itemBuilder: (_, i) {
                  final c = _kPalette[i];
                  final sel = c.toARGB32() == _activeColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      setState(() => _activeColor = c);
                      Navigator.pop(ctx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel
                              ? widget.theme.primary
                              : (c == Colors.white
                                    ? Colors.grey.shade300
                                    : Colors.transparent),
                          width: sel ? 3 : 1.5,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: sel
                          ? Icon(
                              Icons.check_rounded,
                              color: c == Colors.white
                                  ? Colors.black
                                  : Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  //  BUILD

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;

    return Scaffold(
      backgroundColor: const Color(0xFFECECEC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(s, t),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildCanvasArea()),
                  // Floating partner badges - top right
                  Positioned(top: 10, right: 10, child: _buildPartnerBadges()),
                  // Scale indicator - top left
                  if (_scale != 1.0)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _buildScaleIndicator(),
                    ),
                  // Onboarding hint
                  if (_showHint)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 88,
                      child: Center(child: _buildHintBubble(s)),
                    ),
                ],
              ),
            ),
            _buildBottomToolbar(s, t),
          ],
        ),
      ),
    );
  }

  //  Top bar

  Widget _buildTopBar(AppStrings s, AppTheme t) {
    final drawingPartners = _partnerLiveMap.entries
        .where((e) => e.value.points.length > 1)
        .map(
          (e) =>
              widget.pairData.partners
                  .where((p) => p.uid == e.key)
                  .map((p) => p.name)
                  .firstOrNull ??
              '?',
        )
        .toList();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _topIconBtn(
            Icons.arrow_back_ios_new_rounded,
            () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.drawTogether,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (drawingPartners.isNotEmpty)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      s.partnerIsDrawing(drawingPartners.join(', ')),
                      key: ValueKey(drawingPartners.join()),
                      style: TextStyle(
                        fontSize: 11,
                        color: t.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _topIconBtn(
            Icons.undo_rounded,
            _canUndo ? _undo : null,
            tooltip: s.undoAction,
          ),
          _topIconBtn(
            Icons.redo_rounded,
            _canRedo ? _redo : null,
            tooltip: s.redoAction,
          ),
          _saving
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _topIconBtn(
                  Icons.save_alt_rounded,
                  () => _saveOrShare(share: false),
                  tooltip: s.saveDrawing,
                ),
          _topIconBtn(
            Icons.share_rounded,
            () => _saveOrShare(share: true),
            tooltip: s.shareDrawing,
          ),
        ],
      ),
    );
  }

  Widget _topIconBtn(IconData icon, VoidCallback? onTap, {String? tooltip}) {
    final btn = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip, child: btn);
    return btn;
  }

  //  Canvas area

  Widget _buildCanvasArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest;
        final nextSize = Size(
          (available.width - _kCanvasPad * 2).clamp(1.0, double.infinity),
          (available.height - _kCanvasPad * 2).clamp(1.0, double.infinity),
        );
        // Обновляем размер холста напрямую во время build-фазы.
        // addPostFrameCallback здесь лишний и создавал лишние перерисовки.
        if (!nextSize.isEmpty && nextSize != _canvasSize) {
          _canvasSize = nextSize;
        }

        return Stack(
          children: [
            // Subtle grid background
            const Positioned.fill(child: _GridBackground()),
            // White canvas with shadow
            Positioned(
              left: _kCanvasPad,
              top: _kCanvasPad,
              right: _kCanvasPad,
              bottom: _kCanvasPad,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRect(
                  child: Transform.translate(
                    offset: _canvasOffset,
                    child: Transform.scale(
                      scale: _scale,
                      alignment: Alignment.topLeft,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..rotateZ(_rotationRadians)
                          ..scaleByDouble(
                            _rotationFitScale,
                            _rotationFitScale,
                            1.0,
                            1.0,
                          ),
                        child: RepaintBoundary(
                          key: _canvasKey,
                          child: _CanvasScene(
                            bgColor: _bgColor,
                            strokes: _visibleStrokes,
                            currentPoints: _currentPoints,
                            currentColorValue: _currentColorValue,
                            currentStrokeWidth: _currentStrokeWidth,
                            currentIsEraser: _currentIsEraser,
                            currentShapeType: _currentShapeType,
                            partnerNotifier: _partnerNotifier,
                            canvasSize: _canvasSize,
                            repaintNotifier: _repaintNotifier,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Input layer
            Positioned(
              left: _kCanvasPad,
              top: _kCanvasPad,
              right: _kCanvasPad,
              bottom: _kCanvasPad,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Partner cursor overlays
            ValueListenableBuilder<List<DrawStroke>>(
              valueListenable: _partnerNotifier,
              builder: (_, strokes, _) {
                if (_canvasSize.isEmpty) return const SizedBox.shrink();
                return Stack(
                  children: strokes
                      .where((s) => s.points.isNotEmpty)
                      .map((stroke) => _buildPartnerCursor(stroke))
                      .toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPartnerCursor(DrawStroke stroke) {
    final last = stroke.points.last;
    final rotatedPoint = _canvasToScreen(last.toOffset(_canvasSize));
    final sx = rotatedPoint.dx + _kCanvasPad;
    final sy = rotatedPoint.dy + _kCanvasPad;
    final name =
        widget.pairData.partners
            .where((p) => p.uid == stroke.userId)
            .map((p) => p.name)
            .firstOrNull ??
        '?';
    final color = _colorForUser(stroke.userId);

    return Positioned(
      left: sx - 12,
      top: sy - 12,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) {
            final pulse = 0.7 + 0.3 * _pulseAnim.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(scale: pulse, child: child),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    name.length > 8 ? name.substring(0, 8) : name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
              ],
            ),
            child: const Icon(
              Icons.brush_rounded,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScaleIndicator() {
    final pct = (_scale * 100).round();
    return GestureDetector(
      onTap: _resetZoom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$pct%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  //  Partner badges

  Widget _buildPartnerBadges() {
    final partners = widget.pairData.partners;
    if (partners.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: partners.map((p) {
        final isDrawing = (_partnerLiveMap[p.uid]?.points.length ?? 0) > 1;
        final color = _colorForUser(p.uid);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDrawing ? 0.9 : 0.4),
            borderRadius: BorderRadius.circular(14),
            boxShadow: isDrawing
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDrawing) ...[const _PulsingDot(), const SizedBox(width: 4)],
              Text(
                p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  //  Hint bubble

  Widget _buildHintBubble(AppStrings s) {
    final hints = [s.drawHint, s.brush, s.strokeThickness];
    final icons = [
      Icons.gesture_rounded,
      Icons.expand_rounded,
      Icons.pinch_rounded,
    ];

    return GestureDetector(
      onTap: () => setState(() => _showHint = false),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: Container(
          key: ValueKey(_hintStep),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icons[_hintStep.clamp(0, 2)],
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  hints[_hintStep.clamp(0, 2)],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.close_rounded, color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  //  Bottom toolbar

  Widget _buildBottomToolbar(AppStrings s, AppTheme t) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expanded tools row (shown when toolbar is expanded)
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: _toolbarExpanded
                ? _buildExpandedTools(s, t)
                : const SizedBox.shrink(),
          ),
          // Main toolbar row
          _buildMainToolbarRow(s, t),
        ],
      ),
    );
  }

  Widget _buildExpandedTools(AppStrings s, AppTheme t) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFF9F9F9),
      child: Row(
        children: [
          _toolBtn(
            Icons.remove_rounded,
            DrawTool.line,
            s.drawLine,
            t,
            compact: true,
          ),
          _toolBtn(
            Icons.crop_square_rounded,
            DrawTool.rect,
            s.drawRect,
            t,
            compact: true,
          ),
          _toolBtn(
            Icons.circle_outlined,
            DrawTool.circle,
            s.drawCircle,
            t,
            compact: true,
          ),
          _toolBtn(
            Icons.format_color_fill_rounded,
            DrawTool.fill,
            s.fillBg,
            t,
            compact: true,
          ),
          _actionBtn(
            Icons.add_photo_alternate_rounded,
            _showImageSourcePicker,
            tooltip: s.insertPhoto,
          ),
          _actionBtn(
            Icons.rotate_90_degrees_cw_rounded,
            _rotateCanvasClockwise,
            tooltip: s.rotateCanvas,
          ),
          const Spacer(),
          _actionBtn(
            Icons.delete_outline_rounded,
            _confirmClear,
            tooltip: s.clearCanvas,
            color: Colors.red.shade400,
          ),
        ],
      ),
    );
  }

  Widget _buildMainToolbarRow(AppStrings s, AppTheme t) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Color dot - opens color picker
            GestureDetector(
              onTap: _showColorPicker,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _activeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: _activeColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Color scroll bar
            Expanded(
              child: SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  dragStartBehavior: DragStartBehavior.down,
                  itemCount: _kPalette.length,
                  itemBuilder: (_, i) {
                    final c = _kPalette[i];
                    final sel = c.toARGB32() == _activeColor.toARGB32();
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _activeColor = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 10,
                        ),
                        width: sel ? 40 : 34,
                        height: sel ? 40 : 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel
                                ? t.primary
                                : (c == Colors.white
                                      ? Colors.grey.shade400
                                      : Colors.transparent),
                            width: sel ? 2.5 : 1,
                          ),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Brush tool
            _toolBtn(Icons.brush_rounded, DrawTool.brush, s.brush, t),
            // Hand / pan tool
            _toolBtn(Icons.pan_tool_rounded, DrawTool.hand, s.panTool, t),
            // Eraser
            _toolBtn(
              Icons.auto_fix_normal_rounded,
              DrawTool.eraser,
              s.eraser,
              t,
            ),
            // Thickness
            _actionBtn(
              Icons.line_weight_rounded,
              _showThicknessPicker,
              tooltip: s.strokeThickness,
              badge: _strokeWidth.round().toString(),
            ),
            // Expand/collapse more tools
            _expandBtn(t),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(
    IconData icon,
    DrawTool tool,
    String tooltip,
    AppTheme t, {
    bool compact = false,
  }) {
    final active = _activeTool == tool;
    final size = compact ? 36.0 : 42.0;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => _selectTool(tool),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 3,
            vertical: compact ? 8 : 6,
          ),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active
                ? t.primary.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(
                    color: t.primary.withValues(alpha: 0.45),
                    width: 1.5,
                  )
                : null,
          ),
          child: Icon(
            icon,
            size: compact ? 20 : 22,
            color: active ? t.primary : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    VoidCallback? onTap, {
    required String tooltip,
    Color? color,
    String? badge,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 22,
                  color: color ?? Colors.grey.shade500,
                ),
              ),
              if (badge != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandBtn(AppTheme t) {
    return GestureDetector(
      onTap: () {
        setState(() => _toolbarExpanded = !_toolbarExpanded);
        if (_toolbarExpanded) {
          _toolbarAnim.forward();
        } else {
          _toolbarAnim.reverse();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _toolbarExpanded
              ? t.primary.withValues(alpha: 0.13)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: _toolbarExpanded
              ? Border.all(color: t.primary.withValues(alpha: 0.4), width: 1.5)
              : null,
        ),
        child: AnimatedRotation(
          duration: const Duration(milliseconds: 260),
          turns: _toolbarExpanded ? 0.5 : 0.0,
          child: Icon(
            Icons.expand_less_rounded,
            size: 22,
            color: _toolbarExpanded ? t.primary : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

//  Grid background

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4D4D4)
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

//  Pulsing dot widget

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5 + 0.5 * _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

//  _CanvasScene

class _CanvasScene extends StatefulWidget {
  final Color bgColor;
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final DrawShapeType? currentShapeType;
  final ValueNotifier<List<DrawStroke>> partnerNotifier;
  final Size canvasSize;
  final ValueNotifier<int> repaintNotifier;

  const _CanvasScene({
    required this.bgColor,
    required this.strokes,
    required this.currentPoints,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.currentShapeType,
    required this.partnerNotifier,
    required this.canvasSize,
    required this.repaintNotifier,
  });

  @override
  State<_CanvasScene> createState() => _CanvasSceneState();
}

class _CanvasSceneState extends State<_CanvasScene> {
  late Listenable _repaint;

  // Cache of decoded ui.Image objects keyed by URL/path.
  final Map<String, ui.Image> _imageCache = {};
  final Set<String> _loadingUrls = {};

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([
      widget.repaintNotifier,
      widget.partnerNotifier,
    ]);
    _ensureImagesLoaded(widget.strokes);
  }

  @override
  void didUpdateWidget(covariant _CanvasScene old) {
    super.didUpdateWidget(old);
    if (old.repaintNotifier != widget.repaintNotifier ||
        old.partnerNotifier != widget.partnerNotifier) {
      _repaint = Listenable.merge([
        widget.repaintNotifier,
        widget.partnerNotifier,
      ]);
    }
    if (old.strokes != widget.strokes) {
      _ensureImagesLoaded(widget.strokes);
    }
  }

  void _ensureImagesLoaded(List<DrawStroke> strokes) {
    for (final s in strokes) {
      if (!s.isImageStroke) continue;
      final url = s.imageUrl!;
      if (_imageCache.containsKey(url) || _loadingUrls.contains(url)) continue;
      _loadingUrls.add(url);
      _loadImage(url);
    }
  }

  Future<void> _loadImage(String url) async {
    try {
      ui.Image img;
      if (url.startsWith('/') || url.startsWith('file://')) {
        final path = url.startsWith('file://') ? url.substring(7) : url;
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        img = frame.image;
      } else {
        // Network URL (Firebase Storage download URL).
        final completer = Completer<ui.Image>();
        final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            stream.removeListener(listener);
            completer.complete(info.image);
          },
          onError: (e, _) {
            stream.removeListener(listener);
            completer.completeError(e);
          },
        );
        stream.addListener(listener);
        img = await completer.future;
      }
      if (mounted) {
        setState(() {
          _imageCache[url] = img;
          _loadingUrls.remove(url);
        });
      }
    } catch (e) {
      _loadingUrls.remove(url);
      debugPrint('[Canvas] image load error for $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.bgColor,
      child: Positioned.fill(
        child: CustomPaint(
          painter: _DrawingPainter(
            strokes: widget.strokes,
            currentPoints: widget.currentPoints,
            currentColorValue: widget.currentColorValue,
            currentStrokeWidth: widget.currentStrokeWidth,
            currentIsEraser: widget.currentIsEraser,
            currentShapeType: widget.currentShapeType,
            partnerNotifier: widget.partnerNotifier,
            canvasSize: widget.canvasSize,
            imageCache: _imageCache,
            repaint: _repaint,
          ),
        ),
      ),
    );
  }
}

//  _DrawingPainter

class _DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final DrawShapeType? currentShapeType;
  final ValueNotifier<List<DrawStroke>> partnerNotifier;
  final Size canvasSize;
  final Map<String, ui.Image> imageCache;

  _DrawingPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.currentShapeType,
    required this.partnerNotifier,
    required this.canvasSize,
    required this.imageCache,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final s in strokes) {
      if (s.isImageStroke) {
        final img = s.imageUrl != null ? imageCache[s.imageUrl] : null;
        if (img != null) _drawImageStroke(canvas, s, size, img);
      } else if (s.isFill) {
        _drawFilledStroke(canvas, s, size);
      } else if (s.shapeType != null) {
        _drawShape(
          canvas,
          s.points,
          s.colorValue,
          s.strokeWidth,
          s.shapeType!,
          size,
        );
      } else {
        _drawStroke(
          canvas,
          s.points,
          s.colorValue,
          s.strokeWidth,
          s.isEraser,
          size,
        );
      }
    }

    if (currentPoints.isNotEmpty) {
      if (currentShapeType != null && currentPoints.length >= 2) {
        _drawShape(
          canvas,
          currentPoints,
          currentColorValue,
          currentStrokeWidth,
          currentShapeType!,
          size,
        );
      } else {
        _drawStroke(
          canvas,
          currentPoints,
          currentColorValue,
          currentStrokeWidth,
          currentIsEraser,
          size,
        );
      }
    }

    for (final s in partnerNotifier.value) {
      if (s.isFill) {
        _drawFilledStroke(canvas, s, size, alpha: 0.85);
      } else if (s.shapeType != null && s.points.length >= 2) {
        _drawShape(
          canvas,
          s.points,
          s.colorValue,
          s.strokeWidth,
          s.shapeType!,
          size,
          alpha: 0.85,
        );
      } else if (s.shapeType == null) {
        _drawStroke(
          canvas,
          s.points,
          s.colorValue,
          s.strokeWidth,
          s.isEraser,
          size,
          alpha: 0.85,
        );
      }
    }

    canvas.restore();
  }

  void _drawShape(
    Canvas canvas,
    List<DrawPoint> points,
    int colorValue,
    double strokeWidth,
    DrawShapeType shapeType,
    Size size, {
    double alpha = 1.0,
  }) {
    if (points.length < 2) return;
    final c = Color(colorValue);
    final paint = Paint()
      ..color = alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final s = points.first.toOffset(size);
    final e = points.last.toOffset(size);

    switch (shapeType) {
      case DrawShapeType.line:
        canvas.drawLine(s, e, paint);
      case DrawShapeType.rect:
        canvas.drawRect(Rect.fromPoints(s, e), paint);
      case DrawShapeType.circle:
        final dx = e.dx - s.dx;
        final dy = e.dy - s.dy;
        final radius = math.sqrt(dx * dx + dy * dy) / 2;
        final center = Offset((s.dx + e.dx) / 2, (s.dy + e.dy) / 2);
        canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<DrawPoint> points,
    int colorValue,
    double strokeWidth,
    bool isEraser,
    Size size, {
    double alpha = 1.0,
  }) {
    if (points.isEmpty) return;
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
      final c = Color(colorValue);
      paint.color = alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c;
    }

    if (points.length == 1) {
      if (!isEraser) {
        canvas.drawCircle(
          points.first.toOffset(size),
          strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      }
      return;
    }

    final path = Path();
    final first = points.first.toOffset(size);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i].toOffset(size);
      final p1 = points[i + 1].toOffset(size);
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }

    final last = points.last.toOffset(size);
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  void _drawFilledStroke(
    Canvas canvas,
    DrawStroke stroke,
    Size size, {
    double alpha = 1.0,
  }) {
    final color = Color(stroke.colorValue);
    final paint = Paint()
      ..color = alpha < 1.0 ? color.withValues(alpha: color.a * alpha) : color
      ..style = PaintingStyle.fill;

    switch (stroke.shapeType) {
      case DrawShapeType.rect:
        if (stroke.points.length < 2) return;
        canvas.drawRect(
          Rect.fromPoints(
            stroke.points.first.toOffset(size),
            stroke.points.last.toOffset(size),
          ),
          paint,
        );
      case DrawShapeType.circle:
        if (stroke.points.length < 2) return;
        final start = stroke.points.first.toOffset(size);
        final end = stroke.points.last.toOffset(size);
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final radius = (end - start).distance / 2;
        canvas.drawCircle(center, radius, paint);
      case DrawShapeType.line:
        return;
      case null:
        final path = _buildClosedPath(stroke.points, size);
        if (path != null) canvas.drawPath(path, paint);
    }
  }

  Path? _buildClosedPath(List<DrawPoint> points, Size size) {
    if (points.length < 3) return null;

    final path = Path();
    final first = points.first.toOffset(size);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i].toOffset(size);
      final p1 = points[i + 1].toOffset(size);
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }

    final last = points.last.toOffset(size);
    path.lineTo(last.dx, last.dy);
    path.close();
    return path;
  }

  void _drawImageStroke(
    Canvas canvas,
    DrawStroke stroke,
    Size size,
    ui.Image image,
  ) {
    final x = (stroke.imageX ?? 0.0) * size.width;
    final y = (stroke.imageY ?? 0.0) * size.height;
    final w = (stroke.imageWidth ?? 1.0) * size.width;
    final h = (stroke.imageHeight ?? 1.0) * size.height;
    final dst = Rect.fromLTWH(x, y, w, h);
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) =>
      old.strokes != strokes ||
      old.currentPoints != currentPoints ||
      old.currentColorValue != currentColorValue ||
      old.currentStrokeWidth != currentStrokeWidth ||
      old.currentIsEraser != currentIsEraser ||
      old.currentShapeType != currentShapeType ||
      old.canvasSize != canvasSize ||
      old.imageCache != imageCache;
}

// ignore: unused_element
Future<void> unawaited(Future<void> future) => future;

// --------------- Undo / Redo action types ---------------

class _UndoItem {
  final String? strokeId;
  final Color? oldBg;
  final Color? newBg;

  _UndoItem.stroke(String id) : strokeId = id, oldBg = null, newBg = null;

  _UndoItem.bg({required Color old, required Color current})
    : strokeId = null,
      oldBg = old,
      newBg = current;

  bool get isStroke => strokeId != null;
  bool get isBg => strokeId == null;
}

class _RedoItem {
  final DrawStroke? stroke;
  final Color? bgColor;

  _RedoItem.stroke(DrawStroke s) : stroke = s, bgColor = null;
  _RedoItem.bg(Color c) : stroke = null, bgColor = c;

  bool get isStroke => stroke != null;
}
