import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/coloring_clamp.dart';
import '../models/coloring_picture.dart';
import '../utils/stroke_layer_cache.dart';
import 'coloring_result_screen.dart';
import '../services/memory_repository.dart';
import '../models/memory.dart';
import '../utils/flood_fill.dart';
import '../utils/local_image_paths.dart';
import '../widgets/color_picker_sheet.dart';
import '../utils/color_hex.dart';
import '../widgets/app_sheet.dart';
import '../utils/safe_pick.dart';
import '../utils/safe_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/share_origin.dart';

import '../models/canvas_background.dart';
import '../models/draw_stroke.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/analytics_service.dart';
import '../services/canvas_storage_service.dart';
import '../services/canvas_repository.dart';
import '../services/offline/outbox_service.dart';
import '../services/media_service.dart';
import '../services/locale_service.dart';
import '../utils/canvas_pinch.dart';
import '../theme/app_theme.dart';
import '../widgets/storage_image.dart';
import '../widgets/common/app_dialog.dart';
import '../services/plus_access.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';


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

  /// Unique identifier for this canvas (default: 'main').
  final String canvasId;

  /// Human-readable title shown in the top bar.
  final String? canvasName;

  /// Пиксельная сетка холста: колонки × строки. null — обычный холст.
  final int? pixelW;
  final int? pixelH;

  /// Пропорция листа. null — холст создан до появления листа: он рисуется во
  /// всю область, иначе штрихи, сохранённые в долях старого холста, сплющило бы.
  final double? sheetRatio;

  /// Режим раскраски, выбранный при создании: сюрприз или вместе.
  final ColoringMode? coloringMode;

  /// Раскраска вдвоём: id картинки из каталога. null — обычный холст.
  ///
  /// В этом режиме контур лежит ПОВЕРХ мазков (закрасить рисунок нельзя), лист
  /// делится пополам вертикальной линией, и каждый работает только в своей
  /// половине. Инструменты все те же — кисть, фигуры, заливка, стёрка.
  final String? coloringId;

  const DrawScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.theme,
    this.canvasId = 'main',
    this.canvasName,
    this.pixelW,
    this.pixelH,
    this.sheetRatio,
    this.coloringId,
    this.coloringMode,
  });

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _kCanvasPad = 16.0;
  /// Ширина к высоте листа. 4:5 — вертикаль, привычная по фото в галерее.
  static const double _kSheetRatio = 4 / 5;
  /// Место под подписью формата под листом.
  static const double _kSheetCaption = 22.0;
  /// Скругление листа — как у карточек приложения.
  static const double _kSheetRadius = 14.0;
  /// Цвет клетки на листе — бесплатный фон «Клетка» из макета.
  static const Color _sheetGridColor = Color(0x1A6E4FC0);

  /// Холст в режиме пиксель-арта.
  bool get _isPixel =>
      (widget.pixelW ?? 0) > 1 && (widget.pixelH ?? 0) > 1;
  int get _pxCols => widget.pixelW ?? 1;
  int get _pxRows => widget.pixelH ?? 1;

  /// Пропорция листа: у пиксельного её задаёт сетка, у нового обычного —
  /// сохранённая при создании. null — старый холст без листа.
  double? get _sheetRatio {
    // Раскраска нарисована 1:1: если взять сохранённое соотношение, контур
    // сплющит, а половины перестанут совпадать с линией на картинке. Мета
    // холста соотношение к тому же теряет — в каталог оно не синхронизируется.
    if (_isColoring) return 1.0;
    return _isPixel ? _pxCols / _pxRows : widget.sheetRatio;
  }

  /// Старые холсты живут по-прежнему: лист во всю свободную область.
  bool get _hasSheet => _sheetRatio != null;

  /// Касание переводим в центр клетки: так палец не мажет мимо пикселя, а
  /// точки штриха ложатся ровно в сетку.
  Offset _snapToCell(Offset canvasPx) {
    if (!_isPixel || _canvasSize.isEmpty) return canvasPx;
    final cw = _canvasSize.width / _pxCols;
    final ch = _canvasSize.height / _pxRows;
    final cx = (canvasPx.dx / cw).floor().clamp(0, _pxCols - 1);
    final cy = (canvasPx.dy / ch).floor().clamp(0, _pxRows - 1);
    return Offset((cx + 0.5) * cw, (cy + 0.5) * ch);
  }
  // Live cursor throttle. 60ms felt great but produced ~16 writes/sec per
  // drawing user — combined with the partner's snapshot listener that's
  // ~16 reads/sec on the other side. 150ms (~6.6 fps) still feels fluid for
  // a follow-along cursor and roughly halves both reads and writes.
  static const int _liveThrottleMs = 150;
  static const double _kMinScale = 0.2;
  /// Порог поворота: ниже него щипок считается чистым зумом.
  static const double _kRotationSlop = 0.16; // ≈9°
  /// Показывать направляющие пиксельной сетки. Выбор запоминается: кому-то
  /// удобнее целиться по клеткам, кому-то они мешают смотреть на рисунок.
  bool _showPixelGrid = true;
  static const String _kPixelGridPref = 'draw_pixel_grid_visible';

  bool _rotationUnlocked = false;
  double _rotationSlopUsed = 0.0;
  static const double _kMaxScale = 10.0;

  /// Только для загрузки картинок-вставок в Storage (медиа §4). Холст/штрихи —
  /// на PocketBase через [_canvas].
  final MediaService _fb = MediaService();
  final CanvasRepository _canvas = CanvasRepository();
  final GlobalKey _canvasKey = GlobalKey();

  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<DrawStroke>> _partnerNotifier =
      ValueNotifier<List<DrawStroke>>([]);

  final List<String> _myStrokeIds = [];
  final List<DrawStroke> _redoStack = [];
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

  // ── Раскраска вдвоём ────────────────────────────────────────────────────
  //
  // Контур лежит поверх мазков, поэтому его нельзя закрасить; лист поделён
  // пополам, и каждый пишет только в своей половине. Половина определяется по
  // uid: у кого он меньше по алфавиту — левая. Так обе стороны считают
  // одинаково, без переговоров.

  /// Картинка раскраски. null — обычный холст.
  ColoringPicture? get _coloring => ColoringPicture.byId(_coloringId);

  /// id картинки: из параметра экрана или из меты холста (её мог завести
  /// партнёр — тогда раскраска приезжает сама).
  String? _coloringId;

  ColoringMode _coloringMode = ColoringMode.surprise;
  /// Половины поменяны местами. Общее решение пары: на картинке бывает мальчик
  /// слева и девочка справа, а порядок uid об этом не знает — «у меня выходит
  /// сторона мальчика, а у него наоборот».
  bool _coloringSwap = false;

  /// Кто уже нажал «Готово»: uid → true.
  Map<String, bool> _coloringDone = const {};

  /// Загруженный контур — им же рисуется вуаль поверх чужой половины.
  ui.Image? _coloringOutline;

  bool get _isColoring => _coloring != null;

  /// Моя половина листа.
  ColoringSide get _mySide => coloringSideFor(
        _myUid,
        widget.pairData.partnerUid,
        swapped: _coloringSwap,
      );

  bool get _iAmDone => _coloringDone[_myUid] == true;

  bool get _partnerIsDone {
    final partner = widget.pairData.partnerUid;
    return partner.isNotEmpty && _coloringDone[partner] == true;
  }

  /// Рисунок открыт целиком: оба закончили — или партнёра нет вовсе.
  bool get _coloringRevealed =>
      _coloringMode == ColoringMode.together ||
      widget.pairData.partnerUid.isEmpty ||
      (_iAmDone && _partnerIsDone);

  /// Локальные файлы картинок-штрихов: id → путь. Держим, чтобы после
  /// загрузки на сервер продолжать показывать уже готовый файл — иначе штрих
  /// перерисовывается сетевой картинкой и на кадр пропадает.
  final Map<String, String> _localImagePaths = {};

  /// Недавно выбранные цвета — общий список с остальными экранами рисования.
  List<Color> _recentColors = const [];

  // ── Пипетка ─────────────────────────────────────────────────────────────
  //
  // Снимок холста делается ОДИН раз при включении режима, дальше цвет читается
  // из уже снятых байтов. Снимать на каждое движение пальца нельзя: `toImage`
  // стоит кадра, и лупа плелась бы за пальцем.

  /// Режим взятия цвета включён — следующее касание холста берёт пиксель.
  bool _eyedropperArmed = false;

  /// Сырые пиксели снимка (RGBA) и его размер.
  ByteData? _eyedropperPixels;
  int _eyedropperWidth = 0;
  int _eyedropperHeight = 0;

  /// Где сейчас палец и какой под ним цвет — для лупы.
  Offset? _eyedropperPoint;
  Color? _eyedropperColor;

  /// Текстура листа. Хранится вместе с рисунком, а не в настройках: у каждого
  /// холста своя бумага.
  CanvasBackground _background = CanvasBackground.plain;

  // ── Слои ────────────────────────────────────────────────────────────────
  //
  // Слой — это номер у штриха, а не отдельный холст: так рисунки, сделанные до
  // появления слоёв, просто становятся нижним слоем, и ничего мигрировать не
  // нужно. Порядок отрисовки — сначала по слою, потом по времени.

  /// Сколько слоёв заведено. Минимум один.
  int _layerCount = 1;

  /// На какой слой ложатся новые штрихи.
  int _activeLayer = 0;

  /// Спрятанные слои: их не видно и по ним не попасть заливкой.
  final Set<int> _hiddenLayers = <int>{};

  int _currentColorValue = 0xFF000000;
  double _currentStrokeWidth = 5.0;
  bool _currentIsEraser = false;
  bool _currentIsFilledShape = false;
  DrawShapeType? _currentShapeType;
  bool _isDrawing = false;
  bool _fillShapes = false;

  // ── Image tool ────────────────────────────────────────────────────────────
  String? _selectedImageId;
  DrawStroke? _imgDragBase;
  Offset _imgDragStartPx = Offset.zero;
  double _imgScaleBaseW = 0.5;
  double _imgScaleBaseH = 0.5;
  double _imgScaleBaseRot = 0.0;

  // Hint / onboarding
  bool _showHint = true;
  int _hintStep = 0; // 0=draw, 1=tools, 2=pinch - auto-dismiss

  bool _saving = false;

  // Pan / zoom / rotation
  Size _canvasSize = Size.zero;
  /// Сигнал «вид холста поменялся»: масштаб, смещение или поворот.
  ///
  /// Пока панорама шла через `setState`, на каждом сэмпле жеста заново
  /// строился ВЕСЬ экран рисования — панели инструментов, палитра, слои,
  /// список кистей. Отсюда жалоба «двигаю экран, он очень лагает». Теперь
  /// перестраивается только сам холст и табличка с процентом.
  final ValueNotifier<int> _viewTick = ValueNotifier<int>(0);

  void _bumpView() => _viewTick.value++;

  double _scale = 1.0;

  /// Щипок на паузе: пальцев стало меньше двух и холст ждёт возвращения
  /// второго, а не едет за оставшимся.
  bool _pinchPaused = false;
  double _canvasRotation = 0.0; // radians
  Offset _canvasOffset = Offset.zero;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _baseOffset = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  bool _isZooming = false;
  int? _drawingPointerId;
  int _orderCounter = 0;
  DateTime _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);

  // Palm tool
  Offset _palmPanStart = Offset.zero;
  Offset _palmBaseOffset = Offset.zero;

  // Toolbar expansion
  bool _toolbarExpanded = false;
  late AnimationController _toolbarAnim;

  // Partner cursor pulse animation
  late AnimationController _pulseAnim;

  StreamSubscription? _strokesSub;
  StreamSubscription? _liveSub;
  StreamSubscription? _canvasMetaSub;
  Timer? _staleTimer;
  Timer? _hintTimer;
  int? _lastClearVersion;

  String get _myUid => widget.userData.uid;
  String get _groupId => widget.pairData.pairId;
  String get _canvasId => widget.canvasId;
  bool get _hasSharedCanvas => _groupId.isNotEmpty;

  bool get _isShapeTool =>
      _activeTool == DrawTool.line ||
      _activeTool == DrawTool.rect ||
      _activeTool == DrawTool.circle ||
      _activeTool == DrawTool.triangle;

  DrawShapeType? get _activeShapeType {
    switch (_activeTool) {
      case DrawTool.line:
        return DrawShapeType.line;
      case DrawTool.rect:
        return DrawShapeType.rect;
      case DrawTool.circle:
        return DrawShapeType.circle;
      case DrawTool.triangle:
        return DrawShapeType.triangle;
      default:
        return null;
    }
  }

  bool get _canUndo => _myStrokeIds.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _activeColor = widget.pairData.isPaired
        ? _colorForUser(_myUid)
        : const Color(0xFF000000);
    unawaited(_loadPixelGridPref());
    unawaited(_restoreBackground());
    unawaited(_reloadRecentColors());

    // Раскраска: параметры пришли с экрана выбора — сразу заводим её на холсте,
    // чтобы партнёр увидел ту же картинку и тот же режим.
    if (widget.coloringId != null) {
      _coloringId = widget.coloringId;
      _coloringMode = widget.coloringMode ?? ColoringMode.surprise;
      unawaited(_loadColoringOutline());
      unawaited(_startColoring(_coloringId!, _coloringMode));
    }
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
    if (!_hasSharedCanvas) _loadSoloStrokes();
    _markPresence(true);
    _scheduleHints();
    unawaited(
      AnalyticsService.instance.logCanvasOpened(shared: _hasSharedCanvas),
    );
  }

  // ── Solo stroke persistence ───────────────────────────────────────────────

  Future<void> _loadSoloStrokes() async {
    final strokes = await CanvasStorageService.instance.loadLocalStrokes(
      _myUid,
      _canvasId,
      groupId: _groupId,
    );
    if (!mounted || strokes.isEmpty) return;
    setState(() {
      _visibleStrokes = List<DrawStroke>.from(strokes)
        ..sort(_compareStrokes);
      // Restore undo history so the user can undo loaded strokes.
      _myStrokeIds
        ..clear()
        ..addAll(strokes.map((s) => s.id));
      if (strokes.isNotEmpty) {
        _orderCounter =
            strokes.map((s) => s.orderIndex).reduce((a, b) => a > b ? a : b) +
                1;
      }
    });
  }

  void _saveSoloStrokes() {
    CanvasStorageService.instance.saveLocalStrokes(
      _myUid,
      _canvasId,
      _visibleStrokes,
      groupId: _groupId,
    );
  }

  //  Thumbnail capture

  /// Saves a PNG thumbnail to [CanvasStorageService] then pops the route.
  Future<void> _captureThumbnailAndExit() async {
    await _captureThumbnail();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _captureThumbnail() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      await CanvasStorageService.instance.updatePreview(
        _myUid,
        _canvasId,
        byteData.buffer.asUint8List(),
        groupId: _groupId,
      );
    } catch (e) {
      debugPrint('[Draw] thumbnail error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _markPresence(false);
    _strokesSub?.cancel();
    _liveSub?.cancel();
    _canvasMetaSub?.cancel();
    _staleTimer?.cancel();
    _hintTimer?.cancel();
    _toolbarAnim.dispose();
    _pulseAnim.dispose();
    _resetCtrl?.dispose();
    _clearLiveStroke();
    _repaintNotifier.dispose();
    _viewTick.dispose();
    _partnerNotifier.dispose();
    super.dispose();
  }

  /// No-op: presence была write-only (нигде не читалась) → при переезде на PB
  /// не переносим (миграция §3). Метод оставлен ради вызовов из lifecycle.
  void _markPresence(bool present) {}

  /// ���������� ��� ��������� ������ ��� ����� ���������� � ���.
  /// ��� ������������� ���������� ����� ����, ��� �������
  /// ���������� PointerUp-������� (������ �����������, ������ � �.�.).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _activePointers.clear();
      _isZooming = false;
      _cancelCurrentGesture();
      _markPresence(false);
    } else if (state == AppLifecycleState.resumed) {
      _markPresence(true);
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

    _strokesSub = _canvas
        .watchStrokes(_groupId, _canvasId)
        .handleError((e) => debugPrint('[Draw] strokes error: $e'))
        .listen(_onRemoteStrokes);

    _liveSub = _canvas
        .watchLive(_groupId, _canvasId, _myUid)
        .handleError((e) => debugPrint('[Draw] live error: $e'))
        .listen(_onLiveStrokes);

    // Мета холста (bgColor + clearVersion + rotation) одной подпиской на запись
    // canvas_meta — все три поля в одном документе.
    _canvasMetaSub = _canvas
        .watchMeta(_groupId, _canvasId)
        .handleError((e) => debugPrint('[Draw] canvasMeta error: $e'))
        .listen(_onCanvasMeta);

    // Safety: ensure listeners don't crash the app if rules are restrictive
    _strokesSub?.onError((e) => debugPrint('[Draw] global strokes error: $e'));

    _staleTimer = Timer.periodic(
      const Duration(seconds: 2),
      _removeStalePartners,
    );
  }

  void _onRemoteStrokes(List<DrawStroke> rawList) {
    if (!mounted) return;

    // CanvasRepository уже отдаёт распарсенные DrawStroke (через fromPb) —
    // копируем перед сортировкой (список из стрима неизменяемый).
    final parsed = List<DrawStroke>.from(rawList);
    parsed.sort(_compareStrokes);
    _remoteStrokes = parsed;

    final remainingPending = Map<String, DrawStroke>.from(_pendingLocalStrokes);
    final updatedMyIds = List<String>.from(_myStrokeIds);

    for (final remote in parsed) {
      final matchKey = remainingPending.entries
          .where((e) => _looksLikeSameStroke(remote, e.value))
          .map((e) => e.key)
          .firstOrNull;
      if (matchKey != null) {
        remainingPending.remove(matchKey);
        for (int i = 0; i < updatedMyIds.length; i++) {
          if (updatedMyIds[i] == matchKey) updatedMyIds[i] = remote.id;
        }
        // Картинку-штрих (заливка, вставленное фото) продолжаем рисовать с
        // диска — см. [adoptLocalImagePath].
        adoptLocalImagePath(_localImagePaths, matchKey, remote.id);
      }
    }

    _pendingLocalStrokes
      ..clear()
      ..addAll(remainingPending);
    _myStrokeIds
      ..clear()
      ..addAll(updatedMyIds);

    if (parsed.isNotEmpty || remainingPending.isNotEmpty) {
      final maxOrder = [
        ...parsed.map((s) => s.orderIndex),
        ...remainingPending.values.map((s) => s.orderIndex),
      ].reduce(math.max);
      _orderCounter = maxOrder + 1;
    }

    setState(() => _visibleStrokes = _composeVisibleStrokes());
  }

  void _onCanvasMeta(CanvasMetaUpdate meta) {
    if (!mounted) return;

    final version = meta.clearVersion;
    if (version != null && _lastClearVersion != version) {
      _lastClearVersion = version;
      _myStrokeIds.clear();
      _redoStack.clear();
      _pendingLocalStrokes.clear();
      _cancelledPendingStrokeIds.clear();
      _remoteStrokes = [];
      _partnerLiveMap.clear();
      _partnerTimestamps.clear();
      _partnerNotifier.value = const [];
      _visibleStrokes = [];
    }

    // Как человек держит лист — его личное дело: масштаб, сдвиг и поворот
    // никуда не уезжают. Раньше поворот ехал к обоим, и пара сидела с одним
    // экраном на двоих: партнёр развернул лист щипком — лист развернулся и у
    // тебя, посреди твоего же мазка. Сперва это сняли с раскрасок (там половина
    // у каждого), теперь и с общего холста. Общими остаются штрихи, фон,
    // очистка и раскраска — то, что видно в самом рисунке.

    bool bgChanged = false;
    final bg = meta.bgColor;
    if (bg != null) {
      final next = Color(bg);
      if (next.toARGB32() != _bgColor.toARGB32()) {
        _bgColor = next;
        bgChanged = true;
      }
    }

    // Раскраска приезжает метой: партнёр мог завести её первым.
    var coloringChanged = false;
    final remoteColoring = meta.coloringId;
    if (remoteColoring != null &&
        remoteColoring.isNotEmpty &&
        remoteColoring != _coloringId) {
      _coloringId = remoteColoring;
      coloringChanged = true;
      unawaited(_loadColoringOutline());
    }
    final remoteMode = meta.coloringMode;
    if (remoteMode != null && remoteMode.isNotEmpty) {
      final next = ColoringMode.fromStorage(remoteMode);
      if (next != _coloringMode) {
        _coloringMode = next;
        coloringChanged = true;
      }
    }
    final remoteSwap = meta.coloringSwap;
    if (remoteSwap != null && remoteSwap != _coloringSwap) {
      _coloringSwap = remoteSwap;
      coloringChanged = true;
    }
    final done = meta.coloringDone;
    if (done != null) {
      final next = <String, bool>{
        for (final e in done.entries) e.key: e.value == true,
      };
      if (next.toString() != _coloringDone.toString()) {
        _coloringDone = next;
        coloringChanged = true;
      }
    }

    if (version != null || bgChanged || coloringChanged) {
      setState(() {});
    }
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
    // Слой важнее времени: что нарисовано на верхнем слое, лежит поверх, даже
    // если нарисовано раньше.
    final l = a.layer.compareTo(b.layer);
    if (l != 0) return l;
    final o = a.orderIndex.compareTo(b.orderIndex);
    if (o != 0) return o;
    // Стабильный тай-брейкер по userId: id у локального optimistic-штриха
    // отличается от id, который вернёт Firestore, и при коллизии orderIndex
    // между двумя рисующими порядок слоёв «прыгал» после подтверждения записи.
    final u = a.userId.compareTo(b.userId);
    return u != 0 ? u : a.id.compareTo(b.id);
  }

  List<DrawStroke> _composeVisibleStrokes() {
    final combined = <DrawStroke>[
      ..._remoteStrokes,
      ..._pendingLocalStrokes.values,
    ];
    combined.sort(_compareStrokes);
    // Число слоёв выводим из самих штрихов: партнёр мог добавить слой, и его
    // рисунок не должен провалиться в нижний.
    final maxLayer = combined.isEmpty
        ? 0
        : combined.map((s) => s.layer).reduce((a, b) => a > b ? a : b);
    if (maxLayer + 1 > _layerCount) _layerCount = maxLayer + 1;

    if (_hiddenLayers.isEmpty) return combined;
    return combined.where((s) => !_hiddenLayers.contains(s.layer)).toList();
  }

  bool _looksLikeSameStroke(DrawStroke remote, DrawStroke local) {
    if (remote.userId != local.userId) return false;
    if (remote.orderIndex != local.orderIndex) return false;
    if (remote.colorValue != local.colorValue) return false;
    if ((remote.strokeWidth - local.strokeWidth).abs() > 0.01) return false;
    if (remote.isEraser != local.isEraser) return false;
    if (remote.shapeType != local.shapeType) return false;
    if (remote.isImageStroke != local.isImageStroke) return false;

    if (remote.isImageStroke) {
      // Match by userId + orderIndex only — URL changes after upload, position changes on drag
      return true;
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

  /// Rotates [o] by [angle] radians around the origin.
  Offset _rotateOffset(Offset o, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Offset(o.dx * cos - o.dy * sin, o.dx * sin + o.dy * cos);
  }

  /// Converts a screen-local point to canvas coordinates,
  /// accounting for pan, rotation, and scale.
  Offset _screenToCanvas(Offset localPoint) {
    final translated = localPoint - _canvasOffset;
    final rotated = _rotateOffset(translated, -_canvasRotation);
    return rotated / _scale;
  }

  //  Tool selection

  void _selectTool(DrawTool tool) {
    _disarmEyedropper();
    _cancelCurrentGesture();
    setState(() {
      _activeTool = tool;
      if (tool != DrawTool.image) _selectedImageId = null;
    });
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

    // Раскраска: чужая половина не принимает касаний ни в каком режиме — даже
    // когда её видно. Каждый отвечает за свою.
    if (_isColoring && !_inMySide(_screenToCanvas(localPoint))) {
      _showHalfHint();
      return;
    }

    if (_activeTool == DrawTool.fill) {
      _applyFill(localPoint);
      return;
    }

    _redoStack.clear();
    _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPushedPointsCount = 0;
    _lastPushedTipX = double.nan;
    _lastPushedTipY = double.nan;
    if (_showHint) setState(() => _showHint = false);

    if (_isShapeTool) {
      final pt = DrawPoint.fromOffset(_screenToCanvas(localPoint), _canvasSize);
      setState(() {
        _currentPoints
          ..clear()
          ..add(pt)
          ..add(pt);
        _currentShapeType = _activeShapeType;
        _currentColorValue = _activeColor.toARGB32();
        _currentStrokeWidth = _strokeWidth;
        _currentIsEraser = false;
        _currentIsFilledShape = _fillShapes;
        _isDrawing = true;
      });
      _repaintNotifier.value++;
      return;
    }

    setState(() {
      _currentPoints
        ..clear()
        ..add(DrawPoint.fromOffset(
          _snapToCell(_screenToCanvas(localPoint)),
          _canvasSize,
        ));
      _currentShapeType = null;
      _currentColorValue = _activeTool == DrawTool.eraser
          ? _bgColor.toARGB32()
          : _activeColor.toARGB32();
      _currentStrokeWidth = _strokeWidth;
      _currentIsEraser = _activeTool == DrawTool.eraser;
      _currentIsFilledShape = false;
      _isDrawing = true;
    });
    _repaintNotifier.value++;
  }

  void _updateStroke(Offset localPoint) {
    if (!_isDrawing || _canvasSize.isEmpty) return;
    if (_isColoring) localPoint = _clampToMySide(localPoint);
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
      final pt = DrawPoint.fromOffset(
        _snapToCell(_screenToCanvas(localPoint)),
        _canvasSize,
      );
      // В пиксельном режиме палец внутри одной клетки не должен плодить точки:
      // штрих раздувается, а рисунок от этого не меняется.
      if (_isPixel && _currentPoints.isNotEmpty) {
        final last = _currentPoints.last;
        if ((last.x - pt.x).abs() < 1e-6 && (last.y - pt.y).abs() < 1e-6) {
          return;
        }
      }
      _currentPoints.add(pt);
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

  int _lastPushedPointsCount = 0;
  double _lastPushedTipX = double.nan;
  double _lastPushedTipY = double.nan;

  Future<void> _pushLiveStrokeAsync() async {
    if (!_hasSharedCanvas || _currentPoints.isEmpty) return;
    // Skip the write if the stroke is identical to the last one we pushed.
    // For freehand strokes the point count grows, for shape tools the count
    // stays at 2 but the endpoint moves — both cases need to be covered.
    final tip = _currentPoints.last;
    if (_currentPoints.length == _lastPushedPointsCount &&
        tip.x == _lastPushedTipX &&
        tip.y == _lastPushedTipY) {
      return;
    }
    _lastPushedPointsCount = _currentPoints.length;
    _lastPushedTipX = tip.x;
    _lastPushedTipY = tip.y;

    final stroke = DrawStroke(
      id: 'live_$_myUid',
      userId: _myUid,
      colorValue: _currentColorValue,
      strokeWidth: _currentStrokeWidth,
      points: List<DrawPoint>.unmodifiable(_currentPoints),
      isEraser: _currentIsEraser,
      isFilledShape: _currentIsFilledShape,
      shapeType: _currentShapeType,
      orderIndex: -1,
    );
    try {
      await _canvas.setLive(_groupId, _canvasId, _myUid, stroke.toLiveMap());
    } catch (e) {
      debugPrint('[Draw] live push error: $e');
    }
  }

  void _clearLiveStroke() {
    if (!_hasSharedCanvas) return;
    _canvas
        .clearLive(_groupId, _canvasId, _myUid)
        .catchError((e) => debugPrint('[Draw] clear live error: $e'));
  }

  void _onPointerDown(PointerDownEvent event) {
    // Пипетка перехватывает касание целиком: рисовать в этом режиме нельзя,
    // палец только выбирает цвет.
    if (_eyedropperArmed) {
      _trackEyedropper(event.localPosition);
      return;
    }

    // ���� ����� ����� �������� � Set ��� �������� �������, ��
    // ����� ����� �������� � ��� ������� ������������ PointerUp
    // (�����������, ������). ������� ��������� �����.
    if (_activePointers.isEmpty) {
      _isZooming = false;
      if (_isDrawing) _cancelCurrentGesture();
    }

    _activePointers.add(event.pointer);

    if (_activePointers.length >= 2) {
      _isZooming = false; // дальше подхватит onScaleStart
      // Второй палец раньше стирал начатую линию целиком: коснулись ладонью —
      // и штрих пропал. Теперь он фиксируется, а зум начинается со следующего
      // события. Терять работу из-за случайного касания нельзя.
      if (_isDrawing && _currentPoints.length > 1) {
        _finishStroke();
      } else {
        _cancelCurrentGesture();
      }
      return;
    }

    // ���� ����� � ������������� ���������� zoom, ���� �� �����
    _isZooming = false;

    // Palm tool
    if (_activeTool == DrawTool.palm) {
      _palmPanStart = event.localPosition;
      _palmBaseOffset = _canvasOffset;
      return;
    }

    // Image tool
    if (_activeTool == DrawTool.image) {
      final hit = _findImageAt(event.localPosition);
      if (hit != null) {
        // Tapped on an image — select and prepare for drag
        setState(() => _selectedImageId = hit.id);
        _imgDragBase = hit;
        _imgDragStartPx = _screenToCanvas(event.localPosition);
      } else {
        // Tapped on empty space — keep selection so pinch still works
        _imgDragBase = null;
      }
      return;
    }

    _drawingPointerId = event.pointer;
    _startStroke(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_eyedropperArmed) {
      _trackEyedropper(event.localPosition);
      return;
    }
    if (_isZooming || _activePointers.length != 1) return;

    // Palm tool
    if (_activeTool == DrawTool.palm) {
      final delta = event.localPosition - _palmPanStart;
      _canvasOffset = _palmBaseOffset + delta;
      _bumpView();
      return;
    }

    // Image drag
    if (_activeTool == DrawTool.image &&
        _imgDragBase != null &&
        _selectedImageId != null &&
        !_canvasSize.isEmpty) {
      final canvasPx = _screenToCanvas(event.localPosition);
      final delta = canvasPx - _imgDragStartPx;
      final newX = (_imgDragBase!.imageX ?? 0.5) + delta.dx / _canvasSize.width;
      final newY =
          (_imgDragBase!.imageY ?? 0.5) + delta.dy / _canvasSize.height;
      _applyImageUpdate(_copyImageStroke(_imgDragBase!, x: newX, y: newY));
      return;
    }

    if (_drawingPointerId != event.pointer) return;
    _updateStroke(event.localPosition);
  }

  void _onPointerUp(PointerEvent event) {
    if (_eyedropperArmed) {
      _activePointers.remove(event.pointer);
      _finishEyedropper();
      return;
    }
    final wasDrawing = _drawingPointerId == event.pointer;
    _activePointers.remove(event.pointer);

    if (wasDrawing && !_isZooming) {
      _finishStroke();
    }

    if (_activePointers.isEmpty) {
      _drawingPointerId = null;
      _isZooming = false;
      if (_isDrawing) _cancelCurrentGesture();
      // Sync image position to Firestore when drag ends
      if (_activeTool == DrawTool.image && _imgDragBase != null) {
        final img = _findImageById(_selectedImageId ?? '');
        if (img != null) unawaited(_syncImageToFirestore(img));
        _imgDragBase = null;
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_eyedropperArmed) return;
    if (details.pointerCount < 2) return;
    _isZooming = true;
    _pinchPaused = false;
    _rotationUnlocked = false;
    _rotationSlopUsed = 0.0;
    _cancelCurrentGesture();
    _baseScale = _scale;
    _baseOffset = _canvasOffset;
    _baseFocalPoint = details.localFocalPoint;
    _baseRotation = _canvasRotation;
    // Save image base transform for pinch on selected image
    if (_activeTool == DrawTool.image && _selectedImageId != null) {
      final img = _findImageById(_selectedImageId!);
      if (img != null) {
        _imgDragBase = img;
        _imgScaleBaseW = img.imageWidth ?? 0.5;
        _imgScaleBaseH = img.imageHeight ?? 0.5;
        _imgScaleBaseRot = img.imageRotation ?? 0.0;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_eyedropperArmed) return;
    if (!_isZooming && details.pointerCount < 2) return;
    _isZooming = true;

    // Пальцев снова меньше двух: система продолжает слать события, а фокус
    // скачком уезжает к оставшемуся пальцу — лист прыгал за ним и «метался
    // туда-сюда». Пока палец один, холст стоит; вернулся второй — берём новую
    // опору и только потом двигаем.
    switch (pinchAction(
        pointerCount: details.pointerCount, paused: _pinchPaused)) {
      case PinchAction.pause:
        _pinchPaused = true;
        return;
      case PinchAction.rebase:
        _pinchPaused = false;
        _baseScale = _scale;
        _baseOffset = _canvasOffset;
        _baseRotation = _canvasRotation;
        _baseFocalPoint = details.localFocalPoint;
        _rotationUnlocked = false;
        _rotationSlopUsed = 0.0;
        return;
      case PinchAction.transform:
        break;
    }

    // Image pinch: scale + rotate the selected image
    if (_activeTool == DrawTool.image &&
        _imgDragBase != null &&
        _selectedImageId != null) {
      final newW = (_imgScaleBaseW * details.scale).clamp(0.05, 2.0);
      final newH = (_imgScaleBaseH * details.scale).clamp(0.05, 2.0);
      final newRot = _imgScaleBaseRot + details.rotation;
      _applyImageUpdate(
        _copyImageStroke(_imgDragBase!, w: newW, h: newH, rot: newRot),
      );
      return;
    }

    final nextScale = (_baseScale * details.scale).clamp(
      _kMinScale,
      _kMaxScale,
    );
    // Поворот включается только после заметного разворота пальцев (~9°):
    // раньше лист кренился от любого щипка, и его приходилось выправлять.
    // После срабатывания порог вычитается, иначе лист прыгнул бы рывком.
    if (!_rotationUnlocked && details.rotation.abs() > _kRotationSlop) {
      _rotationUnlocked = true;
      _rotationSlopUsed =
          details.rotation.sign * _kRotationSlop;
    }
    final nextRotation = _rotationUnlocked
        ? _baseRotation + details.rotation - _rotationSlopUsed
        : _baseRotation;
    final nextOffset = pinchOffset(
      focal: details.localFocalPoint,
      baseFocal: _baseFocalPoint,
      baseOffset: _baseOffset,
      baseScale: _baseScale,
      nextScale: nextScale,
      baseRotation: _baseRotation,
      nextRotation: nextRotation,
    );
    _scale = nextScale;
    _canvasRotation = nextRotation;
    _canvasOffset = nextOffset;
    _bumpView();
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _isZooming = false;
    _pinchPaused = false;
    // Sync image transform to Firestore after pinch ends
    if (_activeTool == DrawTool.image && _imgDragBase != null) {
      final img = _findImageById(_selectedImageId ?? '');
      if (img != null) unawaited(_syncImageToFirestore(img));
      _imgDragBase = null;
    }
    if (_activePointers.isEmpty) {
      _drawingPointerId = null;
      if (_isDrawing) _cancelCurrentGesture();
    }
    // Поворот листа партнёру не уходит: см. `_onCanvasMeta`.
  }

  /// Возврат листа на место — анимацией, а не прыжком: рывок сбивает с толку,
  /// особенно когда лист был повёрнут.
  Future<void> _togglePixelGrid() async {
    setState(() => _showPixelGrid = !_showPixelGrid);
    _repaintNotifier.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPixelGridPref, _showPixelGrid);
    } catch (_) {}
  }

  Future<void> _loadPixelGridPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_kPixelGridPref);
      if (v != null && mounted && v != _showPixelGrid) {
        setState(() => _showPixelGrid = v);
      }
    } catch (_) {}
  }

  void _resetZoom() {
    _resetCtrl?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _resetCtrl = ctrl;
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    final fromScale = _scale;
    final fromOffset = _canvasOffset;
    final fromRot = _canvasRotation;
    ctrl.addListener(() {
      final t = curve.value;
      _scale = fromScale + (1.0 - fromScale) * t;
      _canvasOffset = Offset.lerp(fromOffset, Offset.zero, t)!;
      _canvasRotation = fromRot * (1 - t);
      _bumpView();
    });
    ctrl.forward().whenComplete(() {
      ctrl.dispose();
      if (identical(_resetCtrl, ctrl)) _resetCtrl = null;
    });
  }

  AnimationController? _resetCtrl;

  // ── Image helpers ──────────────────────────────────────────────────────────

  DrawStroke? _findImageAt(Offset screenPos) {
    if (_canvasSize.isEmpty) return null;
    final cp = _screenToCanvas(screenPos);
    final nx = cp.dx / _canvasSize.width;
    final ny = cp.dy / _canvasSize.height;
    for (final s in _visibleStrokes.reversed) {
      if (!s.isImageStroke) continue;
      final cx = s.imageX ?? 0.5;
      final cy = s.imageY ?? 0.5;
      final hw = (s.imageWidth ?? 0.5) / 2;
      final hh = (s.imageHeight ?? 0.5) / 2;
      if (nx >= cx - hw && nx <= cx + hw && ny >= cy - hh && ny <= cy + hh) {
        return s;
      }
    }
    return null;
  }

  DrawStroke? _findImageById(String id) =>
      _visibleStrokes.where((s) => s.id == id).firstOrNull;

  DrawStroke _copyImageStroke(
    DrawStroke s, {
    double? x,
    double? y,
    double? w,
    double? h,
    double? rot,
    String? url,
  }) => DrawStroke(
    id: s.id,
    userId: s.userId,
    colorValue: s.colorValue,
    strokeWidth: s.strokeWidth,
    points: s.points,
    orderIndex: s.orderIndex,
    imageUrl: url ?? s.imageUrl,
    imageX: x ?? s.imageX,
    imageY: y ?? s.imageY,
    imageWidth: w ?? s.imageWidth,
    imageHeight: h ?? s.imageHeight,
    imageRotation: rot ?? s.imageRotation,
  );

  void _applyImageUpdate(DrawStroke updated) {
    final id = updated.id;
    if (_pendingLocalStrokes.containsKey(id)) {
      _pendingLocalStrokes[id] = updated;
      setState(() => _visibleStrokes = _composeVisibleStrokes());
      return;
    }
    final ri = _remoteStrokes.indexWhere((s) => s.id == id);
    if (ri >= 0) {
      _remoteStrokes[ri] = updated;
      setState(() => _visibleStrokes = _composeVisibleStrokes());
      return;
    }
    // Solo canvas
    setState(() {
      final vi = _visibleStrokes.indexWhere((s) => s.id == id);
      if (vi >= 0) _visibleStrokes[vi] = updated;
    });
  }

  Future<void> _syncImageToFirestore(DrawStroke stroke) async {
    if (!_hasSharedCanvas) return;
    if (!_remoteStrokes.any((s) => s.id == stroke.id)) return;
    try {
      await _canvas.patchStroke(stroke.id, {
        'imageX': stroke.imageX,
        'imageY': stroke.imageY,
        'imageWidth': stroke.imageWidth,
        'imageHeight': stroke.imageHeight,
        'imageRotation': stroke.imageRotation,
      });
    } catch (e) {
      debugPrint('[Draw] image sync error: $e');
    }
  }

  Future<void> _pickAndAddImage() async {
    final picker = ImagePicker();
    final xFile = await safePick(
      () => picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      ),
    );
    if (xFile == null || !mounted) return;

    final id = 'img_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter';
    final stroke = DrawStroke(
      id: id,
      userId: _myUid,
      colorValue: 0xFF000000,
      strokeWidth: 0,
      points: const [],
      orderIndex: _orderCounter,
      layer: _activeLayer,
      imageUrl: 'file://${xFile.path}',
      imageX: 0.5,
      imageY: 0.5,
      imageWidth: 0.5,
      imageHeight: 0.5,
      imageRotation: 0.0,
    );
    _orderCounter++;
    setState(() {
      _selectedImageId = id;
      _activeTool = DrawTool.image;
    });

    if (!_hasSharedCanvas) {
      // Соло-холст: локальный file:// путь рисует только это устройство — ок.
      _submitStroke(stroke);
      return;
    }

    // Общий холст: показываем картинку себе сразу (file://), но в Firestore
    // локальный путь НЕ пишем — партнёр его не откроет. Сначала грузим файл в
    // Storage и только с готовым сетевым URL коммитим штрих, чтобы партнёр тоже
    // увидел картинку, а не «битый файл».
    setState(() {
      _pendingLocalStrokes[id] = stroke;
      _visibleStrokes = _composeVisibleStrokes();
    });
    _myStrokeIds.add(id);
    unawaited(_uploadImageAsync(id, xFile.path));
  }

  Future<void> _uploadImageAsync(String localStrokeId, String localPath) async {
    _localImagePaths[localStrokeId] = localPath;
    final ext = localPath.split('.').last.toLowerCase();
    final dest = 'canvas/$_groupId/$_canvasId/$localStrokeId.$ext';
    final url = await _fb.uploadFile(localPath, dest);
    if (!mounted) return;

    // Штрих могли отменить/удалить, пока шла загрузка — тогда ничего не коммитим.
    final pending = _pendingLocalStrokes[localStrokeId];
    if (pending == null) return;

    if (url == null) {
      // Загрузка не удалась — убираем оптимистичный штрих и историю undo.
      debugPrint('[Draw] image upload failed, dropping stroke $localStrokeId');
      _cancelledPendingStrokeIds.remove(localStrokeId);
      _myStrokeIds.remove(localStrokeId);
      setState(() {
        _pendingLocalStrokes.remove(localStrokeId);
        if (_selectedImageId == localStrokeId) _selectedImageId = null;
        _visibleStrokes = _composeVisibleStrokes();
      });
      return;
    }

    // Подменяем file:// на сетевой URL (берём актуальный pending — вдруг штрих
    // двигали во время загрузки) и коммитим штрих в Firestore уже с ним.
    final networked = _copyImageStroke(pending, url: url);
    setState(() {
      _pendingLocalStrokes[localStrokeId] = networked;
      _visibleStrokes = _composeVisibleStrokes();
    });
    _commitImageStroke(localStrokeId, networked);
  }

  /// Записать картинку-штрих в Firestore (с уже сетевым URL). Повторяет логику
  /// сверки optimistic-штриха из [_submitStroke]: при ошибке откатывает локально,
  /// при отмене во время записи — удаляет уже созданный документ.
  void _commitImageStroke(String localId, DrawStroke stroke) {
    _canvas
        .addStroke(_groupId, _canvasId, stroke.toFirestore())
        .then((remoteId) async {
          if (remoteId.isEmpty) throw Exception('Empty stroke id');
          if (_cancelledPendingStrokeIds.remove(localId)) {
            if (!await _canvas.deleteStroke(remoteId)) {
              await OutboxService.instance
                  .enqueue('strokeDelete', {'id': remoteId});
            }
          }
        })
        .catchError((e) {
          debugPrint('[Draw] image commit error: $e');
          if (!mounted) return;
          _myStrokeIds.remove(localId);
          setState(() {
            _pendingLocalStrokes.remove(localId);
            _visibleStrokes = _composeVisibleStrokes();
          });
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
      isFilledShape: _currentIsFilledShape,
      shapeType: shapeType,
      orderIndex: _orderCounter,
      layer: _activeLayer,
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
      _myStrokeIds.add(stroke.id);
      _saveSoloStrokes();
      return;
    }

    setState(() {
      _pendingLocalStrokes[stroke.id] = stroke;
      _visibleStrokes = _composeVisibleStrokes();
    });
    _myStrokeIds.add(stroke.id);

    _canvas
        .addStroke(_groupId, _canvasId, stroke.toFirestore())
        .then((remoteId) async {
          if (remoteId.isEmpty) throw Exception('Empty stroke id');
          if (_cancelledPendingStrokeIds.remove(stroke.id)) {
            if (!await _canvas.deleteStroke(remoteId)) {
              await OutboxService.instance
                  .enqueue('strokeDelete', {'id': remoteId});
            }
          }
        })
        .catchError((e) {
          debugPrint('[Draw] commit error: $e');
          if (!mounted) return;
          setState(() {
            _pendingLocalStrokes.remove(stroke.id);
            _visibleStrokes = _composeVisibleStrokes();
          });
          _myStrokeIds.remove(stroke.id);
        });
  }

  //  Undo / Redo

  Future<void> _undo() async {
    if (_myStrokeIds.isEmpty) return;
    final undoKey = _myStrokeIds.removeLast();

    DrawStroke? removed;
    String? remoteIdForDelete;

    if (_pendingLocalStrokes.containsKey(undoKey)) {
      removed = _pendingLocalStrokes.remove(undoKey);
      _cancelledPendingStrokeIds.add(undoKey);
    } else {
      removed = _visibleStrokes.where((s) => s.id == undoKey).firstOrNull;
      if (removed != null && _hasSharedCanvas) {
        _remoteStrokes = _remoteStrokes.where((s) => s.id != undoKey).toList();
        remoteIdForDelete = undoKey;
      }
    }

    if (removed == null) return;
    _redoStack.add(removed);

    if (_hasSharedCanvas) {
      setState(() => _visibleStrokes = _composeVisibleStrokes());
    } else {
      // Solo: strokes live directly in _visibleStrokes, not in remote/pending
      setState(() {
        _visibleStrokes = _visibleStrokes
            .where((s) => s.id != undoKey)
            .toList();
      });
      _saveSoloStrokes();
    }

    if (!_hasSharedCanvas || remoteIdForDelete == null) return;

    // Отмена не отыгрывается назад. Человек убрал штрих — значит его нет, а
    // сервер догоняет очередью: она повторяет с паузами и переживает
    // перезапуск приложения. Прежний код при отказе возвращал штрих на холст,
    // и это читалось как «отменённые штрихи восстанавливаются»; хуже того,
    // репозиторий отказ проглатывал, поэтому чаще всего штрих оставался в базе
    // молча и всплывал при следующей загрузке.
    var done = false;
    try {
      done = await _canvas.deleteStroke(remoteIdForDelete);
    } catch (e) {
      debugPrint('[Draw] undo: удаление не прошло ($e)');
    }
    if (!done) {
      await OutboxService.instance
          .enqueue('strokeDelete', {'id': remoteIdForDelete});
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final base = _redoStack.removeLast();
    final stroke = DrawStroke(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter',
      userId: _myUid,
      colorValue: base.colorValue,
      strokeWidth: base.strokeWidth,
      points: List<DrawPoint>.unmodifiable(base.points),
      isEraser: base.isEraser,
      isFilledShape: base.isFilledShape,
      shapeType: base.shapeType,
      orderIndex: _orderCounter,
      layer: _activeLayer,
      imageUrl: base.imageUrl,
      imageX: base.imageX,
      imageY: base.imageY,
      imageWidth: base.imageWidth,
      imageHeight: base.imageHeight,
      imageRotation: base.imageRotation,
    );
    _orderCounter++;
    _submitStroke(stroke);
  }


  /// Удаляет штрих по id — из очереди, из локального списка и с сервера.
  ///
  /// Отдельно от [_deleteSelectedImage]: тот работает только с выбранной
  /// картинкой, а слой уносит с собой всё, что на нём лежит.
  void _removeStrokeById(String id) {
    if (_pendingLocalStrokes.containsKey(id)) {
      _pendingLocalStrokes.remove(id);
      _cancelledPendingStrokeIds.add(id);
      _myStrokeIds.remove(id);
      return;
    }

    _myStrokeIds.remove(id);
    _remoteStrokes = _remoteStrokes.where((s) => s.id != id).toList();

    if (!_hasSharedCanvas) {
      _saveSoloStrokes();
      return;
    }
    unawaited(() async {
      var done = false;
      try {
        done = await _canvas.deleteStroke(id);
      } catch (e) {
        debugPrint('[Draw] не удалось удалить штрих $id: $e');
      }
      // Не дошло до сервера — доведёт очередь. Иначе штрих остаётся в базе и
      // всплывает при следующей загрузке холста.
      if (!done) {
        await OutboxService.instance.enqueue('strokeDelete', {'id': id});
      }
    }());
  }

  /// Запоминает выбранный фон.
  ///
  /// Пока локально: в мете общего холста есть только цвет, поворот и версия
  /// очистки, поля под текстуру нет. Значит у партнёра свой фон — на сам
  /// рисунок это не влияет, штрихи одинаковые у обоих.
  Future<void> _persistBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'canvas_bg_$_canvasId',
        backgroundToStorage(_background),
      );
    } catch (e) {
      debugPrint('[Draw] не удалось сохранить фон: $e');
    }
  }

  /// Возвращает фон, выбранный для этого холста в прошлый раз.
  Future<void> _restoreBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('canvas_bg_$_canvasId');
      if (raw == null || !mounted) return;
      final restored = backgroundFromStorage(raw);
      if (restored == _background) return;
      setState(() => _background = restored);
      _repaintNotifier.value++;
    } catch (e) {
      debugPrint('[Draw] не удалось прочитать фон: $e');
    }
  }

  Future<void> _deleteSelectedImage() async {
    if (_selectedImageId == null) return;
    final id = _selectedImageId!;

    // Pending stroke (Firebase not yet confirmed)
    if (_pendingLocalStrokes.containsKey(id)) {
      _pendingLocalStrokes.remove(id);
      _cancelledPendingStrokeIds.add(id);
      _myStrokeIds.remove(id);
      setState(() {
        _selectedImageId = null;
        _visibleStrokes = _composeVisibleStrokes();
      });
      return;
    }

    final removed = _visibleStrokes.where((s) => s.id == id).firstOrNull;
    if (removed == null) {
      setState(() => _selectedImageId = null);
      return;
    }

    _myStrokeIds.remove(id);

    if (!_hasSharedCanvas) {
      setState(() {
        _selectedImageId = null;
        _visibleStrokes = _visibleStrokes.where((s) => s.id != id).toList();
      });
      _saveSoloStrokes();
      return;
    }

    _remoteStrokes = _remoteStrokes.where((s) => s.id != id).toList();
    setState(() {
      _selectedImageId = null;
      _visibleStrokes = _composeVisibleStrokes();
    });

    var imageGone = false;
    try {
      imageGone = await _canvas.deleteStroke(id);
    } catch (e) {
      debugPrint('[Draw] deleteImage error: $e');
    }
    if (!imageGone) {
      await OutboxService.instance.enqueue('strokeDelete', {'id': id});
    }
  }

  //  Fill / Clear

  /// Заливка области по тапу.
  ///
  /// Раньше умела лишь перекрасить целую фигуру или весь фон — залить кусок
  /// между линиями было нечем. Теперь холст растеризуется, от точки тапа
  /// расходится обход по соседним пикселям похожего цвета, а получившееся
  /// пятно ложится поверх рисунка отдельным штрихом.
  ///
  /// Работает одинаково и в обычном рисовании, и в пиксельном: после
  /// растеризации это просто картинка.
  Future<void> _applyFill(Offset localPoint) async {
    _cancelCurrentGesture();
    if (_canvasSize.isEmpty) return;

    final boundary = _canvasKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;

    try {
      // Снимаем один к одному: увеличивать разрешение незачем — заливка и так
      // самая тяжёлая операция на холсте.
      final snapshot = await boundary.toImage(pixelRatio: 1.0);

      // Точка тапа в координатах снимка: тап приходит в координатах холста,
      // а снимок сделан в его же пикселях.
      final canvasPoint = _screenToCanvas(localPoint);
      final sx = (canvasPoint.dx / _canvasSize.width * snapshot.width).round();
      final sy = (canvasPoint.dy / _canvasSize.height * snapshot.height).round();

      final filled = await FloodFill.fill(
        source: snapshot,
        startX: sx,
        startY: sy,
        fillColor: _activeColor.toARGB32(),
      );
      final full = Size(snapshot.width.toDouble(), snapshot.height.toDouble());
      snapshot.dispose();

      if (filled == null) return;

      // Обрезаем прозрачные поля: слой во весь холст весил как целый рисунок и
      // ложился в хранилище отдельным файлом на каждую заливку.
      final bounds = await FloodFill.opaqueBounds(filled);
      final cropped = bounds == null ? filled : await _cropImage(filled, bounds);
      if (!identical(cropped, filled)) filled.dispose();

      final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (png == null || !mounted) return;

      // Куда лечь обрезанному пятну: те же доли холста, что занимала область.
      final rect = bounds ?? Rect.fromLTWH(0, 0, full.width, full.height);
      final fx = (rect.left + rect.width / 2) / full.width;
      final fy = (rect.top + rect.height / 2) / full.height;
      final fw = rect.width / full.width;
      final fh = rect.height / full.height;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/fill_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(png.buffer.asUint8List());

      final id = 'fill_${DateTime.now().millisecondsSinceEpoch}_$_orderCounter';
      final stroke = DrawStroke(
        id: id,
        userId: _myUid,
        colorValue: _activeColor.toARGB32(),
        strokeWidth: 0,
        points: const [],
        orderIndex: _orderCounter,
        layer: _activeLayer,
        imageUrl: 'file://${file.path}',
        imageX: fx,
        imageY: fy,
        imageWidth: fw,
        imageHeight: fh,
        imageRotation: 0.0,
      );
      _orderCounter++;

      if (!_hasSharedCanvas) {
        _submitStroke(stroke);
        return;
      }

      // Общий холст: показываем себе сразу, а на сервер уходит уже загруженный
      // файл — локальный путь партнёр не откроет. Дальше тем же путём, что и
      // вставленные из галереи картинки.
      setState(() {
        _pendingLocalStrokes[id] = stroke;
        _visibleStrokes = _composeVisibleStrokes();
      });
      _myStrokeIds.add(id);
      unawaited(_uploadImageAsync(id, file.path));
    } catch (e) {
      debugPrint('заливка не удалась: $e');
    }
  }



  Future<void> _confirmClear() async {
    final s = LocaleService.current;
    final confirmed = await AppDialog.confirm(
      context,
      title: s.clearCanvas,
      message: s.clearCanvasConfirm,
      confirmLabel: s.clearCanvas,
      destructive: true,
      icon: Icons.cleaning_services_rounded,
    );

    if (!confirmed || !mounted) return;

    final prevVisible = List<DrawStroke>.from(_visibleStrokes);
    final prevRemote = List<DrawStroke>.from(_remoteStrokes);
    final prevPending = Map<String, DrawStroke>.from(_pendingLocalStrokes);
    final prevBg = _bgColor;

    _myStrokeIds.clear();
    _redoStack.clear();
    _pendingLocalStrokes.clear();
    _remoteStrokes = [];
    setState(() {
      _visibleStrokes = [];
      _bgColor = Colors.white;
    });

    if (!_hasSharedCanvas) {
      _saveSoloStrokes();
      return;
    }

    try {
      // clearCanvas разом чистит штрихи + live-курсоры и пишет clear_version +
      // bg в canvas_meta (паритет с прежними двумя вызовами).
      await _canvas.clear(
        _groupId,
        _canvasId,
        clearVersion: DateTime.now().millisecondsSinceEpoch,
        bgColor: Colors.white.toARGB32(),
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
    // iPad-поповер: origin считаем до async-gap, пока context жив.
    final shareOrigin = shareOriginFromContext(context);
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
        await Share.shareXFiles(
          [XFile(file.path)],
          text: ' ${s.drawTogether}',
          sharePositionOrigin: shareOrigin,
        );
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
      backgroundColor: widget.theme.cardSurface,
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
                      color: widget.theme.divider,
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
                    Icon(Icons.brush, size: 16, color: widget.theme.textMuted),
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
                    Icon(Icons.brush, size: 28, color: widget.theme.textMuted),
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
                              : widget.theme.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? _activeColor : widget.theme.divider,
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

  /// Лист палитры: готовые цвета, недавние и вход в полный пикер.
  void _showColorPicker() {
    final s = LocaleService.current;
    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: s.colorLabel,
          action: IconButton(
            tooltip: s.customColor,
            onPressed: () async {
              Navigator.pop(ctx);
              await _openFullColorPicker();
            },
            icon: const Icon(Icons.tune_rounded, size: 22),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 10,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _kPalette.length,
                  itemBuilder: (_, i) => _paletteDot(
                    _kPalette[i],
                    onTap: () {
                      _applyPickedColor(_kPalette[i]);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                if (_recentColors.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    s.recentColors,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: widget.theme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recentColors.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => SizedBox(
                        width: 36,
                        child: _paletteDot(
                          _recentColors[i],
                          onTap: () {
                            _applyPickedColor(_recentColors[i]);
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _openFullColorPicker();
                        },
                        icon: const Icon(Icons.palette_rounded, size: 20),
                        label: Text(s.customColor),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: s.eyedropper,
                      onPressed: () {
                        Navigator.pop(ctx);
                        _armEyedropper();
                      },
                      icon: const Icon(Icons.colorize_rounded, size: 22),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(52, 52),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paletteDot(Color c, {required VoidCallback onTap}) {
    final sel = c.toARGB32() == _activeColor.toARGB32();
    return GestureDetector(
      onTap: onTap,
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
        ),
        child: sel
            ? Icon(
                Icons.check_rounded,
                color: c == Colors.white ? Colors.black : Colors.white,
                size: 16,
              )
            : null,
      ),
    );
  }

  /// Вырезает из слоя только закрашенную часть.
  Future<ui.Image> _cropImage(ui.Image src, Rect rect) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      rect,
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      Paint(),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      rect.width.round().clamp(1, 4096),
      rect.height.round().clamp(1, 4096),
    );
    picture.dispose();
    return image;
  }

  // ── Раскраска вдвоём ─────────────────────────────────────────────────────

  /// Подгружает контур в память: он рисуется поверх мазков каждым кадром,
  /// поэтому держим уже декодированную картинку, а не путь к ассету.
  Future<void> _loadColoringOutline() async {
    final picture = _coloring;
    if (picture == null) return;
    try {
      // Своя раскраска лежит файлом в папке приложения, встроенная — в
      // ассетах. Дальше разницы нет: контур точно так же рисуется поверх
      // мазков, а половины делит вертикальная линия по центру.
      final Uint8List raw;
      if (picture.isOwn) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/coloring/${picture.id}.png');
        if (!file.existsSync()) {
          debugPrint('раскраска: своего контура нет на диске');
          return;
        }
        raw = await file.readAsBytes();
      } else {
        final data = await rootBundle.load(picture.outlineAsset);
        raw = data.buffer.asUint8List();
      }
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _coloringOutline = frame.image);
    } catch (e) {
      debugPrint('раскраска: контур не загрузился: $e');
    }
  }

  /// Заводит раскраску на этом холсте (или подхватывает уже заведённую).
  Future<void> _startColoring(String pictureId, ColoringMode mode) async {
    setState(() {
      _coloringId = pictureId;
      _coloringMode = mode;
      _coloringDone = const {};
    });
    await _loadColoringOutline();
    if (_hasSharedCanvas) {
      await CanvasRepository().setColoring(
        _groupId,
        _canvasId,
        pictureId: pictureId,
        mode: mode.storage,
      );
    }
  }

  /// Переключает мою отметку «Готово».
  Future<void> _toggleColoringDone() async {
    final next = Map<String, bool>.from(_coloringDone);
    next[_myUid] = !(next[_myUid] ?? false);
    setState(() => _coloringDone = next);
    HapticFeedback.mediumImpact();
    if (_hasSharedCanvas) {
      await CanvasRepository().setColoringDone(_groupId, _canvasId, next);
    }
  }

  /// Моя ли это половина холста (в долях 0..1 по ширине).
  bool _inMySide(Offset canvasPoint) {
    if (!_isColoring || _canvasSize.isEmpty) return true;
    // Пока партнёра нет, лист делить не на кого: весь холст мой. Без этого
    // касания по правой половине молча пропадали — «кисти не работают».
    if (!coloringSplitApplies(widget.pairData.partnerUid)) return true;
    final half = _canvasSize.width / 2;
    return _mySide == ColoringSide.left
        ? canvasPoint.dx <= half
        : canvasPoint.dx >= half;
  }

  /// Снимает холст целиком и открывает итог. Контур уже внутри снимка —
  /// склеивать половины отдельно не нужно.
  Future<void> _openColoringResult() async {
    final picture = _coloring;
    if (picture == null) return;
    final boundary = _canvasKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: 2.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ColoringResultScreen(
            png: png.buffer.asUint8List(),
            picture: picture,
            theme: widget.theme,
            onToMemories: _hasSharedCanvas ? _coloringToMemories : null,
          ),
        ),
      );
    } catch (e) {
      debugPrint('раскраска: снимок итога не удался: $e');
    }
  }

  /// Кладёт готовую раскраску в ленту воспоминаний: сначала файл на сервер,
  /// потом запись — тем же путём, что и обычное фото.
  Future<void> _coloringToMemories(File file) async {
    final destination =
        'memories/$_groupId/coloring_${DateTime.now().millisecondsSinceEpoch}.png';
    final url = await MediaService().uploadFile(file.path, destination);
    if (url == null) throw Exception('upload failed');
    await MemoryRepository().add(
      groupId: _groupId,
      authorName: widget.userData.displayName,
      authorAvatar: widget.userData.avatarUrl,
      type: MemoryType.photo,
      imageUrl: url,
      title: _coloring?.title,
      caption: LocaleService.current.coloringTitle,
    );
  }

  /// Прижимает точку к своей половине: мазок можно вести к центру, но за
  /// линию он не перельётся.
  Offset _clampToMySide(Offset localPoint) {
    if (_canvasSize.isEmpty) return localPoint;
    // Без партнёра половин нет — мазок никуда не прижимаем.
    if (!coloringSplitApplies(widget.pairData.partnerUid)) return localPoint;
    final canvasPoint = _screenToCanvas(localPoint);
    // Границы считает `coloringClampX` под тестами: прежний расчёт на месте
    // переворачивал диапазон при толстой кисти на узком листе, и `clamp`
    // ронял приложение прямо посреди мазка («часто вылетает в раскрасках»).
    final clampedX = coloringClampX(
      canvasPoint.dx,
      width: _canvasSize.width,
      strokeWidth: _strokeWidth,
      left: _mySide == ColoringSide.left,
    );
    if ((clampedX - canvasPoint.dx).abs() < 0.01) return localPoint;
    // Обратно в экранные координаты — тем же преобразованием, что и вперёд.
    final delta = clampedX - canvasPoint.dx;
    return Offset(localPoint.dx + delta * _scale, localPoint.dy);
  }

  DateTime _lastHalfHint = DateTime.fromMillisecondsSinceEpoch(0);

  /// Подсказка, почему касание не сработало. Не чаще раза в три секунды —
  /// иначе она сыплется на каждый тап.
  void _showHalfHint() {
    final now = DateTime.now();
    if (now.difference(_lastHalfHint).inSeconds < 3) return;
    _lastHalfHint = now;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleService.current.coloringOtherHalf),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Пипетка ──────────────────────────────────────────────────────────────

  /// Включает режим взятия цвета: снимает холст один раз, дальше цвет читается
  /// из снимка. Лист при этом уже закрыт — цвет берут с самого рисунка.
  Future<void> _armEyedropper() async {
    final boundary = _canvasKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final snapshot = await boundary.toImage(pixelRatio: 1.0);
      final bytes =
          await snapshot.toByteData(format: ui.ImageByteFormat.rawRgba);
      _eyedropperWidth = snapshot.width;
      _eyedropperHeight = snapshot.height;
      snapshot.dispose();
      if (bytes == null || !mounted) return;
      setState(() {
        _eyedropperPixels = bytes;
        _eyedropperArmed = true;
        _eyedropperPoint = null;
        _eyedropperColor = null;
      });
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('пипетка: снимок холста не удался: $e');
    }
  }

  void _disarmEyedropper() {
    if (!_eyedropperArmed) return;
    setState(() {
      _eyedropperArmed = false;
      _eyedropperPixels = null;
      _eyedropperPoint = null;
      _eyedropperColor = null;
    });
  }

  /// Цвет пикселя под точкой касания. null — палец вне холста.
  Color? _colorAt(Offset localPoint) {
    final pixels = _eyedropperPixels;
    if (pixels == null || _canvasSize.isEmpty) return null;

    final canvasPoint = _screenToCanvas(localPoint);
    final x =
        (canvasPoint.dx / _canvasSize.width * _eyedropperWidth).round();
    final y =
        (canvasPoint.dy / _canvasSize.height * _eyedropperHeight).round();
    if (x < 0 || y < 0 || x >= _eyedropperWidth || y >= _eyedropperHeight) {
      return null;
    }

    final offset = (y * _eyedropperWidth + x) * 4;
    if (offset + 3 >= pixels.lengthInBytes) return null;
    final r = pixels.getUint8(offset);
    final g = pixels.getUint8(offset + 1);
    final b = pixels.getUint8(offset + 2);
    final a = pixels.getUint8(offset + 3);
    // Прозрачное место листа — это его фон, а не «никакой цвет».
    if (a == 0) return _bgColor;
    return Color.fromARGB(255, r, g, b);
  }

  void _trackEyedropper(Offset localPoint) {
    final color = _colorAt(localPoint);
    setState(() {
      _eyedropperPoint = localPoint;
      if (color != null) _eyedropperColor = color;
    });
  }

  void _finishEyedropper() {
    final color = _eyedropperColor;
    _disarmEyedropper();
    if (color == null) return;
    HapticFeedback.mediumImpact();
    _applyPickedColor(color);
  }

  /// Полный пикер: квадрат «насыщенность × яркость», оттенок, HEX, пипетка.
  Future<void> _openFullColorPicker() async {
    final picked = await showColorPickerSheet(
      context: context,
      initial: _activeColor,
      onEyedropper: _armEyedropper,
    );
    if (picked != null) _applyPickedColor(picked);
  }

  /// Ставит цвет активным и запоминает в недавних.
  void _applyPickedColor(Color color) {
    setState(() {
      _activeColor = color;
      _currentColorValue = color.toARGB32();
      // Пипеткой берут цвет, чтобы им же рисовать: возвращаем кисть, иначе
      // следующий мазок уйдёт стёркой или заливкой.
      if (_activeTool == DrawTool.eraser) _activeTool = DrawTool.brush;
    });
    unawaited(RecentColors.remember(color).then((_) => _reloadRecentColors()));
  }

  Future<void> _reloadRecentColors() async {
    final list = await RecentColors.load();
    if (mounted) setState(() => _recentColors = list);
  }

  //  BUILD

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _captureThumbnailAndExit();
      },
      child: Scaffold(
        backgroundColor: t.surfaceMuted,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(s, t),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildCanvasArea()),
                    // Floating partner badges - top right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _buildPartnerBadges(),
                    ),
                    // Scale / rotation indicator - top left
                    if (_scale != 1.0 || _canvasRotation != 0.0)
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
              // Раскраска: полоса готовности над панелью инструментов.
              if (_isColoring) _buildColoringBar(s, t),
              _buildBottomToolbar(s, t),
            ],
          ),
        ),
      ),
    );
  }

  /// Меняет половины местами у обоих сразу.
  Future<void> _swapColoringSides() async {
    final next = !_coloringSwap;
    setState(() => _coloringSwap = next);
    if (_groupId.isEmpty) return;
    try {
      await _canvas.setColoringSwap(_groupId, _canvasId, swapped: next);
    } catch (e) {
      debugPrint('Раскраска: обмен половин не сохранился — $e');
    }
  }

  /// Полоса раскраски: чья половина, отметка «Готово» и вход в итог.
  Widget _buildColoringBar(AppStrings s, AppTheme t) {
    final bothDone = _iAmDone && (_partnerIsDone || _groupId.isEmpty);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (bothDone ? t.primary : t.surfaceMuted),
              shape: BoxShape.circle,
            ),
            child: Icon(
              bothDone ? Icons.celebration_rounded : Icons.palette_rounded,
              size: 19,
              color: bothDone ? Colors.white : t.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _coloring?.title ?? s.coloringTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  _iAmDone
                      ? (bothDone
                          ? s.coloringRevealTitle
                          : s.coloringWaitingHint(
                              widget.pairData.partnerDisplayName))
                      : s.coloringMyHalf,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Поменяться половинками: пока никто не закончил, это безобидно —
          // мазки остаются на своих местах, меняется лишь то, кому какая
          // сторона принадлежит.
          if (!bothDone && !_iAmDone && _groupId.isNotEmpty)
            IconButton(
              tooltip: s.coloringSwapSides,
              onPressed: _swapColoringSides,
              icon: const Icon(Icons.swap_horiz_rounded, size: 22),
              color: t.textSecondary,
            ),
          if (bothDone)
            FilledButton(
              onPressed: _openColoringResult,
              style: FilledButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Text(s.coloringRevealTitle),
            )
          else
            FilledButton.icon(
              onPressed: _toggleColoringDone,
              icon: Icon(
                _iAmDone ? Icons.edit_rounded : Icons.check_rounded,
                size: 18,
              ),
              label: Text(_iAmDone ? s.coloringNotDoneBtn : s.coloringDoneBtn),
              style: FilledButton.styleFrom(
                backgroundColor: _iAmDone ? t.surfaceMuted : t.primary,
                foregroundColor: _iAmDone ? t.textSecondary : Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
        ],
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

    // Панель без фона и тени: плавающие пилюли поверх «стола» — так лист
    // получает всю высоту, а живое присутствие партнёра видно сразу.
    final live = drawingPartners.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          _pillIcon(Icons.arrow_back_rounded, _captureThumbnailAndExit),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: live ? t.primaryLight : t.cardSurface,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  if (live) ...[
                    const _PulsingDot(),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Text(
                      live
                          ? s.partnerIsDrawing(drawingPartners.join(', '))
                          : (widget.canvasName ?? s.drawTogether),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Тумблер сетки — только на пиксельном холсте и всегда на виду:
          // в нижнем ряду он уезжал за край.
          if (_isPixel) ...[
            _pillIcon(
              _showPixelGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
              _togglePixelGrid,
              tooltip: _showPixelGrid ? s.pixelGridHide : s.pixelGridShow,
              active: _showPixelGrid,
            ),
            const SizedBox(width: 8),
          ],
          _pillIcon(Icons.undo_rounded, _canUndo ? _undo : null,
              tooltip: s.undoAction),
          const SizedBox(width: 8),
          _saving
              ? SizedBox(
                  width: 42,
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: t.primary,
                    ),
                  ),
                )
              : _pillIcon(Icons.ios_share_rounded, () => _saveOrShare(share: true),
                  tooltip: s.shareDrawing),
        ],
      ),
    );
  }

  /// Круглая кнопка-пилюля верхней панели.
  Widget _pillIcon(
    IconData icon,
    VoidCallback? onTap, {
    String? tooltip,
    bool active = false,
  }) {
    final t = widget.theme;
    final btn = Material(
      color: active ? t.primary : t.cardSurface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 20,
            color: active
                ? _onPrimaryColor(t)
                : (onTap == null ? t.textMuted : t.textPrimary),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  //  Canvas area

  Widget _buildCanvasArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest;
        // Лист держит формат 4:5 и одинаков у обоих в паре. Раньше холст
        // растягивался по экрану: точки хранятся в долях 0..1, поэтому у
        // партнёра с другой формой экрана рисунок съезжал, а выгруженный PNG
        // каждый раз получался своего размера.
        final ratio = _sheetRatio;
        final double sheetW;
        final double sheetH;
        final double sheetLeft;
        final double sheetTop;
        if (ratio == null) {
          // Холст, созданный до появления листа: прежняя геометрия во всю
          // область — иначе сохранённые штрихи сплющит.
          sheetW = (available.width - _kCanvasPad * 2).clamp(1.0, double.infinity);
          sheetH =
              (available.height - _kCanvasPad * 2).clamp(1.0, double.infinity);
          sheetLeft = _kCanvasPad;
          sheetTop = _kCanvasPad;
        } else {
          final maxW =
              (available.width - _kCanvasPad * 2).clamp(1.0, double.infinity);
          final maxH = (available.height - _kCanvasPad * 2 - _kSheetCaption)
              .clamp(1.0, double.infinity);
          double w = maxW;
          double h = w / ratio;
          if (h > maxH) {
            h = maxH;
            w = h * ratio;
          }
          sheetW = w;
          sheetH = h;
          sheetLeft = (available.width - w) / 2;
          sheetTop = ((available.height - _kSheetCaption) - h) / 2;
        }
        final nextSize = Size(sheetW, sheetH);
        // ��������� ������ ������ �������� �� ����� build-����.
        // addPostFrameCallback ����� ������ � �������� ������ �����������.
        if (!nextSize.isEmpty && nextSize != _canvasSize) {
          _canvasSize = nextSize;
        }

        return Stack(
          children: [
            // «Стол», на котором лежит лист. Сетка теперь живёт внутри листа —
            // это фон самого рисунка, он и уходит в экспорт.
            Positioned.fill(
              child: ColoredBox(color: widget.theme.bgGradient.first),
            ),
            // Лист: скруглённый, по центру «стола»
            Positioned(
              left: sheetLeft,
              top: sheetTop,
              width: sheetW,
              height: sheetH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_kSheetRadius),
                child: SizedBox.expand(
                  // Вид холста слушает свой сигнал: жест перестраивает только
                  // это поддерево, а не весь экран с панелями и палитрой.
                  child: ValueListenableBuilder<int>(
                    valueListenable: _viewTick,
                    builder: (context, _, canvasChild) => Transform(
                    transform: Matrix4.identity()
                      ..setTranslationRaw(
                        _canvasOffset.dx,
                        _canvasOffset.dy,
                        0.0,
                      )
                      ..scale(_scale, _scale, 1.0)
                      ..rotateZ(_canvasRotation),
                    // Вуаль едет вместе с холстом: при зуме и повороте она
                    // должна закрывать ту же половину, иначе чужой рисунок
                    // подсматривается простым щипком.
                    child: Stack(
                      children: [
                    RepaintBoundary(
                      key: _canvasKey,
                      child: _CanvasScene(
                        bgColor: _bgColor,
                        background: _background,
                        gridColor: _isPixel ? null : _sheetGridColor,
                        pixelCols: _isPixel ? _pxCols : null,
                        pixelRows: _isPixel ? _pxRows : null,
                        showPixelGrid: _showPixelGrid,
                        strokes: _visibleStrokes,
                        currentPoints: _currentPoints,
                        currentColorValue: _currentColorValue,
                        currentStrokeWidth: _currentStrokeWidth,
                        currentIsEraser: _currentIsEraser,
                        currentIsFilledShape: _currentIsFilledShape,
                        currentShapeType: _currentShapeType,
                        partnerNotifier: _partnerNotifier,
                        canvasSize: _canvasSize,
                        repaintNotifier: _repaintNotifier,
                        coloringOutline: _coloringOutline,
                        localImagePaths: _localImagePaths,
                        selectedImageId: _selectedImageId,
                      ),
                    ),
                    if (_isColoring && !_coloringRevealed)
                      // Доли, а не пиксели: _canvasSize обновляется в разметке
                      // и на первом кадре отстаёт — штриховка вылезала за лист
                      // и заходила на свою половину.
                      Positioned.fill(
                        child: Align(
                          alignment: _mySide == ColoringSide.left
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 0.5,
                            heightFactor: 1,
                            child: _coloringVeil(),
                          ),
                        ),
                      ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
            ),
            // Слой ввода лежит ровно на листе: координаты штрихов считаются
            // от него, поэтому рамки должны совпадать до пикселя.
            Positioned(
              left: sheetLeft,
              top: sheetTop,
              width: sheetW,
              height: sheetH,
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
            // Формат листа — только там, где лист есть
            if (_hasSheet) Positioned(
              left: 0,
              right: 0,
              top: sheetTop + sheetH + 6,
              child: Center(
                child: Text(
                  _sheetCaption(sheetW, sheetH),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: widget.theme.textMuted,
                  ),
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
            // Пипетка: лупа под пальцем и подсказка, пока цвет не взят.
            if (_eyedropperArmed) ..._eyedropperOverlay(),
          ],
        );
      },
    );
  }

  /// Штриховка поверх половины партнёра: видно, что там чужая территория, но
  /// не видно, что именно там нарисовано.
  Widget _coloringVeil() {
    final t = widget.theme;
    final waiting = _iAmDone && !_partnerIsDone;
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: t.surfaceMuted.withValues(alpha: 0.97),
          border: Border(
            left: BorderSide(
              color: t.textPrimary,
              width: _mySide == ColoringSide.left ? 1.5 : 0,
            ),
            right: BorderSide(
              color: t.textPrimary,
              width: _mySide == ColoringSide.right ? 1.5 : 0,
            ),
          ),
        ),
        child: CustomPaint(
          painter: _HatchPainter(t.primary.withValues(alpha: 0.10)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.cardSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    waiting ? Icons.schedule_rounded : Icons.lock_rounded,
                    size: 22,
                    color: t.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    waiting
                        ? LocaleService.current.coloringPartnerColoring(
                            widget.pairData.partnerDisplayName)
                        : LocaleService.current.coloringPartnerHalfHidden,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Лупа под пальцем и подсказка внизу. Лупа поднята над точкой касания —
  /// иначе её закрывает сам палец, и выбирать приходится вслепую.
  List<Widget> _eyedropperOverlay() {
    final s = LocaleService.current;
    final t = widget.theme;
    final point = _eyedropperPoint;
    return [
      if (point != null)
        Positioned(
          left: point.dx - 48,
          top: point.dy - 116,
          child: IgnorePointer(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _eyedropperColor ?? t.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 96,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.colorize_rounded,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _eyedropperColor == null
                        ? s.eyedropperHint
                        : ColorHex.format(_eyedropperColor!),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Подпись под листом: у пиксельного холста — сетка и сторона пикселя,
  /// у обычного — формат и размер будущего PNG.
  String _sheetCaption(double w, double h) {
    if (_isPixel) {
      final px = (1600 / _pxCols).round();
      return '$_pxCols × $_pxRows · клетка $px px';
    }
    const exportW = 1600;
    final ratio = _sheetRatio ?? (w / h);
    final exportH = (exportW / ratio).round();
    // Подпись раньше врала: соотношение было прибито к 4:5, а лист мог быть
    // и квадратным (раскраска), и во всю область (старые холсты).
    final label = (ratio - _kSheetRatio).abs() < 0.01
        ? '4 : 5'
        : (ratio - 1).abs() < 0.01
            ? '1 : 1'
            : ratio.toStringAsFixed(2);
    return '$label · $exportW×$exportH';
  }

  Widget _buildPartnerCursor(DrawStroke stroke) {
    final last = stroke.points.last;
    final sx =
        last.x * _canvasSize.width * _scale + _canvasOffset.dx + _kCanvasPad;
    final sy =
        last.y * _canvasSize.height * _scale + _canvasOffset.dy + _kCanvasPad;
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
                  ),
                  child: Text(
                    name.truncateGraphemes(8),
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
    return ValueListenableBuilder<int>(
      valueListenable: _viewTick,
      builder: (context, _, __) => _scaleIndicatorBody(),
    );
  }

  Widget _scaleIndicatorBody() {
    final pct = (_scale * 100).round();
    final deg = (_canvasRotation * 180 / math.pi).round();
    final label = deg != 0 ? '$pct%  ${deg > 0 ? '+' : ''}$deg°' : '$pct%';
    return GestureDetector(
      onTap: _resetZoom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
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
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDrawing) ...[const _PulsingDot(), const SizedBox(width: 4)],
              Text(
                p.name.firstGraphemeUpper('?'),
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
      decoration: BoxDecoration(
        color: t.cardSurface,
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

  /// Ряд дополнительных инструментов.
  ///
  /// Прокручивается по горизонтали: на узком экране (или с крупным системным
  /// шрифтом) фигуры, заливка, слои и фон не влезают в ряд, и кнопки за правым
  /// краем становились недоступны совсем. Удаление вынесено из прокрутки и
  /// прижато к правому краю — до него всегда один тап, и оно не уезжает под
  /// палец во время прокрутки.
  Widget _buildExpandedTools(AppStrings s, AppTheme t) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: t.surfaceMuted,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
            Icons.change_history_rounded,
            DrawTool.triangle,
            s.drawTriangle,
            t,
            compact: true,
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 24, color: t.divider),
          const SizedBox(width: 4),
          _actionBtn(
            _fillShapes
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            () => setState(() => _fillShapes = !_fillShapes),
            tooltip: s.fillShapes,
            color: _fillShapes ? t.primary : t.textMuted,
          ),
          _toolBtn(
            Icons.format_color_fill_rounded,
            DrawTool.fill,
            s.fillBg,
            t,
            compact: true,
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 24, color: t.divider),
          const SizedBox(width: 4),
          _actionBtn(
            Icons.layers_rounded,
            _openLayersSheet,
            tooltip: s.drawLayers,
            color: _layerCount > 1 ? t.primary : t.textMuted,
          ),
          _actionBtn(
            Icons.texture_rounded,
            _openBackgroundSheet,
            tooltip: s.drawBackgrounds,
            color: _background != CanvasBackground.plain
                ? t.primary
                : t.textMuted,
          ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 24, color: t.divider),
          const SizedBox(width: 4),
          _actionBtn(
            Icons.delete_outline_rounded,
            _selectedImageId != null ? _deleteSelectedImage : _confirmClear,
            tooltip: _selectedImageId != null ? s.deletePhoto : s.clearCanvas,
            color: Colors.red.shade400,
          ),
        ],
      ),
    );
  }


  // ── Слои и фон ──────────────────────────────────────────────────────────

  /// Панель слоёв: выбрать активный, спрятать, добавить, удалить.
  void _openLayersSheet() {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;

    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: s.drawLayers,
          action: IconButton(
            tooltip: s.drawLayerAdd,
            onPressed: () {
              setState(() {
                _layerCount++;
                _activeLayer = _layerCount - 1;
              });
              setSheet(() {});
            },
            icon: const Icon(Icons.add_rounded),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            // Сверху — верхний слой: так же, как он лежит на холсте.
            itemCount: _layerCount,
            itemBuilder: (_, i) {
              final index = _layerCount - 1 - i;
              final hidden = _hiddenLayers.contains(index);
              final active = index == _activeLayer;
              final count =
                  _visibleStrokes.where((st) => st.layer == index).length;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: active
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onTap: () {
                    setState(() => _activeLayer = index);
                    setSheet(() {});
                  },
                  leading: Icon(
                    active ? Icons.edit_rounded : Icons.layers_rounded,
                    color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    s.drawLayerName(index + 1),
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color:
                          active ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    s.drawLayerStrokes(count),
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 12,
                      color: active
                          ? cs.onPrimaryContainer.withValues(alpha: 0.8)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: hidden ? s.drawLayerShow : s.drawLayerHide,
                        onPressed: () {
                          setState(() {
                            if (hidden) {
                              _hiddenLayers.remove(index);
                            } else {
                              _hiddenLayers.add(index);
                            }
                            _visibleStrokes = _composeVisibleStrokes();
                          });
                          _repaintNotifier.value++;
                          setSheet(() {});
                        },
                        icon: Icon(
                          hidden
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: active
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      // Нижний слой не удаляем: холст без слоёв не бывает.
                      if (_layerCount > 1)
                        IconButton(
                          tooltip: s.drawLayerDelete,
                          onPressed: () => _deleteLayer(index, setSheet),
                          icon: Icon(Icons.delete_outline_rounded,
                              color: cs.error),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Удаляет слой вместе со всем, что на нём нарисовано.
  Future<void> _deleteLayer(int index, StateSetter refreshSheet) async {
    final s = LocaleService.current;
    final ok = await AppDialog.confirm(
      context,
      title: s.drawLayerDelete,
      message: s.drawLayerDeleteConfirm,
      confirmLabel: s.delete,
      destructive: true,
      icon: Icons.layers_clear_rounded,
    );
    if (!ok || !mounted) return;

    final doomed =
        _visibleStrokes.where((st) => st.layer == index).map((st) => st.id);
    for (final id in doomed) {
      _removeStrokeById(id);
    }

    setState(() {
      _layerCount = (_layerCount - 1).clamp(1, 99);
      _activeLayer = _activeLayer.clamp(0, _layerCount - 1);
      _hiddenLayers.remove(index);
      _visibleStrokes = _composeVisibleStrokes();
    });
    _repaintNotifier.value++;
    refreshSheet(() {});
  }

  /// Выбор фона листа.
  void _openBackgroundSheet() {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;

    showAppSheet<void>(
      context,
      expand: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: s.drawBackgrounds,
          child: GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            childAspectRatio: 0.78,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (final bg in CanvasBackground.values)
                if (_backgroundShown(bg)) _backgroundTile(bg, cs, setSheet),
            ],
          ),
        ),
      ),
    );
  }

  /// Показывать ли фон в листе выбора.
  ///
  /// Там, где Togetherly+ не существует (iOS), платные фоны прячем совсем:
  /// поштучно они не продаются, монетами их не открыть, и замок без выхода
  /// выглядел бы поломкой. Купленное раньше остаётся на месте.
  bool _backgroundShown(CanvasBackground bg) =>
      PlusService.instance.visible ||
      PlusAccess.ownsBackground(
        id: bg,
        plus: false,
        owned: widget.userData.ownedFeatures,
      );

  Widget _backgroundTile(
    CanvasBackground bg,
    ColorScheme cs,
    StateSetter refreshSheet,
  ) {
    final spec = specOf(bg);
    final selected = _background == bg;
    final s = LocaleService.current;
    // Платные фоны набора открывает Togetherly+ (или поштучная покупка).
    final unlocked = PlusAccess.ownsBackground(
      id: bg,
      plus: PlusService.instance.active,
      owned: widget.userData.ownedFeatures,
    );

    return GestureDetector(
      onTap: () {
        if (!unlocked) {
          // Там, где Togetherly+ не существует, закрытых фонов в списке нет —
          // а если тап всё же случился, молча ничего не делаем.
          if (!PlusService.instance.visible) return;
          // Закрытый фон не выбирается молча: ведём туда, где его открывают.
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlusScreen(
                scheme: Theme.of(context).colorScheme,
              ),
              settings: const RouteSettings(name: '/plus'),
            ),
          );
          return;
        }
        setState(() => _background = bg);
        _repaintNotifier.value++;
        _persistBackground();
        refreshSheet(() {});
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Превью — тот же painter, что рисует холст: врать не может.
            CustomPaint(painter: CanvasBackgroundPainter(bg)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                color: cs.surface.withValues(alpha: 0.88),
                child: Text(
                  s.drawBackgroundName(bg.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            // Закрытый фон гасим и вешаем замок: видно, что он есть и что за
            // него надо заплатить, — вместо молчаливого «не нажимается».
            if (!unlocked)
              Positioned.fill(
                child: Container(
                  color: cs.surface.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: Icon(Icons.lock_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ),
            if (selected && unlocked)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded,
                      size: 13, color: cs.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainToolbarRow(AppStrings s, AppTheme t) {
    // Инструментов больше, чем влезает в строку, поэтому ряд прокручивается.
    // Раньше лишние кнопки просто обрезались краем экрана и до них было не
    // добраться.
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 68,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Лента цветов: своя ширина, иначе Expanded внутри прокрутки падает
            SizedBox(
              width: 210,
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
                      onTap: () => setState(() {
                        _activeColor = c;
                        _currentColorValue = c.toARGB32();
                      }),
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
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Palm (hand) tool
            _toolBtn(Icons.pan_tool_rounded, DrawTool.palm, s.palmTool, t),
            // Image tool
            _toolBtn(Icons.image_rounded, DrawTool.image, s.photo, t),
            // Add photo button
            _actionBtn(
              Icons.add_photo_alternate_rounded,
              _pickAndAddImage,
              tooltip: s.addPhoto,
            ),
            // Brush tool
            _toolBtn(Icons.brush_rounded, DrawTool.brush, s.brush, t),
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
            // Отмена и возврат — здесь же, у большого пальца
            _actionBtn(
              Icons.undo_rounded,
              _canUndo ? _undo : null,
              tooltip: s.undoAction,
            ),
            _actionBtn(
              Icons.redo_rounded,
              _canRedo ? _redo : null,
              tooltip: s.redoAction,
            ),
            // Expand/collapse more tools
            _expandBtn(t),
            const SizedBox(width: 4),
          ],
          ),
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
    final size = compact ? 40.0 : 48.0;
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
            // Круглая кнопка: выбранный инструмент залит акцентом, остальные —
            // на поверхности карточки. Рамок и полупрозрачных заливок нет.
            color: active ? t.primary : t.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: compact ? 20 : 22,
            color: active ? _onPrimaryColor(t) : t.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Контрастный цвет поверх акцента: у светлых акцентов белый текст тонет.
  Color _onPrimaryColor(AppTheme t) =>
      t.primary.computeLuminance() > 0.55 ? const Color(0xFF16161A) : Colors.white;

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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: widget.theme.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 22,
                  color: color ?? widget.theme.textMuted,
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
              : t.surfaceMuted,
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
            color: _toolbarExpanded ? t.primary : t.textMuted,
          ),
        ),
      ),
    );
  }
}

//  Grid background

/// Направляющие пиксельной сетки. Рисуются только когда клетка крупнее 6 px —
/// на мелкой сетке линии сливаются в кашу и мешают.
class _PixelGridPainter extends CustomPainter {
  final int cols;
  final int rows;

  const _PixelGridPainter({required this.cols, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / cols;
    final ch = size.height / rows;
    if (cw < 6 || ch < 6) return;
    final paint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    for (int i = 1; i < cols; i++) {
      final x = i * cw;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int j = 1; j < rows; j++) {
      final y = j * ch;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter old) =>
      old.cols != cols || old.rows != rows;
}

class _GridBackground extends StatelessWidget {
  final Color lineColor;
  const _GridBackground({required this.lineColor});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter(lineColor));
  }
}

class _GridPainter extends CustomPainter {
  final Color lineColor;
  _GridPainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
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
  bool shouldRepaint(covariant _GridPainter old) => old.lineColor != lineColor;
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

/// Косая штриховка закрытой половины.
class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6;
    const step = 22.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

/// Контур раскраски поверх мазков — растянут на весь лист.
class _ColoringOutlinePainter extends CustomPainter {
  const _ColoringOutlinePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_ColoringOutlinePainter old) => old.image != image;
}

class _CanvasScene extends StatefulWidget {
  final Color bgColor;

  /// Текстура листа: клетка, тетрадь, крафт и прочее. Рисуется под штрихами и
  /// попадает в выгрузку вместе с рисунком.
  final CanvasBackground background;
  /// Цвет клетки фона; null — фон без сетки.
  final Color? gridColor;
  /// Сетка пиксельного холста (колонки × строки); null — обычный холст.
  final int? pixelCols;
  final int? pixelRows;
  /// Показывать направляющие сетки поверх листа.
  final bool showPixelGrid;
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final bool currentIsFilledShape;
  final DrawShapeType? currentShapeType;
  final ValueNotifier<List<DrawStroke>> partnerNotifier;
  final Size canvasSize;
  final ValueNotifier<int> repaintNotifier;
  final String? selectedImageId;

  /// Контур раскраски. Рисуется ПОСЛЕДНИМ, поверх всех мазков: закрасить сам
  /// рисунок нельзя, как ни старайся — краска всегда уходит под линии.
  final ui.Image? coloringOutline;

  /// Локальные файлы своих картинок-штрихов: id → путь.
  final Map<String, String> localImagePaths;

  const _CanvasScene({
    required this.bgColor,
    required this.background,
    this.gridColor,
    this.pixelCols,
    this.pixelRows,
    this.showPixelGrid = true,
    required this.strokes,
    required this.currentPoints,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.currentIsFilledShape,
    required this.currentShapeType,
    required this.partnerNotifier,
    required this.canvasSize,
    required this.repaintNotifier,
    this.selectedImageId,
    this.coloringOutline,
    this.localImagePaths = const {},
  });

  @override
  State<_CanvasScene> createState() => _CanvasSceneState();
}

class _CanvasSceneState extends State<_CanvasScene> {
  late Listenable _repaint;

  /// Закоммиченные штрихи держим готовым слоем: без него каждое движение
  /// пальца перерисовывало весь рисунок целиком — отсюда лаги на большом
  /// холсте и при увеличении.
  final StrokeLayerCache _layer = StrokeLayerCache();

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([
      widget.repaintNotifier,
      widget.partnerNotifier,
    ]);
  }

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
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
    if (old.bgColor != widget.bgColor ||
        old.background != widget.background ||
        old.gridColor != widget.gridColor ||
        old.pixelCols != widget.pixelCols ||
        old.pixelRows != widget.pixelRows) {
      _layer.invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageStrokes = widget.strokes.where((s) => s.isImageStroke).toList();
    final drawStrokes = widget.strokes.where((s) => !s.isImageStroke).toList();

    return Container(
      color: widget.bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Фон-текстура: рисуется кодом, поэтому тянется под любой размер
          // холста и не мылится на больших экранах.
          if (widget.background != CanvasBackground.plain)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CanvasBackgroundPainter(widget.background),
                ),
              ),
            ),
          // Клетка — старый бесплатный фон листа, остаётся для рисунков,
          // сделанных до появления текстур.
          if (widget.gridColor != null &&
              widget.background == CanvasBackground.plain)
            Positioned.fill(child: _GridBackground(lineColor: widget.gridColor!)),
          // Пиксельная сетка: тонкие направляющие ровно по клеткам, чтобы было
          // видно, куда встанет следующий пиксель.
          if (widget.showPixelGrid &&
              widget.pixelCols != null &&
              widget.pixelRows != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PixelGridPainter(
                    cols: widget.pixelCols!,
                    rows: widget.pixelRows!,
                  ),
                ),
              ),
            ),
          SizedBox.expand(
            child: CustomPaint(
              painter: _DrawingPainter(
                strokes: drawStrokes,
                layer: _layer,
                pixelCols: widget.pixelCols,
                pixelRows: widget.pixelRows,
                currentPoints: widget.currentPoints,
                currentColorValue: widget.currentColorValue,
                currentStrokeWidth: widget.currentStrokeWidth,
                currentIsEraser: widget.currentIsEraser,
                currentIsFilledShape: widget.currentIsFilledShape,
                currentShapeType: widget.currentShapeType,
                partnerNotifier: widget.partnerNotifier,
                canvasSize: widget.canvasSize,
                repaint: _repaint,
              ),
            ),
          ),
          ...imageStrokes.map((s) => _buildImageWidget(s, widget.canvasSize)),
          if (widget.coloringOutline != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ColoringOutlinePainter(widget.coloringOutline!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(DrawStroke s, Size canvasSize) {
    if (canvasSize.isEmpty) return const SizedBox.shrink();
    final cx = (s.imageX ?? 0.5) * canvasSize.width;
    final cy = (s.imageY ?? 0.5) * canvasSize.height;
    final w = (s.imageWidth ?? 0.5) * canvasSize.width;
    final h = (s.imageHeight ?? 0.5) * canvasSize.height;
    final rot = s.imageRotation ?? 0.0;
    // file:// — локальный файл; остальное (pb:// protected / http / gs / sb) —
    // через StorageImage: он добавит PocketBase file-токен и разрешит схему async.
    // Свой, только что загруженный штрих показываем с диска: сетевой адрес у
    // него уже есть, но качать своё же изображение заново незачем.
    final local = widget.localImagePaths[s.id];
    final raw = (local != null && File(local).existsSync())
        ? 'file://$local'
        : (s.imageUrl ?? '');
    final isSelected = widget.selectedImageId == s.id;

    Widget img;
    if (raw.startsWith('file://')) {
      img = Image.file(
        File(raw.substring(7)),
        width: w,
        height: h,
        fit: BoxFit.cover,
        // Без этого каждая перестройка дерева гасит картинку на кадр: после
        // заливки (а она кладётся картинкой на весь холст) рисунок мигал.
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _imgPlaceholder(w, h),
      );
    } else if (raw.isNotEmpty) {
      img = StorageImage(
        imageUrl: raw,
        width: w,
        height: h,
        fit: BoxFit.cover,
        placeholder: (_, __) => _imgPlaceholder(w, h, loading: true),
        errorWidget: (_, __, ___) => _imgPlaceholder(w, h),
      );
    } else {
      return const SizedBox.shrink();
    }

    return Positioned(
      // Ключ по id штриха: без него список картинок пересобирается при каждом
      // мазке, элементы съезжают друг на друга и все заливки перезагружаются —
      // рисунок мигал на каждом штрихе.
      key: ValueKey(s.id),
      left: cx - w / 2,
      top: cy - h / 2,
      child: Transform.rotate(
        angle: rot,
        alignment: Alignment.center,
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(4), child: img),
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue.shade400, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder(double w, double h, {bool loading = false}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.broken_image_rounded, color: Colors.grey.shade400),
        ),
      );
}

//  _DrawingPainter

class _DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<DrawPoint> currentPoints;
  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final bool currentIsFilledShape;
  final DrawShapeType? currentShapeType;
  final ValueNotifier<List<DrawStroke>> partnerNotifier;
  final Size canvasSize;
  /// Сетка пиксельного холста; null — обычное рисование кривыми.
  final int? pixelCols;
  final int? pixelRows;

  /// Готовый слой закоммиченных штрихов (живёт в состоянии сцены).
  final StrokeLayerCache layer;

  _DrawingPainter({
    required this.strokes,
    required this.layer,
    this.pixelCols,
    this.pixelRows,
    required this.currentPoints,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.currentIsFilledShape,
    required this.currentShapeType,
    required this.partnerNotifier,
    required this.canvasSize,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Removed saveLayer for performance. Simplified Eraser uses bgColor ink.

    // Закоммиченные штрихи выкладываем готовым слоем: заново их рисуем только
    // когда штрихов стало больше или меньше. Разделять их на отдельный слой
    // поверх нельзя — ластик работает по общему полотну, — поэтому картинка
    // остаётся одна, меняется только цена кадра.
    var picture = layer.pictureFor(strokes.length, size);
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final buffer = Canvas(recorder);
      for (final s in strokes) {
        if (s.shapeType != null) {
          _drawShape(
            buffer,
            s.points,
            s.colorValue,
            s.strokeWidth,
            s.shapeType!,
            size,
            isFilledShape: s.isFilledShape,
          );
        } else {
          _drawStroke(
            buffer,
            s.points,
            s.colorValue,
            s.strokeWidth,
            s.isEraser,
            size,
          );
        }
      }
      picture = recorder.endRecording();
      layer.save(picture, strokes.length, size);
    }
    canvas.drawPicture(picture);

    if (currentPoints.isNotEmpty) {
      if (currentShapeType != null && currentPoints.length >= 2) {
        _drawShape(
          canvas,
          currentPoints,
          currentColorValue,
          currentStrokeWidth,
          currentShapeType!,
          size,
          isFilledShape: currentIsFilledShape,
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
      if (s.shapeType != null && s.points.length >= 2) {
        _drawShape(
          canvas,
          s.points,
          s.colorValue,
          s.strokeWidth,
          s.shapeType!,
          size,
          alpha: 0.85,
          isFilledShape: s.isFilledShape,
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
  }

  void _drawShape(
    Canvas canvas,
    List<DrawPoint> points,
    int colorValue,
    double strokeWidth,
    DrawShapeType shapeType,
    Size size, {
    double alpha = 1.0,
    required bool isFilledShape,
  }) {
    if (points.length < 2) return;
    final c = Color(colorValue);
    final paint = Paint()
      ..color = alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = isFilledShape ? PaintingStyle.fill : PaintingStyle.stroke;

    final s = points.first.toOffset(size);
    final e = points.last.toOffset(size);

    switch (shapeType) {
      case DrawShapeType.line:
        canvas.drawLine(s, e, paint);
      case DrawShapeType.rect:
        canvas.drawRect(Rect.fromPoints(s, e), paint);
      case DrawShapeType.circle:
        canvas.drawOval(Rect.fromPoints(s, e), paint);
      case DrawShapeType.triangle:
        final path = Path();
        path.moveTo((s.dx + e.dx) / 2, s.dy); // Top center
        path.lineTo(s.dx, e.dy); // Bottom left
        path.lineTo(e.dx, e.dy); // Bottom right
        path.close();
        canvas.drawPath(path, paint);
    }
  }

  /// Пиксельный штрих: точки — номера клеток, между ними шагаем алгоритмом
  /// Брезенхэма, иначе при быстром движении пальца в дорожке остаются дыры.
  void _drawPixelStroke(
    Canvas canvas,
    List<DrawPoint> points,
    int colorValue,
    bool isEraser,
    Size size,
    int cols,
    int rows, {
    double alpha = 1.0,
  }) {
    if (points.isEmpty || cols < 1 || rows < 1) return;
    final cw = size.width / cols;
    final ch = size.height / rows;
    final c = Color(colorValue);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..color = alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c;

    final cells = <int>{};
    int? prevX, prevY;
    for (final p in points) {
      final cx = (p.x * cols).floor().clamp(0, cols - 1);
      final cy = (p.y * rows).floor().clamp(0, rows - 1);
      if (prevX != null && prevY != null && (prevX != cx || prevY != cy)) {
        int x0 = prevX, y0 = prevY;
        final dx = (cx - x0).abs(), sx = x0 < cx ? 1 : -1;
        final dy = -(cy - y0).abs(), sy = y0 < cy ? 1 : -1;
        int err = dx + dy;
        while (true) {
          cells.add(y0 * cols + x0);
          if (x0 == cx && y0 == cy) break;
          final e2 = 2 * err;
          if (e2 >= dy) { err += dy; x0 += sx; }
          if (e2 <= dx) { err += dx; y0 += sy; }
        }
      }
      cells.add(cy * cols + cx);
      prevX = cx;
      prevY = cy;
    }

    // +0.5 к стороне — чтобы между соседними клетками не просвечивали щели
    // после округления координат.
    for (final key in cells) {
      final x = key % cols;
      final y = key ~/ cols;
      canvas.drawRect(
        Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5),
        paint,
      );
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
    // Пиксельный холст: клетки вместо сглаженной кривой.
    if (pixelCols != null && pixelRows != null) {
      _drawPixelStroke(canvas, points, colorValue, isEraser, size,
          pixelCols!, pixelRows!, alpha: alpha);
      return;
    }
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (isEraser) {
      // Drawing with bgColor is faster and more collaborative-friendly than BlendMode.dstOut
      paint.color = Color(colorValue);
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

  @override
  bool shouldRepaint(covariant _DrawingPainter old) =>
      old.strokes != strokes ||
      old.currentPoints != currentPoints ||
      old.currentColorValue != currentColorValue ||
      old.currentStrokeWidth != currentStrokeWidth ||
      old.currentIsEraser != currentIsEraser ||
      old.currentShapeType != currentShapeType ||
      old.canvasSize != canvasSize ||
      old.pixelCols != pixelCols ||
      old.pixelRows != pixelRows;
}
