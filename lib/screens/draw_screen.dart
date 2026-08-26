import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/coloring_clamp.dart';
import '../models/live_stroke_wire.dart';
import '../models/coloring_picture.dart';
import '../utils/canvas_image_cache.dart';
import '../utils/stroke_layer_cache.dart';
import '../utils/stroke_save_scheduler.dart';
import 'coloring_result_screen.dart';
import '../services/memory_repository.dart';
import '../models/memory.dart';
import '../utils/flood_fill.dart';
import '../utils/local_image_paths.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/draw/draw_tools_panel.dart';
import '../utils/color_hex.dart';
import '../widgets/app_sheet.dart';
import '../utils/safe_pick.dart';
import '../utils/safe_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/share_origin.dart';

import '../models/canvas_background.dart';
import '../models/draw_stroke.dart';
import '../models/pixel_grid_style.dart';
import '../models/pair_data.dart';
import '../models/ad_grants.dart';
import '../models/user_data.dart';
import '../services/analytics_service.dart';
import '../services/canvas_storage_service.dart';
import '../services/canvas_repository.dart';
import '../services/pb_data_service.dart';
import '../services/offline/outbox_service.dart';
import '../services/media_service.dart';
import '../services/locale_service.dart';
import '../services/pocketbase_service.dart';
import '../services/rewarded_ad_service.dart';
import '../utils/canvas_pinch.dart';
import '../theme/app_theme.dart';
import '../services/ui_prefs.dart';
import '../theme/motion.dart';
import '../theme/profile_theme.dart';
import '../models/canvas_symmetry.dart';
import '../models/draw_layout.dart';
import '../models/draw_quick_tools.dart';
import 'draw_replay_screen.dart';
import '../widgets/draw/stroke_painting.dart';
import '../models/canvas_undo.dart';
import '../models/stroke_transform.dart';
import '../utils/quick_shape.dart';
import '../utils/stroke_stabilizer.dart';
import '../widgets/common/app_dialog.dart';
import '../services/plus_access.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';
import '../utils/canvas_gestures.dart';


//  Palette

/// Ряд цветов в листе инструментов: семь штук плюс кнопка своей палитры —
/// столько помещается на 320 точках без прокрутки. Полный набор остаётся в
/// [_kPalette] и открывается кнопкой.
const List<Color> _kPanelPalette = [
  Color(0xFF000000),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFFBBF24),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
];

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
  /// Реклама за пробу платного фона: держим один экземпляр на экран, как в
  /// профиле, иначе каждый показ грузит ролик заново.
  final RewardedAdService _rewardedAd = RewardedAdService();

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
  /// Как часто уходит прирост мазка в канал партнёра.
  ///
  /// Раньше здесь стояли 150 мс, и в канал каждый раз ехал ВЕСЬ мазок: партнёр
  /// видел движение ступеньками, а сообщение росло вместе с линией. Теперь
  /// сорок миллисекунд и только новые точки — сотня байт вместо килобайтов.
  static const int _liveIncrementMs = 40;

  /// Как часто среди приростов идёт ключевой кадр со всей линией. Его читают
  /// сборки постарше (для них ничего не изменилось), и он чинит потерянный
  /// пакет, не дожидаясь конца мазка.
  static const int _liveKeyframeMs = 150;
  static const double _kMinScale = 0.2;
  /// Показывать направляющие пиксельной сетки. Выбор запоминается: кому-то
  /// удобнее целиться по клеткам, кому-то они мешают смотреть на рисунок.
  bool _showPixelGrid = true;
  static const String _kPixelGridPref = 'draw_pixel_grid_visible';

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

  /// Сквозная шкала действий холста. Нарисованные штрихи и правки формы лежат
  /// в разных стеках, а кнопка «отменить» одна: по этим номерам она понимает,
  /// что случилось позже (правило — `undoTakesEdit`).
  int _actionSeq = 0;
  final Map<String, int> _strokeSeq = {};
  final List<_ShapeEdit> _shapeEdits = [];
  final List<_ShapeEdit> _shapeRedos = [];
  final Map<String, DrawStroke> _pendingLocalStrokes = {};
  final Set<String> _cancelledPendingStrokeIds = {};
  final Map<String, DrawStroke> _partnerLiveMap = {};
  final Map<String, int> _partnerTimestamps = {};

  /// Сборщики приростов: по одному на каждого рисующего партнёра.
  final Map<String, LiveStrokeAssembler> _liveAssemblers = {};

  /// Чужие мазки, уже законченные в канале, но ещё не приехавшие из базы.
  /// Ключ — `clientId`: по нему пришедшая запись заменит эту копию.
  final Map<String, DrawStroke> _partnerCommitted = {};
  final Set<int> _activePointers = <int>{};

  List<DrawStroke> _remoteStrokes = [];

  /// Видимые штрихи и ревизия их ОСНОВЫ.
  ///
  /// Ревизия двигается на всё, кроме дописывания в конец: отмену, замену,
  /// пересортировку. Пока человек ведёт клетку за клеткой, она стоит на месте,
  /// и готовый слой в `StrokeLayerCache` не пересобирается — свежие штрихи
  /// рисуются поверх него. Правило — `appendOnly` в stroke_layer_cache.dart,
  /// под тестами.
  ///
  /// Состав едет в холст отдельным каналом, а не перестройкой экрана: коммит
  /// штриха звал `setState`, и в пиксельной раскраске это перебирало панели,
  /// палитру и список слоёв десятки раз в секунду.
  final ValueNotifier<StrokesSnapshot> _strokesNotifier =
      ValueNotifier<StrokesSnapshot>(const StrokesSnapshot(<DrawStroke>[], 0));
  int _strokesBaseRevision = 0;

  List<DrawStroke> get _visibleStrokes => _strokesNotifier.value.list;

  set _visibleStrokes(List<DrawStroke> next) {
    if (!appendOnly(_strokesNotifier.value.list, next)) _strokesBaseRevision++;
    _strokesNotifier.value = StrokesSnapshot(next, _strokesBaseRevision);
  }
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

  // ── Векторная правка ──────────────────────────────────────────────────
  /// Что сейчас выделено инструментом «Выделение».
  ///
  /// Правится КОПИЯ: пока палец ведёт, экран показывает изменённый штрих, а на
  /// сервер уходит одна правка по отпусканию. Иначе partner получал бы поток
  /// патчей на каждое движение — то же, из-за чего живой мазок ездит
  /// приростами, а не целиком.
  String? _selectedStrokeId;

  /// Штрих на момент начала жеста — от него считаются сдвиг, масштаб, поворот.
  DrawStroke? _selectBase;

  /// Точка холста, где палец взялся за выделенное.
  Offset _selectStartPx = Offset.zero;

  /// За какую ручку рамки тянут. null — тянут саму фигуру.
  StrokeHandle? _selectHandle;

  /// Правка ушла на сервер? Пока нет — по отпусканию отправим.
  bool _selectDirty = false;

  /// Как фигура выглядела до жеста — это и вернёт отмена.
  List<DrawPoint>? _selectPointsBefore;

  /// Палец на ручке поворота: угол считаем от середины фигуры.
  bool _selectRotating = false;
  double _selectStartAngle = 0;

  /// Канал рамки: painter слушает его напрямую, поэтому ведение пальцем не
  /// пересобирает дерево виджетов — та же причина, по которой состав рисунка
  /// уезжает каналом, а не через setState.
  final ValueNotifier<DrawStroke?> _selectionNotifier = ValueNotifier(null);
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

  /// Щипок двумя пальцами: ведёт шаг от кадра к кадру и гасит кадры, в
  /// которых Flutter перестроил жест (см. `PinchTracker`).
  final PinchTracker _pinch = PinchTracker();

  // Тап заливки: копим путь и время первого пальца, а красим на отпускании.
  // Пока заливка срабатывала по касанию, первый палец щипка успевал залить то,
  // на чём стоял, — «заливается куда попало, пока просто приближаю картинку»
  // (жалоба 19.08.2026).
  Offset? _fillTapStart;
  DateTime? _fillTapAt;
  double _fillTapTravel = 0;
  bool _fillTapSpoiled = false;

  // Путь и время текущего штриха: по ним решаем, оставлять ли его, когда
  // холста коснулся второй палец.
  Offset? _strokeStartPoint;
  DateTime? _strokeStartedAt;
  double _strokeTravel = 0;

  double _canvasRotation = 0.0; // radians
  Offset _canvasOffset = Offset.zero;
  bool _isZooming = false;
  int? _drawingPointerId;
  int _orderCounter = 0;
  DateTime _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLiveKeyframe = DateTime.fromMillisecondsSinceEpoch(0);

  /// Идентификатор мазка, который ведёт палец прямо сейчас. Он же уезжает в
  /// запись как `clientId`, поэтому партнёр узнаёт в пришедшей из базы записи
  /// тот самый мазок, который уже нарисовал у себя из живого канала.
  String? _liveSid;
  int _liveSeq = 0;
  int _liveSentPoints = 0;

  // Palm tool
  Offset _palmPanStart = Offset.zero;
  Offset _palmBaseOffset = Offset.zero;

  // Toolbar expansion
  /// Лист инструментов раскрыт. В свёрнутом виде на холсте только пузырь.
  bool _toolsOpen = false;
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

  bool get _canUndo => _myStrokeIds.isNotEmpty || _shapeEdits.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty || _shapeRedos.isNotEmpty;

  /// Штрих нарисовал я — значит его можно отменить. Номер по общей шкале.
  void _noteMyStroke(String id) {
    _myStrokeIds.add(id);
    _strokeSeq[id] = ++_actionSeq;
  }

  /// Сглаживание текущего мазка. Заводится на каждый мазок заново: у него своя
  /// память о том, где сейчас точка и где палец.
  StrokeStabilizer? _stabilizer;

  /// Сила сглаживания кисти, 0…1. Пиксельный режим и фигуры её не берут:
  /// клетке отставание вредит, а фигура живёт двумя точками.
  double _smoothing = kDefaultSmoothing;

  /// Превращать ли задержанный мазок в ровную фигуру.
  bool _quickShapes = true;

  /// Форма холста без листа, снятая при свёрнутой панели.
  double? _freeRatio;

  /// Состав панели быстрого доступа: человек собирает его в настройках.
  List<DrawQuickTool> _quickTools = kDefaultQuickTools;

  /// Где сейчас панель — снизу или сбоку. Считается по размеру экрана в
  /// `build`, потому что поворот меняет её на ходу.
  DrawLayout _layout = DrawLayout.bottomSheet;

  /// Фигура, которую только что узнали в мазке, дальше НЕ тянется за пальцем.
  /// Палец в этот момент стоит там, где человек закончил линию, и любое его
  /// движение сплющивало распознанный круг в полоску: холст двигает второй
  /// угол фигуры, а второй угол — это и есть палец.
  bool _shapeLocked = false;

  /// Симметрия: мазок повторяется зеркалами или лучами. Копии — обычные
  /// штрихи, поэтому партнёр видит их, ничего не зная про режим.
  SymmetryMode _symmetry = SymmetryMode.none;
  int _symmetrySectors = 6;

  /// К какой зеркальной пачке относится штрих. Нужна отмене: шесть лучей —
  /// это один мазок для руки, и снимать их по одному было бы издевательством.
  final Map<String, String> _mirrorGroupOf = {};

  /// Когда палец последний раз двигался, и часовой, который ждёт остановки.
  DateTime _lastMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset? _lastMovePoint;
  Timer? _quickShapeTimer;

  /// Сколько держать палец на месте, чтобы линия стала фигурой.
  static const Duration _kQuickShapeHold = Duration(milliseconds: 450);

  /// Тап двумя пальцами отменяет, тремя — возвращает. Считаем максимум
  /// одновременных пальцев, путь самого резвого и был ли щипок: правило
  /// живёт в `multiTapAction`.
  int _gestureFingers = 0;
  DateTime? _gestureStartedAt;
  final Map<int, Offset> _gestureOrigins = {};
  double _gestureTravel = 0;
  bool _gestureZoomed = false;

  bool _shownCanUndo = false;
  bool _shownCanRedo = false;
  int _shownLayerCount = 1;

  /// Перестроить панели, только если в них что-то изменилось.
  ///
  /// Коммит штриха звал `setState` и перебирал весь экран — панели, палитру,
  /// список слоёв, — а в пиксельной раскраске штрих это клетка, их десятки в
  /// секунду. Сам рисунок едет в холст каналом `_strokesNotifier` и в
  /// перестройке не нуждается; кнопкам «отменить» и «вернуть» она нужна ровно
  /// в тот момент, когда они меняют доступность.
  void _syncCanvasChrome() {
    if (!mounted) return;
    if (_shownCanUndo == _canUndo &&
        _shownCanRedo == _canRedo &&
        _shownLayerCount == _layerCount) {
      return;
    }
    setState(() {
      _shownCanUndo = _canUndo;
      _shownCanRedo = _canRedo;
      _shownLayerCount = _layerCount;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _activeColor = widget.pairData.isPaired
        ? _colorForUser(_myUid)
        : const Color(0xFF000000);
    unawaited(_loadPixelGridPref());
    unawaited(_loadBrushPrefs());
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
    // Зов партнёру: «сел рисовать, давай вместе». Один запрос на вход, дальше
    // всё решает сервер — и частоту, и выключатель, и то, что человеку в
    // приложении звать незачем. В одиночном холсте звать некого.
    if (_hasSharedCanvas) {
      unawaited(PbDataService().inviteToDraw(_groupId));
    }
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

  /// Запись всего холста на диск: `jsonEncode` всех штрихов плюс поход в
  /// SharedPreferences. На каждый штрих это терпимо в обычной раскраске, где
  /// штрих — целый мазок, и убийственно в пиксельной, где штрих — одна клетка:
  /// трёхсотая клетка сериализует триста штрихов. Планировщик склеивает правки
  /// и пишет раз в интервал, а выход с экрана дописывает последнее.
  late final StrokeSaveScheduler _soloSave = StrokeSaveScheduler(
    save: () => CanvasStorageService.instance.saveLocalStrokes(
      _myUid,
      _canvasId,
      _visibleStrokes,
      groupId: _groupId,
    ),
  );

  void _saveSoloStrokes() => _soloSave.schedule();

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
    _rewardedAd.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _markPresence(false);
    _strokesSub?.cancel();
    _liveSub?.cancel();
    _canvasMetaSub?.cancel();
    _staleTimer?.cancel();
    _hintTimer?.cancel();
    _quickShapeTimer?.cancel();
    _selectionNotifier.dispose();
    _toolbarAnim.dispose();
    _pulseAnim.dispose();
    _resetCtrl?.dispose();
    _clearLiveStroke();
    // Планировщик дописывает отложенный холст: закрытие экрана не должно
    // съедать последние клетки.
    _soloSave.dispose();
    _repaintNotifier.dispose();
    _viewTick.dispose();
    _partnerNotifier.dispose();
    _strokesNotifier.dispose();
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
      // Свёрнутое приложение система вправе выгрузить: отложенный холст
      // дописываем сразу, иначе последние клетки пропадут.
      _soloSave.flushNow();
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

  /// Первое знакомство с выделением: что вообще надо сделать пальцем.
  ///
  /// Инструмент ничего не рисует, и без объяснения он выглядит сломанным —
  /// человек водит по холсту, а следа нет.
  Future<void> _maybeShowSelectHint() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(UiPrefs.kSelectToolHintSeen) ?? false) return;
    await p.setBool(UiPrefs.kSelectToolHintSeen, true);
    if (!mounted) return;
    _showMessage(LocaleService.current.selectToolHint);
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
        .watchLivePackets(_groupId, _canvasId, _myUid)
        .handleError((e) => debugPrint('[Draw] live error: $e'))
        .listen(_onLivePacket);

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
      // Чужой мазок, который мы уже нарисовали из живого канала, заменяется
      // настоящей записью: узнаём его по клиентскому идентификатору.
      final clientId = remote.clientId;
      if (clientId != null) _partnerCommitted.remove(clientId);

      // Свой оптимистичный штрих сверяем сперва по идентификатору и только
      // потом на глаз — эвристика осталась для записей прежних сборок.
      final matchKey = remainingPending.entries
              .where((e) => clientId != null && e.value.clientId == clientId)
              .map((e) => e.key)
              .firstOrNull ??
          remainingPending.entries
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

    _visibleStrokes = _composeVisibleStrokes();
    _syncCanvasChrome();
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
      _partnerCommitted.clear();
      _liveAssemblers.clear();
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

  void _onLivePacket(LivePacket packet) {
    if (!mounted) return;
    final uid = packet.uid;
    final data = packet.data;

    // Надгробие: партнёр отпустил палец, живую копию убираем. Если мазок уже
    // зафиксирован финальным пакетом, убирать нечего — он лежит среди штрихов.
    if (data == null || data.isEmpty) {
      _liveAssemblers.remove(uid);
      if (_partnerLiveMap.remove(uid) != null) {
        _partnerTimestamps.remove(uid);
        _publishPartnerLive();
      }
      return;
    }

    final assembler = _liveAssemblers.putIfAbsent(uid, LiveStrokeAssembler.new);
    try {
      assembler.accept(data);
    } catch (e) {
      debugPrint('[Draw] parse live error: $e');
      return;
    }

    _partnerTimestamps[uid] =
        (data['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    if (assembler.done) {
      final finished = assembler.buildStroke(uid);
      _liveAssemblers.remove(uid);
      _partnerLiveMap.remove(uid);
      _partnerTimestamps.remove(uid);
      if (finished != null) {
        // Кладём мазок к себе НЕМЕДЛЕННО, не дожидаясь записи в базу: она
        // приедет позже и заменит его по clientId, а до 18.08.2026 в этой яме
        // линия партнёра просто отсутствовала.
        _partnerCommitted[finished.clientId ?? finished.id] = finished;
        _visibleStrokes = _composeVisibleStrokes();
        _repaintNotifier.value++;
      }
      _publishPartnerLive();
      return;
    }

    final live = assembler.buildLive(uid);
    if (live == null) return;
    _partnerLiveMap[uid] = live;
    _publishPartnerLive();
  }

  /// Живые мазки партнёров едут в painter отдельным каналом, без перестройки
  /// экрана: `setState` тут перебирал панели, палитру и список слоёв по
  /// двадцать пять раз в секунду.
  void _publishPartnerLive() {
    _partnerNotifier.value = List.of(_partnerLiveMap.values);
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
      _liveAssemblers.remove(uid);
    }
    _publishPartnerLive();
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
      // Мазки партнёра, законченные в живом канале, но ещё не приехавшие из
      // базы. Без них линия пропадала на те 200–600 мс, что идёт запись.
      ..._partnerCommitted.values,
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

  /// Лежит ли точка (уже в координатах холста) на самом холсте.
  bool _insideCanvas(Offset canvasPoint) =>
      canvasPoint.dx >= 0 &&
      canvasPoint.dy >= 0 &&
      canvasPoint.dx <= _canvasSize.width &&
      canvasPoint.dy <= _canvasSize.height;

  //  Tool selection

  void _selectTool(DrawTool tool) {
    _disarmEyedropper();
    _cancelCurrentGesture();
    setState(() {
      _activeTool = tool;
      if (tool != DrawTool.image) _selectedImageId = null;
      if (tool != DrawTool.select) {
        _selectedStrokeId = null;
        _selectBase = null;
        _selectHandle = null;
        _selectionNotifier.value = null;
      }
    });
    if (_showHint) setState(() => _showHint = false);
  }

  void _cancelCurrentGesture() {
    final had = _isDrawing || _currentPoints.isNotEmpty;
    // Сглаживание живёт ровно один мазок: чужая память о том, где был палец,
    // дала бы следующему мазку рывок от прежней точки.
    _stabilizer = null;
    _shapeLocked = false;
    _disarmQuickShape();
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

    // Мазок начинается только на холсте. Слой ввода лежит на всём листе, а холст
    // при уменьшении меньше листа: без этой проверки касание в зазоре начинало
    // штрих, который обрезка прижимала к краю, — по краю оставалась полоса.
    if (!_insideCanvas(_screenToCanvas(localPoint))) return;

    // Раскраска: чужая половина не принимает касаний ни в каком режиме — даже
    // когда её видно. Каждый отвечает за свою.
    if (_isColoring && !_inMySide(_screenToCanvas(localPoint))) {
      _showHalfHint();
      return;
    }

    if (_activeTool == DrawTool.fill) {
      // Красим на отпускании: сейчас ещё не известно, тап это или начало
      // щипка. Копим путь и время, решает `fillTapAccepted`.
      _fillTapStart = localPoint;
      _fillTapAt = DateTime.now();
      _fillTapTravel = 0;
      _fillTapSpoiled = false;
      return;
    }

    _strokeStartPoint = localPoint;
    _strokeStartedAt = DateTime.now();
    _strokeTravel = 0;

    // Кисть и ластик ведут линию рукой, им сглаживание помогает. У фигуры
    // точек всего две, у пиксельной клетки отставание превращается в
    // промахи мимо клетки — там стабилизатор выключен.
    _shapeLocked = false;
    _stabilizer = StrokeStabilizer(
      strength: (_isShapeTool || _isPixel) ? 0 : _smoothing,
    )..begin(localPoint);
    _armHoldWatch();

    _redoStack.clear();
    _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);
    _lastLiveKeyframe = DateTime.fromMillisecondsSinceEpoch(0);
    _liveSid = _newStrokeId();
    _liveSeq = 0;
    _liveSentPoints = 0;
    _lastPushedPointsCount = 0;
    _lastPushedTipX = double.nan;
    _lastPushedTipY = double.nan;
    if (_showHint) setState(() => _showHint = false);

    if (_isShapeTool) {
      final pt = DrawPoint.clampedFromOffset(
        _screenToCanvas(localPoint),
        _canvasSize,
      );
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
        ..add(DrawPoint.clampedFromOffset(
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
    // Сглаживаем в экранных точках и ДО прижатия к своей половине: иначе у
    // границы раскраски линия ползла бы вдоль неё с отставанием.
    final smoothed = _stabilizer?.update(localPoint);
    if (smoothed == null && _stabilizer != null) return;
    localPoint = smoothed ?? localPoint;
    if (_isColoring) localPoint = _clampToMySide(localPoint);
    if (_currentShapeType != null) {
      if (_shapeLocked) return;
      final end = DrawPoint.clampedFromOffset(
        _screenToCanvas(localPoint),
        _canvasSize,
      );
      if (_currentPoints.length >= 2) {
        _currentPoints[1] = end;
      } else {
        _currentPoints.add(end);
      }
    } else {
      final pt = DrawPoint.clampedFromOffset(
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
    _lastMoveAt = DateTime.now();
    _repaintNotifier.value++;
    _pushLiveStrokeIfNeeded();
  }

  /// Часовой удержания: следит, что палец замер. Одно и то же ожидание
  /// кормит два приёма — короткий путь означает пипетку, длинный ровную
  /// фигуру. Проверяем по таймеру, а не по движению: когда палец стоит,
  /// событий движения нет вовсе, а именно это и нужно поймать.
  void _armHoldWatch() {
    _quickShapeTimer?.cancel();
    if (_isPixel && !_holdPicksColor) return;
    if (_activeTool == DrawTool.palm ||
        _activeTool == DrawTool.image ||
        _activeTool == DrawTool.fill) {
      return;
    }
    _lastMoveAt = DateTime.now();
    _lastMovePoint = null;
    _quickShapeTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _onHoldTick(),
    );
  }

  void _disarmQuickShape() {
    _quickShapeTimer?.cancel();
    _quickShapeTimer = null;
  }

  /// Разрешено ли брать цвет удержанием. Отдельным полем, чтобы в пиксельном
  /// режиме часовой всё равно заводился: там фигур нет, а пипетка нужна.
  final bool _holdPicksColor = true;

  void _onHoldTick() {
    if (!_isDrawing || _canvasSize.isEmpty) return;
    final startedAt = _strokeStartedAt;
    if (_holdPicksColor &&
        startedAt != null &&
        _currentShapeType == null &&
        holdIsEyedropper(
          held: DateTime.now().difference(startedAt),
          travel: _strokeTravel,
        )) {
      // Палец стоит на месте с самого начала: человек не рисует, а
      // присматривается к цвету. Начатую точку убираем — она бы осталась
      // кляксой под пальцем.
      _disarmQuickShape();
      _cancelCurrentGesture();
      unawaited(_armEyedropper());
      return;
    }
    _tryQuickShape();
  }

  /// Палец постоял на месте — смотрим, не фигуру ли он вёл.
  void _tryQuickShape() {
    if (!_quickShapes || _isPixel || _isShapeTool) return;
    if (_activeTool != DrawTool.brush && _activeTool != DrawTool.eraser) return;
    if (!_isDrawing || _currentShapeType != null || _canvasSize.isEmpty) return;
    if (DateTime.now().difference(_lastMoveAt) < _kQuickShapeHold) return;

    // Разбираем в точках холста, а не в долях: у неквадратного листа доли
    // растягивают круг в овал, и разбор соврал бы.
    final pixels = _currentPoints
        .map((p) => Offset(p.x * _canvasSize.width, p.y * _canvasSize.height))
        .toList();
    final shape = recognizeQuickShape(pixels);
    if (shape == null) {
      // Не узнали — часового НЕ гасим. Раньше первая же неудача выключала его
      // до конца мазка: человек дорисовывал фигуру, замирал ещё раз, и ничего
      // не происходило — отсюда «срабатывает не всегда». Ждём следующей паузы.
      _lastMoveAt = DateTime.now();
      return;
    }
    _disarmQuickShape();

    DrawPoint toPoint(Offset o) => DrawPoint.clampedFromOffset(
          Offset(o.dx, o.dy),
          _canvasSize,
        );

    setState(() {
      _currentPoints
        ..clear()
        ..add(toPoint(shape.start))
        ..add(toPoint(shape.end));
      _currentShapeType = shape.type;
      _currentIsFilledShape = _fillShapes;
      _shapeLocked = true;
    });
    // Дальше конец фигуры ведёт сам палец, сглаживать там нечего.
    _stabilizer = null;
    HapticFeedback.mediumImpact();
    _repaintNotifier.value++;
    // Уйдёт ключевым кадром целиком: у партнёра кривая заменится фигурой.
    unawaited(_pushLiveStrokeAsync());
  }

  void _finishStroke() {
    if (!_isDrawing) return;
    _disarmQuickShape();
    _flushStabilizerTail();
    _isDrawing = false;
    _drawingPointerId = null;
    _commitCurrentStroke();
  }

  /// Хвост сглаживания: точка догоняет палец, иначе на быстром движении
  /// линия обрывается там, где фильтр отстал. Хвост — это дописывание в
  /// конец, поэтому живой мазок у партнёра он не ломает.
  void _flushStabilizerTail() {
    final tail = _stabilizer?.finish();
    _stabilizer = null;
    if (tail == null || tail.isEmpty) return;
    if (_currentShapeType != null || _canvasSize.isEmpty) return;
    for (final raw in tail) {
      final point = _isColoring ? _clampToMySide(raw) : raw;
      _currentPoints.add(
        DrawPoint.clampedFromOffset(
          _snapToCell(_screenToCanvas(point)),
          _canvasSize,
        ),
      );
    }
    _repaintNotifier.value++;
    unawaited(_pushLiveStrokeAsync());
  }

  void _pushLiveStrokeIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastLivePush).inMilliseconds >= _liveIncrementMs) {
      _lastLivePush = now;
      unawaited(_pushLiveStrokeAsync());
    }
  }

  int _lastPushedPointsCount = 0;
  double _lastPushedTipX = double.nan;
  double _lastPushedTipY = double.nan;

  Future<void> _pushLiveStrokeAsync() async {
    if (!_hasSharedCanvas || _currentPoints.isEmpty) return;
    // Ничего не поменялось с прошлого пакета: у кривой растёт число точек, у
    // фигуры их всегда две и двигается только конец — проверяем оба случая.
    final tip = _currentPoints.last;
    if (_currentPoints.length == _lastPushedPointsCount &&
        tip.x == _lastPushedTipX &&
        tip.y == _lastPushedTipY) {
      return;
    }
    _lastPushedPointsCount = _currentPoints.length;
    _lastPushedTipX = tip.x;
    _lastPushedTipY = tip.y;

    final sid = _liveSid ??= _newStrokeId();
    final now = DateTime.now();
    // Фигура (линия, круг, прямоугольник) живёт двумя точками, и вторая
    // ездит: приростом её не передать, шлём целиком.
    final needKeyframe = _currentShapeType != null ||
        _liveSentPoints == 0 ||
        _liveSentPoints > _currentPoints.length ||
        now.difference(_lastLiveKeyframe).inMilliseconds >= _liveKeyframeMs;

    final Map<String, dynamic> packet;
    if (needKeyframe) {
      packet = LiveStrokeWire.keyframe(
        sid: sid,
        seq: _liveSeq++,
        points: _currentPoints,
        meta: _liveMeta(),
      );
      _lastLiveKeyframe = now;
    } else {
      packet = LiveStrokeWire.increment(
        sid: sid,
        seq: _liveSeq++,
        from: _liveSentPoints,
        points: _currentPoints.sublist(_liveSentPoints),
        meta: _liveMeta(),
      );
    }
    _liveSentPoints = _currentPoints.length;

    try {
      await _canvas.setLive(_groupId, _canvasId, _myUid, packet);
    } catch (e) {
      debugPrint('[Draw] live push error: $e');
    }
  }

  LiveStrokeMeta _liveMeta() => LiveStrokeMeta(
        colorValue: _currentColorValue,
        strokeWidth: _currentStrokeWidth,
        isEraser: _currentIsEraser,
        isFilledShape: _currentIsFilledShape,
        shapeType: _currentShapeType,
      );

  /// Идентификатор мазка: время, номер в порядке рисования и хвост своего uid.
  /// Хвост нужен, чтобы у двоих, рисующих в одну миллисекунду, не совпали
  /// идентификаторы: по ним партнёр узнаёт мазок в пришедшей записи.
  String _newStrokeId() {
    final tail = _myUid.length > 4 ? _myUid.substring(_myUid.length - 4) : _myUid;
    return 'local_${DateTime.now().millisecondsSinceEpoch}_${_orderCounter}_$tail';
  }

  /// Последний пакет мазка: партнёр кладёт линию к себе немедленно, не дожидаясь
  /// записи в базу. До 18.08.2026 живую копию снимали сразу, а постоянная
  /// приходила через 200–600 мс, и всё это время мазок у партнёра отсутствовал.
  Future<void> _pushLiveDone(DrawStroke stroke) async {
    if (!_hasSharedCanvas) return;
    final sid = stroke.clientId;
    if (sid == null) return;
    try {
      await _canvas.setLive(
        _groupId,
        _canvasId,
        _myUid,
        LiveStrokeWire.done(
          sid: sid,
          seq: _liveSeq++,
          points: stroke.points,
          meta: LiveStrokeMeta(
            colorValue: stroke.colorValue,
            strokeWidth: stroke.strokeWidth,
            isEraser: stroke.isEraser,
            isFilledShape: stroke.isFilledShape,
            shapeType: stroke.shapeType,
          ),
          orderIndex: stroke.orderIndex,
        ),
      );
    } catch (e) {
      debugPrint('[Draw] live done error: $e');
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
      _gestureFingers = 0;
      _gestureStartedAt = DateTime.now();
      _gestureOrigins.clear();
      _gestureTravel = 0;
      _gestureZoomed = false;
    }

    _activePointers.add(event.pointer);
    _gestureOrigins[event.pointer] = event.localPosition;
    if (_activePointers.length > _gestureFingers) {
      _gestureFingers = _activePointers.length;
    }

    if (_activePointers.length >= 2) {
      _isZooming = false; // дальше подхватит onScaleStart
      // Щипок начался — заливке тут делать нечего.
      _fillTapSpoiled = true;
      // Второй палец раньше стирал начатую линию целиком: коснулись ладонью —
      // и штрих пропал. Теперь линия остаётся, а огрызок в две точки, который
      // первый палец щипка успел поставить за 20–80 мс, — нет. Различает их
      // `strokeSurvivesSecondFinger` по пройденному пути и времени, а не по
      // числу точек: точек за это время набегает сколько угодно.
      final held = _strokeStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_strokeStartedAt!);
      if (_isDrawing &&
          strokeSurvivesSecondFinger(travel: _strokeTravel, held: held)) {
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

    // Выделение: взяли фигуру или ручку рамки.
    if (_activeTool == DrawTool.select) {
      _beginSelectionGesture(event.localPosition);
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
    // Путь считаем до всех проверок: у щипка события движения приходят по
    // каждому пальцу, и именно этот путь отличает щипок от тапа.
    final origin = _gestureOrigins[event.pointer];
    if (origin != null) {
      final moved = (event.localPosition - origin).distance;
      if (moved > _gestureTravel) _gestureTravel = moved;
    }
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

    // Ведём выделенное: саму фигуру или её край.
    if (_activeTool == DrawTool.select && _selectBase != null) {
      _dragSelection(event.localPosition);
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
      _applyStrokeUpdate(_copyImageStroke(_imgDragBase!, x: newX, y: newY));
      return;
    }

    if (_activeTool == DrawTool.fill) {
      final from = _fillTapStart;
      if (from != null) {
        _fillTapTravel = (event.localPosition - from).distance;
      }
      return;
    }

    if (_drawingPointerId != event.pointer) return;
    final start = _strokeStartPoint;
    if (start != null) {
      final travelled = (event.localPosition - start).distance;
      if (travelled > _strokeTravel) _strokeTravel = travelled;
    }
    // Палец считается движущимся по САМОМУ пальцу, а не по добавленным
    // точкам: медленный ход даёт сдвиги мельче шага сглаживания, и часовой
    // ровных фигур принимал бы такое ведение за остановку.
    final prev = _lastMovePoint;
    // Порог заметно больше пикселя: палец на стекле дрожит всегда, и при
    // 1,5 точки пауза не наступала вовсе — фигуры не срабатывали.
    if (prev == null || (event.localPosition - prev).distance > 3.5) {
      _lastMovePoint = event.localPosition;
      _lastMoveAt = DateTime.now();
    }
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

    // Правка фигуры уходит одним запросом — по отпусканию, а не на каждое
    // движение пальца.
    if (_activeTool == DrawTool.select && _activePointers.isEmpty) {
      unawaited(_commitSelection());
    }

    // Заливка ждала до этого момента: теперь видно, был ли это тап одним
    // пальцем или человек сводил пальцы, чтобы приблизить картинку.
    final fillFrom = _fillTapStart;
    if (_activeTool == DrawTool.fill && fillFrom != null) {
      final held = _fillTapAt == null
          ? Duration.zero
          : DateTime.now().difference(_fillTapAt!);
      final accepted = fillTapAccepted(
        travel: _fillTapTravel,
        held: held,
        extraPointers: _activePointers.length,
        zoomed: _isZooming || _fillTapSpoiled,
      );
      _fillTapStart = null;
      _fillTapAt = null;
      _fillTapTravel = 0;
      if (accepted) unawaited(_applyFill(fillFrom));
    }

    if (wasDrawing && !_isZooming) {
      _finishStroke();
    }
    _strokeStartPoint = null;
    _strokeStartedAt = null;
    _strokeTravel = 0;

    if (_activePointers.isEmpty) {
      _runMultiTapIfAny();
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

  /// Пальцы ушли с экрана: разбираем, не был ли это тап отмены или возврата.
  void _runMultiTapIfAny() {
    final started = _gestureStartedAt;
    _gestureStartedAt = null;
    if (started == null || _eyedropperArmed) return;
    final action = multiTapAction(
      fingers: _gestureFingers,
      held: DateTime.now().difference(started),
      travel: _gestureTravel,
      zoomed: _gestureZoomed,
    );
    switch (action) {
      case MultiTapAction.undo:
        if (!_canUndo) return;
        HapticFeedback.selectionClick();
        unawaited(_undo());
      case MultiTapAction.redo:
        if (!_canRedo) return;
        HapticFeedback.selectionClick();
        unawaited(_redo());
      case MultiTapAction.none:
        return;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_eyedropperArmed) return;
    if (details.pointerCount < 2) return;
    // Два пальца при выделенной фигуре крутят и тянут ЕЁ, а не лист: человек
    // взялся за фигуру, и щипок над ней про неё.
    if (_activeTool == DrawTool.select && _selectedStroke != null) {
      _rememberShapeBefore(_selectedStroke!);
      _selectBase = _selectedStroke;
      _selectHandle = null;
      _isZooming = true;
      return;
    }
    _isZooming = true;
    _pinch.begin();
    _cancelCurrentGesture();
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
    if (_activeTool == DrawTool.select && _selectBase != null) {
      _pinchSelection(details);
      return;
    }
    if (!_isZooming && details.pointerCount < 2) return;
    _isZooming = true;
    // Щипок состоялся — тап отмены отменяется сам: сведённые на процент
    // пальцы не должны стирать чужую работу.
    if ((details.scale - 1).abs() > 0.01 || details.rotation.abs() > 0.01) {
      _gestureZoomed = true;
    }

    // Шаг считается ОТ ПРОШЛОГО КАДРА, а кадр перестройки жеста пропускается
    // целиком. Flutter при любом изменении состава пальцев назначает новую
    // точку отсчёта: масштаб возвращается к единице, поворот к нулю, средний
    // фокус скачком уезжает. Обработчик, считавший от своей базы и от
    // абсолютного фокуса, в такие кадры швырял лист в сторону — «двумя
    // пальцами вообще капец», при том что ладонью всё ровно.
    final step = _pinch.step(
      pointerCount: details.pointerCount,
      scale: details.scale,
      rotation: details.rotation,
      focal: details.localFocalPoint,
      focalDelta: details.focalPointDelta,
    );
    if (step == null) return;

    // Image pinch: scale + rotate the selected image
    if (_activeTool == DrawTool.image &&
        _imgDragBase != null &&
        _selectedImageId != null) {
      final newW = (_imgScaleBaseW * details.scale).clamp(0.05, 2.0);
      final newH = (_imgScaleBaseH * details.scale).clamp(0.05, 2.0);
      final newRot = _imgScaleBaseRot + details.rotation;
      _applyStrokeUpdate(
        _copyImageStroke(_imgDragBase!, w: newW, h: newH, rot: newRot),
      );
      return;
    }

    final next = applyPinch(
      CanvasView(
        scale: _scale,
        rotation: _canvasRotation,
        offset: _canvasOffset,
      ),
      step,
      minScale: _kMinScale,
      maxScale: _kMaxScale,
    );
    _scale = next.scale;
    _canvasRotation = next.rotation;
    _canvasOffset = next.offset;
    _bumpView();
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _isZooming = false;
    if (_activeTool == DrawTool.select) {
      unawaited(_commitSelection());
    }
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
  }) =>
      copyImageStroke(s, x: x, y: y, w: w, h: h, rot: rot, url: url);

  /// Показать правленый штрих на холсте: и свой неотправленный, и приехавший с
  /// сервера, и одиночный. Имя было `_applyImageUpdate`, хотя картинок метод
  /// не касается — теперь через него идёт и векторная правка.
  // ── Векторная правка: взять, вести, отпустить ─────────────────────────

  /// Щипок над выделенной фигурой: масштаб и поворот сразу, как в любом
  /// редакторе. Считаем от состояния на начало жеста, а не накапливаем —
  /// накопление дрожит и уводит фигуру.
  void _pinchSelection(ScaleUpdateDetails details) {
    final base = _selectBase;
    if (base == null || _canvasSize.isEmpty) return;
    var updated = base;
    if ((details.scale - 1).abs() > 0.005) {
      updated = scaleStroke(updated, details.scale, _canvasSize);
    }
    if (details.rotation.abs() > 0.005) {
      updated = rotateStroke(updated, details.rotation, _canvasSize);
    }
    if (identical(updated, base)) return;
    _selectDirty = true;
    _applyStrokeUpdate(updated);
  }


  DrawStroke? get _selectedStroke {
    final id = _selectedStrokeId;
    if (id == null) return null;
    for (final s in _visibleStrokes) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Прикосновение при активном «Выделении».
  ///
  /// Сначала пробуем ручки уже выделенной рамки — иначе за край мелкой фигуры
  /// не взяться: палец попадает и в ручку, и в саму фигуру, и она просто
  /// уезжает вместо растягивания.
  void _beginSelectionGesture(Offset screenPoint) {
    if (_canvasSize.isEmpty) return;
    final canvasPoint = _screenToCanvas(screenPoint);

    final current = _selectedStroke;
    if (current != null) {
      final spin = strokeBounds(current, _canvasSize)
          .inflate(kSelectionPad)
          .topCenter
          .translate(0, -kSelectionSpinGap);
      if ((spin - canvasPoint).distance <= 22 / _scale) {
        _rememberShapeBefore(current);
        setState(() {
          _selectRotating = true;
          _selectHandle = null;
          _selectBase = current;
          _selectStartPx = canvasPoint;
          _selectStartAngle = _angleAround(current, canvasPoint);
        });
        return;
      }
      final handle = _handleAt(current, canvasPoint);
      if (handle != null) {
        _rememberShapeBefore(current);
        setState(() {
          _selectHandle = handle;
          _selectBase = current;
          _selectStartPx = canvasPoint;
        });
        return;
      }
    }

    // Картинки правит инструмент «Фото» — со своей рамкой и своими полями
    // положения; ластик формы не имеет вовсе.
    final hit = strokeAtPoint(
      _visibleStrokes
          .where((s) => !s.isEraser && !s.isImageStroke)
          .toList(),
      canvasPoint,
      _canvasSize,
      tolerance: 18 / _scale,
    );
    if (hit != null) _rememberShapeBefore(hit);
    setState(() {
      _selectRotating = false;
      _selectedStrokeId = hit?.id;
      _selectBase = hit;
      _selectHandle = null;
      _selectStartPx = canvasPoint;
    });
    _selectionNotifier.value = hit;
  }

  /// Форма до начала жеста. Второй раз за один жест не перезаписываем: щипок
  /// приходит поверх уже начатого касания, и отмена вернула бы фигуру не туда,
  /// откуда её повели, а в середину движения.
  void _rememberShapeBefore(DrawStroke stroke) {
    if (_selectDirty) return;
    _selectPointsBefore = List<DrawPoint>.unmodifiable(stroke.points);
  }

  /// Ручка рамки под пальцем. Размер зоны делим на масштаб холста: на
  /// приближенном листе ручка не должна становиться размером с ладонь.
  StrokeHandle? _handleAt(DrawStroke stroke, Offset canvasPoint) {
    final b = strokeBounds(stroke, _canvasSize).inflate(kSelectionPad);
    final grab = 22 / _scale;
    final spots = <StrokeHandle, Offset>{
      StrokeHandle.topLeft: b.topLeft,
      StrokeHandle.topRight: b.topRight,
      StrokeHandle.bottomLeft: b.bottomLeft,
      StrokeHandle.bottomRight: b.bottomRight,
      StrokeHandle.left: Offset(b.left, b.center.dy),
      StrokeHandle.right: Offset(b.right, b.center.dy),
      StrokeHandle.top: Offset(b.center.dx, b.top),
      StrokeHandle.bottom: Offset(b.center.dx, b.bottom),
    };
    for (final e in spots.entries) {
      if ((e.value - canvasPoint).distance <= grab) return e.key;
    }
    return null;
  }

  /// Угол от середины фигуры до точки — им меряется поворот ручкой.
  double _angleAround(DrawStroke stroke, Offset canvasPoint) {
    final c = strokeBounds(stroke, _canvasSize).center;
    return math.atan2(canvasPoint.dy - c.dy, canvasPoint.dx - c.dx);
  }

  void _dragSelection(Offset screenPoint) {
    final base = _selectBase;
    if (base == null || _canvasSize.isEmpty) return;
    final point = _screenToCanvas(screenPoint);
    if (_selectRotating) {
      _selectDirty = true;
      _applyStrokeUpdate(rotateStroke(
        base,
        _angleAround(base, point) - _selectStartAngle,
        _canvasSize,
      ));
      return;
    }
    final delta = point - _selectStartPx;
    final handle = _selectHandle;
    final updated = handle == null
        ? moveStroke(base, delta, _canvasSize)
        : stretchStroke(base,
            handle: handle, delta: delta, canvas: _canvasSize);
    _selectDirty = true;
    _applyStrokeUpdate(updated);
  }

  /// Отпустили — отправляем ОДНУ правку. Пока палец вёл, партнёру не уходило
  /// ничего: поток патчей на каждое движение положил бы и сеть, и очередь.
  Future<void> _commitSelection() async {
    if (!_selectDirty) return;
    _selectDirty = false;
    final stroke = _selectedStroke;
    final before = _selectPointsBefore;
    _selectPointsBefore = null;
    _selectRotating = false;
    // Правка попадает в отмену целиком, одной записью: человек вёл фигуру
    // одним движением, и снимать это надо тоже одним нажатием.
    if (stroke != null && before != null) {
      _shapeRedos.clear();
      _shapeEdits.add(_ShapeEdit(
        id: stroke.id,
        before: before,
        after: List<DrawPoint>.unmodifiable(stroke.points),
        seq: ++_actionSeq,
      ));
      _syncCanvasChrome();
    }
    _selectBase = stroke;
    _selectHandle = null;
    if (stroke == null) return;
    if (!_hasSharedCanvas) {
      // Свой холст живёт на диске: без этого подвинутая фигура возвращалась бы
      // на прежнее место при следующем заходе.
      _saveSoloStrokes();
      return;
    }
    if (_pendingLocalStrokes.containsKey(stroke.id)) return; // ещё не на сервере
    try {
      await _canvas.patchStroke(stroke.id, {
        'points': [for (final p in stroke.points) p.toMap()],
      });
    } catch (e) {
      debugPrint('[Draw] не удалось сохранить правку фигуры: $e');
    }
  }

  /// Вернуть фигуре прежние точки: локально и на сервере.
  Future<void> _applyShapePoints(String id, List<DrawPoint> points) async {
    final current = _visibleStrokes.where((s) => s.id == id).firstOrNull;
    if (current == null) return;
    _applyStrokeUpdate(strokeWithPoints(current, points));
    if (!_hasSharedCanvas) {
      _saveSoloStrokes();
      return;
    }
    if (_pendingLocalStrokes.containsKey(id)) return;
    try {
      await _canvas.patchStroke(id, {
        'points': [for (final p in points) p.toMap()],
      });
    } catch (e) {
      debugPrint('[Draw] не удалось отменить правку фигуры: $e');
    }
  }

  void _applyStrokeUpdate(DrawStroke updated) {
    // Рамка обязана ехать вместе с фигурой: иначе она остаётся на прежнем
    // месте, и человек тянет пустоту.
    if (updated.id == _selectedStrokeId) _selectionNotifier.value = updated;
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
      if (vi >= 0) {
        // Через сеттер, а не правкой на месте: иначе ревизия основы не
        // сдвинется и слой останется с прежней картинкой штриха.
        final next = List<DrawStroke>.from(_visibleStrokes);
        next[vi] = updated;
        _visibleStrokes = next;
      }
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
    _noteMyStroke(id);
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

    // Идентификатор мазка тот же, под которым он ехал в живом канале: партнёр
    // уже нарисовал его у себя и по нему узнает пришедшую из базы запись.
    final sid = _liveSid ?? _newStrokeId();
    final stroke = DrawStroke(
      id: sid,
      clientId: sid,
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
    // Сперва финальный пакет — по нему партнёр оставляет мазок у себя сразу, —
    // и только потом надгробие, которое снимает живую копию у сборок постарше.
    unawaited(_pushLiveDone(stroke).then((_) => _clearLiveStroke()));
    _liveSid = null;
    _repaintNotifier.value++;
    _orderCounter++;
    _submitStroke(stroke);
    _submitMirrors(stroke, sid);
  }

  /// Зеркальные копии мазка. Уходят при отпускании пальца, а не живьём: шесть
  /// лучей в канале — это шесть мазков вместо одного, и рисование у обоих
  /// начинает запаздывать. Партнёр получает их из базы, как обычные штрихи.
  void _submitMirrors(DrawStroke stroke, String groupKey) {
    if (_symmetry == SymmetryMode.none || _canvasSize.isEmpty) return;
    final copies = mirrorStroke(
      stroke.points,
      _symmetry,
      sectors: _symmetrySectors,
      aspect: _canvasSize.height == 0
          ? 1
          : _canvasSize.width / _canvasSize.height,
    );
    if (copies.isEmpty) return;
    _mirrorGroupOf[stroke.id] = groupKey;
    for (final points in copies) {
      final id = _newStrokeId();
      _mirrorGroupOf[id] = groupKey;
      _submitStroke(
        DrawStroke(
          id: id,
          clientId: id,
          userId: _myUid,
          colorValue: stroke.colorValue,
          strokeWidth: stroke.strokeWidth,
          points: List<DrawPoint>.unmodifiable(points),
          isEraser: stroke.isEraser,
          isFilledShape: stroke.isFilledShape,
          shapeType: stroke.shapeType,
          orderIndex: _orderCounter,
          layer: stroke.layer,
        ),
      );
      _orderCounter++;
    }
  }

  void _submitStroke(DrawStroke stroke) {
    if (!_hasSharedCanvas) {
      _visibleStrokes = [..._visibleStrokes, stroke]..sort(_compareStrokes);
      _noteMyStroke(stroke.id);
      _syncCanvasChrome();
      _saveSoloStrokes();
      return;
    }

    _pendingLocalStrokes[stroke.id] = stroke;
    _visibleStrokes = _composeVisibleStrokes();
    _noteMyStroke(stroke.id);
    _syncCanvasChrome();

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
          // Штрих остаётся на холсте, а доставку берёт очередь. Раньше отказ
          // стирал нарисованное: в пиксельной раскраске клетки уходят
          // десятками в секунду, часть запросов не проходит, и рисунок
          // осыпался прямо под рукой («всё стирает»).
          unawaited(OutboxService.instance.enqueue('strokeAdd', {
            'id': stroke.id,
            'groupId': _groupId,
            'canvasId': _canvasId,
            'stroke': stroke.toFirestore(),
          }));
        });
  }

  //  Undo / Redo

  /// Отмена. Зеркальная пачка снимается целиком: для руки шесть лучей — один
  /// мазок, и шесть нажатий подряд читались бы как поломка кнопки.
  Future<void> _undo() async {
    if (undoTakesEdit(
      lastEditSeq: _shapeEdits.isEmpty ? null : _shapeEdits.last.seq,
      lastStrokeSeq:
          _myStrokeIds.isEmpty ? null : _strokeSeq[_myStrokeIds.last],
    )) {
      final edit = _shapeEdits.removeLast();
      await _applyShapePoints(edit.id, edit.before);
      _shapeRedos.add(edit);
      _syncCanvasChrome();
      return;
    }
    if (_myStrokeIds.isEmpty) return;
    final undoKey = _myStrokeIds.removeLast();
    final group = _mirrorGroupOf[undoKey];
    await _undoOne(undoKey);
    if (group == null) return;
    while (_myStrokeIds.isNotEmpty &&
        _mirrorGroupOf[_myStrokeIds.last] == group) {
      await _undoOne(_myStrokeIds.removeLast());
    }
  }

  Future<void> _undoOne(String undoKey) async {

    DrawStroke? removed;
    String? remoteIdForDelete;

    if (_pendingLocalStrokes.containsKey(undoKey)) {
      removed = _pendingLocalStrokes.remove(undoKey);
      _cancelledPendingStrokeIds.add(undoKey);
      // Штрих мог не долететь с первого раза и ждать в очереди. Снимаем задачу,
      // иначе очередь пришлёт его позже и отменённое вернётся на холст.
      unawaited(
          OutboxService.instance.enqueue('strokeCancel', {'id': undoKey}));
    } else {
      removed = _visibleStrokes.where((s) => s.id == undoKey).firstOrNull;
      if (removed != null && _hasSharedCanvas) {
        _remoteStrokes = _remoteStrokes.where((s) => s.id != undoKey).toList();
        remoteIdForDelete = undoKey;
      }
    }

    if (removed == null) return;
    _redoStack.add(removed);
    _strokeSeq[removed.id] = ++_actionSeq;
    // Правки удалённой фигуры отменять уже не на чем.
    _shapeEdits.removeWhere((e) => e.id == undoKey);
    _shapeRedos.removeWhere((e) => e.id == undoKey);
    if (_selectedStrokeId == undoKey) {
      _selectedStrokeId = null;
      _selectBase = null;
      _selectionNotifier.value = null;
    }

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

  /// Возврат. Зеркальная пачка возвращается так же целиком, как снималась.
  Future<void> _redo() async {
    if (undoTakesEdit(
      lastEditSeq: _shapeRedos.isEmpty ? null : _shapeRedos.last.seq,
      lastStrokeSeq:
          _redoStack.isEmpty ? null : _strokeSeq[_redoStack.last.id],
    )) {
      final edit = _shapeRedos.removeLast();
      await _applyShapePoints(edit.id, edit.after);
      _shapeEdits.add(edit);
      _syncCanvasChrome();
      return;
    }
    if (_redoStack.isEmpty) return;
    final group = _mirrorGroupOf[_redoStack.last.id];
    await _redoOne();
    if (group == null) return;
    while (_redoStack.isNotEmpty &&
        _mirrorGroupOf[_redoStack.last.id] == group) {
      await _redoOne();
    }
  }

  Future<void> _redoOne() async {
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
    // Вернувшийся штрих получает новый id, а зеркальная пачка должна остаться
    // пачкой: иначе следующая отмена снимет её по одному.
    final group = _mirrorGroupOf[base.id];
    if (group != null) _mirrorGroupOf[stroke.id] = group;
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
      // Снимаем вдвое подробнее экрана. Один к одному край заливки выходил
      // ступеньками и «пятнами», стоило приблизить лист: пятно, посчитанное по
      // трёмстам точкам, растягивалось на полторы тысячи. Выше двух не идём и
      // упираемся в потолок 1600 — столько же в самой картинке раскраски, а
      // заливка и так самая тяжёлая операция на холсте.
      final longest = _canvasSize.longestSide;
      final ratio = longest <= 0
          ? 1.0
          : (1600 / longest).clamp(1.0, 2.0).toDouble();
      final snapshot = await boundary.toImage(pixelRatio: ratio);

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
      _noteMyStroke(id);
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
          child: LayoutBuilder(
            builder: (context, box) {
              _layout = drawLayoutFor(box.biggest);
              final side = _layout == DrawLayout.sidePanel;
              final canvas = Expanded(
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
                    // Свёрнутая панель — один пузырь в углу: на холсте видно
                    // текущий инструмент и текущий цвет, всё прочее приезжает
                    // листом по касанию.
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: IgnorePointer(
                        ignoring: _toolsOpen,
                        child: AnimatedScale(
                          scale: _toolsOpen ? 0.6 : 1,
                          duration: Motion.block,
                          curve: Motion.emphasized,
                          child: AnimatedOpacity(
                            opacity: _toolsOpen ? 0 : 1,
                            duration: Motion.tap,
                            child: DrawToolBubble(
                              color: _activeColor,
                              icon: _bubbleIcon,
                              fill: t.fillColor,
                              onFill: AppThemes.onColor(t.fillColor,
                                  mode: t.brightness),
                              onTap: () => setState(() => _toolsOpen = true),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );

              // Лёжа экран низкий: лист панели съел бы холст целиком, поэтому
              // инструменты уходят в колонку справа, а холст занимает всё, что
              // осталось.
              if (side) {
                return Column(
                  children: [
                    _buildTopBar(s, t),
                    Expanded(
                      child: Row(
                        // Панель тянется во всю высоту: колонка, а не
                        // карточка, повисшая посреди края экрана.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                canvas,
                                if (_isColoring) _buildColoringBar(s, t),
                              ],
                            ),
                          ),
                          _buildSidePanel(s, t, box.biggest),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  _buildTopBar(s, t),
                  canvas,
                  // Раскраска: полоса готовности над панелью инструментов.
                  if (_isColoring) _buildColoringBar(s, t),
                  _buildBottomToolbar(s, t),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Панель сбоку: выезжает справа и забирает у холста ширину, а не высоту.
  Widget _buildSidePanel(AppStrings s, AppTheme t, Size screen) {
    final width = sidePanelWidth(screen);
    return AnimatedContainer(
      duration: Motion.block,
      curve: Motion.emphasized,
      width: _toolsOpen ? width : 0,
      child: _toolsOpen
          ? ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: width,
                minWidth: width,
                child: SizedBox(width: width, child: _toolsSheet(s, t)),
              ),
            )
          : const SizedBox.shrink(),
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
    // Лёжа высота на вес золота: шапке хватает половины прежних полей.
    final tight = _layout == DrawLayout.sidePanel;
    return Padding(
      padding: tight
          ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
          : const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
          _pillIcon(Icons.redo_rounded, _canRedo ? _redo : null,
              tooltip: s.redoAction),
          const SizedBox(width: 8),
          // Фон, рука и очистка переехали сюда из нижнего ряда: панель
          // рисования держит шесть кнопок, а редкие действия прячутся в меню.
          _buildMoreMenu(s, t),
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

  /// Редкие действия холста: фон, перетаскивание, очистка.
  Widget _buildMoreMenu(AppStrings s, AppTheme t) {
    return PopupMenuButton<String>(
      tooltip: s.drawMore,
      position: PopupMenuPosition.under,
      icon: Icon(Icons.more_horiz_rounded, size: 21, color: t.textPrimary),
      onSelected: (value) {
        switch (value) {
          case 'background':
            _openBackgroundSheet();
          case 'palm':
            _selectTool(DrawTool.palm);
          case 'move-image':
            _selectTool(DrawTool.image);
          case 'replay':
            _openReplay();
          case 'clear':
            _confirmClear();
          case 'delete-image':
            _deleteSelectedImage();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'replay',
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline_rounded, size: 20),
              const SizedBox(width: 12),
              Text(s.drawReplay),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'background',
          child: Row(
            children: [
              const Icon(Icons.texture_rounded, size: 20),
              const SizedBox(width: 12),
              Text(s.drawBackgrounds),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'palm',
          child: Row(
            children: [
              Icon(
                Icons.pan_tool_rounded,
                size: 20,
                color: _activeTool == DrawTool.palm ? t.primary : null,
              ),
              const SizedBox(width: 12),
              Text(s.palmTool),
            ],
          ),
        ),
        // Режим перемещения включается сам после вставки фото, но человек
        // мог уйти на кисть — сюда он и возвращается.
        PopupMenuItem(
          value: 'move-image',
          child: Row(
            children: [
              Icon(
                Icons.open_with_rounded,
                size: 20,
                color: _activeTool == DrawTool.image ? t.primary : null,
              ),
              const SizedBox(width: 12),
              Text(s.photo),
            ],
          ),
        ),
        if (_selectedImageId != null)
          PopupMenuItem(
            value: 'delete-image',
            child: Row(
              children: [
                const Icon(Icons.hide_image_rounded, size: 20),
                const SizedBox(width: 12),
                Text(s.deletePhoto),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 20, color: Colors.red.shade400),
              const SizedBox(width: 12),
              Text(s.clearCanvas),
            ],
          ),
        ),
      ],
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
          final fullW =
              (available.width - _kCanvasPad * 2).clamp(1.0, double.infinity);
          final fullH =
              (available.height - _kCanvasPad * 2).clamp(1.0, double.infinity);
          // Форму снимаем ОДИН раз за заход и держим её дальше: рисунок
          // хранится в долях, поэтому любая другая форма его растягивает.
          // Раньше форма менялась вместе с областью — панель открылась или
          // телефон повернули, и круг превращался в блин.
          final r = _freeRatio ??= fullW / fullH;
          var w = fullW;
          var h = w / r;
          if (h > fullH) {
            h = fullH;
            w = h * r;
          }
          sheetW = w;
          sheetH = h;
          sheetLeft = (available.width - w) / 2;
          sheetTop = (available.height - h) / 2;
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
                        selection: _selectionNotifier,
                        bgColor: _bgColor,
                        background: _background,
                        gridColor: _isPixel ? null : _sheetGridColor,
                        pixelCols: _isPixel ? _pxCols : null,
                        pixelRows: _isPixel ? _pxRows : null,
                        showPixelGrid: _showPixelGrid,
                        strokes: _strokesNotifier,
                        currentPoints: _currentPoints,
                        symmetry: _symmetry,
                        symmetrySectors: _symmetrySectors,
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

  /// Лист приезжает снизу, а не появляется рывком: холст при этом ужимается,
  /// и без анимации кажется, что рисунок дёрнулся.
  Widget _buildBottomToolbar(AppStrings s, AppTheme t) {
    return AnimatedSize(
      duration: Motion.block,
      curve: Motion.emphasized,
      alignment: Alignment.topCenter,
      child: _toolsOpen
          ? _toolsSheet(s, t)
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _toolsSheet(AppStrings s, AppTheme t) {
    return DrawToolsSheet(
      tool: _panelTool,
      color: _activeColor,
      width: _strokeWidth,
      minWidth: 1,
      maxWidth: 40,
      palette: _kPanelPalette,
      fill: t.fillColor,
      onFill: AppThemes.onColor(t.fillColor, mode: t.brightness),
      labelThickness: s.strokeThickness,
      labelColor: s.colorLabel,
      // На пиксельном холсте выделения в панели нет: оно двигает нарисованное
      // как свободную фигуру, а клетка обязана лежать в сетке.
      tools: quickToolsFor(_quickTools, pixel: _isPixel),
      toolLabels: {
        DrawQuickTool.brush: s.brush,
        DrawQuickTool.eraser: s.eraser,
        DrawQuickTool.fill: s.fillBg,
        DrawQuickTool.shapes: s.drawShapes,
        DrawQuickTool.layers: s.drawLayers,
        DrawQuickTool.image: s.addPhoto,
        DrawQuickTool.palm: s.palmTool,
        DrawQuickTool.select: s.selectTool,
        DrawQuickTool.background: s.drawBackgrounds,
        DrawQuickTool.clear: s.clearCanvas,
        DrawQuickTool.replay: s.drawReplay,
      },
      onTool: _onPanelTool,
      onWidth: (v) => setState(() => _strokeWidth = v),
      onColor: _applyPickedColor,
      onMoreColors: _showColorPicker,
      onEyedropper: () {
        // Пипетка работает по холсту, поэтому лист уходит с дороги.
        setState(() => _toolsOpen = false);
        unawaited(_armEyedropper());
      },
      eyedropperLabel: s.eyedropper,
      onBrushSettings: _openBrushSheet,
      brushSettingsLabel: s.brushSettings,
      closeLabel: s.close,
      side: _layout == DrawLayout.sidePanel,
      symmetryOn: _symmetry != SymmetryMode.none,
      onClose: () => setState(() => _toolsOpen = false),
    );
  }

  /// Значок пузыря. Ладонь живёт в меню шапки, кнопки в листе у неё нет — но
  /// пузырь обязан показывать то, что холст делает на самом деле, иначе рука
  /// двигает лист, а значок обещает кисть.
  IconData get _bubbleIcon => _activeTool == DrawTool.palm
      ? Icons.pan_tool_rounded
      : DrawToolsSheet.icons[_panelTool] ?? Icons.brush_rounded;

  /// Что показывает пузырь: инструмент холста, приведённый к шести кнопкам
  /// листа. Фигуры (линия, прямоугольник, круг, треугольник) прячутся за одной
  /// кнопкой — на холсте важен не вид фигуры, а то, что рисуют не кистью.
  DrawQuickTool get _panelTool => switch (_activeTool) {
        DrawTool.palm => DrawQuickTool.palm,
        DrawTool.select => DrawQuickTool.select,
        DrawTool.eraser => DrawQuickTool.eraser,
        DrawTool.fill => DrawQuickTool.fill,
        DrawTool.line ||
        DrawTool.rect ||
        DrawTool.circle ||
        DrawTool.triangle =>
          DrawQuickTool.shapes,
        DrawTool.image => DrawQuickTool.image,
        _ => DrawQuickTool.brush,
      };

  void _onPanelTool(DrawQuickTool tool) {
    switch (tool) {
      case DrawQuickTool.brush:
        _selectTool(DrawTool.brush);
      case DrawQuickTool.eraser:
        _selectTool(DrawTool.eraser);
      case DrawQuickTool.fill:
        _selectTool(DrawTool.fill);
      case DrawQuickTool.shapes:
        _openShapesSheet();
      case DrawQuickTool.layers:
        _openLayersSheet();
      case DrawQuickTool.image:
        unawaited(_pickAndAddImage());
      case DrawQuickTool.palm:
        _selectTool(DrawTool.palm);
      case DrawQuickTool.select:
        _selectTool(DrawTool.select);
        unawaited(_maybeShowSelectHint());
      case DrawQuickTool.background:
        _openBackgroundSheet();
      case DrawQuickTool.clear:
        _confirmClear();
      case DrawQuickTool.replay:
        _openReplay();
    }
  }

  /// Настройки самой линии: плавность, ровные фигуры, симметрия.
  ///
  /// Живут за кнопкой в строке «Толщина», а не в ряду инструментов: ряд по
  /// макету держит ровно шесть кнопок, и седьмая ломала бы его на узком
  /// экране.
  void _openBrushSheet() {
    final s = LocaleService.current;
    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          void pick(SymmetryMode mode) {
            HapticFeedback.selectionClick();
            setSheet(() {});
            setState(() => _symmetry = mode);
            unawaited(_saveBrushPrefs());
          }

          return SheetScaffold(
            title: s.brushSettings,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.brushSmoothing,
                    style: ProfileTheme.sectionLabel(cs).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    value: _smoothing,
                    max: 0.8,
                    divisions: 8,
                    label: '${(_smoothing * 100).round()}%',
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _smoothing = v);
                    },
                    onChangeEnd: (_) => unawaited(_saveBrushPrefs()),
                  ),
                  Text(
                    s.brushSmoothingHint,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _quickShapes,
                    title: Text(
                      s.brushQuickShapes,
                      style: const TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      s.brushQuickShapesHint,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _quickShapes = v);
                      unawaited(_saveBrushPrefs());
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.symmetryTitle,
                    style: ProfileTheme.sectionLabel(cs).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (mode, label, icon) in <(SymmetryMode, String, IconData)>[
                        (SymmetryMode.none, s.symmetryNone, Icons.block_rounded),
                        (SymmetryMode.vertical, s.symmetryVertical,
                            Icons.flip_rounded),
                        (SymmetryMode.horizontal, s.symmetryHorizontal,
                            Icons.flip_rounded),
                        (SymmetryMode.quad, s.symmetryQuad, Icons.grid_view_rounded),
                        (SymmetryMode.radial, s.symmetryRadial,
                            Icons.blur_on_rounded),
                      ])
                        ChoiceChip(
                          selected: _symmetry == mode,
                          onSelected: (_) => pick(mode),
                          avatar: Icon(
                            icon,
                            size: 18,
                            // Горизонтальную ось рисует тот же значок,
                            // повёрнутый на четверть оборота.
                            color: _symmetry == mode
                                ? cs.onSecondaryContainer
                                : cs.onSurfaceVariant,
                          ),
                          label: Text(label),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  if (_symmetry == SymmetryMode.radial) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${s.symmetryRaysCount}: $_symmetrySectors',
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Slider(
                      value: _symmetrySectors.toDouble(),
                      min: 2,
                      max: 12,
                      divisions: 10,
                      label: '$_symmetrySectors',
                      onChanged: (v) {
                        setSheet(() {});
                        setState(() => _symmetrySectors = v.round());
                      },
                      onChangeEnd: (_) => unawaited(_saveBrushPrefs()),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadBrushPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final name = p.getString(UiPrefs.kBrushSymmetry);
    setState(() {
      _quickTools = parseQuickTools(p.getString(UiPrefs.kDrawQuickTools));
      _smoothing = p.getDouble(UiPrefs.kBrushSmoothing) ?? kDefaultSmoothing;
      _quickShapes = p.getBool(UiPrefs.kBrushQuickShapes) ?? true;
      _symmetrySectors = p.getInt(UiPrefs.kBrushSymmetrySectors) ?? 6;
      _symmetry = SymmetryMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => SymmetryMode.none,
      );
    });
  }

  Future<void> _saveBrushPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(UiPrefs.kBrushSmoothing, _smoothing);
    await p.setBool(UiPrefs.kBrushQuickShapes, _quickShapes);
    await p.setString(UiPrefs.kBrushSymmetry, _symmetry.name);
    await p.setInt(UiPrefs.kBrushSymmetrySectors, _symmetrySectors);
  }

  /// Какой фигурой рисовать. В панели у фигур одна кнопка, вид выбирают тут.
  void _openShapesSheet() {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: s.drawShapes,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    for (final (icon, tool, label) in <(IconData, DrawTool, String)>[
                      (Icons.remove_rounded, DrawTool.line, s.drawLine),
                      (Icons.crop_square_rounded, DrawTool.rect, s.drawRect),
                      (Icons.circle_outlined, DrawTool.circle, s.drawCircle),
                      (
                        Icons.change_history_rounded,
                        DrawTool.triangle,
                        s.drawTriangle
                      ),
                    ]) ...[
                      Expanded(
                        child: Tooltip(
                          message: label,
                          child: Material(
                            color: _activeTool == tool
                                ? cs.primaryContainer
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                _selectTool(tool);
                                setSheet(() {});
                                Navigator.pop(ctx);
                              },
                              child: SizedBox(
                                height: 56,
                                child: Icon(
                                  icon,
                                  color: _activeTool == tool
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (tool != DrawTool.triangle) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.fillShapes),
                  value: _fillShapes,
                  onChanged: (v) {
                    setState(() => _fillShapes = v);
                    setSheet(() {});
                  },
                ),
              ],
            ),
          ),
        ),
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

  /// Показ того, как рисунок появлялся. Записи не ведём: порядок мазков уже
  /// лежит в базе, повтор просто прокручивает его.
  void _openReplay() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrawReplayScreen(
          strokes: List<DrawStroke>.unmodifiable(_visibleStrokes),
          theme: widget.theme,
          background: _background,
          // Свободный холст листа не имеет: показываем его в квадрате, где
          // доли точек и так лежат по 0…1.
          sheetRatio: _sheetRatio ?? 1.0,
          pixelCols: _isPixel ? _pxCols : null,
          pixelRows: _isPixel ? _pxRows : null,
        ),
      ),
    );
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

  /// Предлагает открыть платный фон холста рекламой до конца суток.
  Future<void> _offerCanvasBgTrial(
    CanvasBackground bg,
    StateSetter refreshSheet,
  ) async {
    final s = LocaleService.current;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => SheetScaffold(
        title: s.adTrialCanvasBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: Text(s.adTrialCanvasBg),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(s.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    final uid = PocketBaseService().userId ?? '';
    final earned = await _rewardedAd.show(uid: uid);
    unawaited(_rewardedAd.load());
    if (!earned) return;

    final res =
        await widget.userData.takeAdGrant(AdGrantKind.canvasBg, bg.name);
    if (!mounted) return;
    if (res.kind == AdGrantOutcome.ok) {
      refreshSheet(() {});
      messenger.showSnackBar(SnackBar(
        content: Text(s.adTrialTakenToday),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(s.adRewardLimitReached),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Widget _backgroundTile(
    CanvasBackground bg,
    ColorScheme cs,
    StateSetter refreshSheet,
  ) {
    final selected = _background == bg;
    final s = LocaleService.current;
    // Платные фоны набора открывает Togetherly+ (или поштучная покупка), а
    // ещё — проба за рекламу: она живёт до конца суток и владением не
    // становится.
    final trial = widget.userData.adGrants
        .activeFor(AdGrantKind.canvasBg, DateTime.now());
    final unlocked = PlusAccess.ownsBackground(
          id: bg,
          plus: PlusService.instance.active,
          owned: widget.userData.ownedFeatures,
        ) ||
        trial?.id == bg.name;

    return GestureDetector(
      onTap: () {
        if (!unlocked) {
          // Там, где Togetherly+ не существует, закрытых фонов в списке нет —
          // а если тап всё же случился, молча ничего не делаем.
          if (!PlusService.instance.visible) return;
          // Закрытый фон не выбирается молча: сперва предлагаем открыть его
          // рекламой на сегодня, и только потом — витрину Togetherly+.
          if (widget.userData.adGrants
              .canTake(AdGrantKind.canvasBg, DateTime.now())) {
            _offerCanvasBgTrial(bg, refreshSheet);
            return;
          }
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

  /// Контрастный цвет поверх акцента: у светлых акцентов белый текст тонет.
  Color _onPrimaryColor(AppTheme t) =>
      t.primary.computeLuminance() > 0.55 ? const Color(0xFF16161A) : Colors.white;
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
    // Порог и вид линии — в pixelGridStyle (под тестами). Прежние жёсткие «6
    // пикселей на клетку» отсекали сетку на 64×80: на телефоне клетка там
    // около 4,4 dp, и человек видел пустой лист без клеток.
    final style = pixelGridStyle(cw < ch ? cw : ch);
    if (!style.visible) return;
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, style.opacity)
      ..strokeWidth = style.strokeWidth;
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

/// Состав рисунка и ревизия его основы, одним значением.
///
/// Ревизия двигается на всё, кроме дописывания штрихов в конец: по ней слой
/// готовых штрихов понимает, годится ли накопленная картинка (см.
/// `StrokeLayerCache`).
class StrokesSnapshot {
  const StrokesSnapshot(this.list, this.revision);

  final List<DrawStroke> list;
  final int revision;
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
  /// Состав рисунка: приезжает каналом, чтобы новый штрих не перестраивал экран.
  final ValueListenable<StrokesSnapshot> strokes;
  final List<DrawPoint> currentPoints;

  /// Симметрия текущего мазка. Копии рисуются здесь же, на лету: в базу они
  /// уходят только при отпускании пальца, а видеть их надо сразу.
  final SymmetryMode symmetry;
  final int symmetrySectors;

  final int currentColorValue;
  final double currentStrokeWidth;
  final bool currentIsEraser;
  final bool currentIsFilledShape;
  final DrawShapeType? currentShapeType;
  final ValueNotifier<List<DrawStroke>> partnerNotifier;
  final Size canvasSize;

  /// Выделенная фигура — рамку рисует painter сцены.
  final ValueListenable<DrawStroke?>? selection;
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
    required this.symmetry,
    required this.symmetrySectors,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.currentIsFilledShape,
    required this.currentShapeType,
    required this.partnerNotifier,
    required this.canvasSize,
    this.selection,
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

  /// Растры картинок-штрихов: заливок ведром и вставленных фотографий.
  ///
  /// Рисует их тот же painter, что и мазки, — только так работают порядок,
  /// слои и ластик (25.08.2026). Пока растр едет, картинки на холсте нет.
  final CanvasImageCache _images = CanvasImageCache();

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
      widget.strokes,
      // Рамка выделения живёт своим каналом: она меняется на каждое движение
      // пальца, а состав рисунка при этом не трогается.
      if (widget.selection != null) widget.selection!,
      _images,
    ]);
    _images.addListener(_onImageReady);
    widget.strokes.addListener(_onStrokes);
  }

  @override
  void dispose() {
    widget.strokes.removeListener(_onStrokes);
    _images.removeListener(_onImageReady);
    _images.dispose();
    _layer.dispose();
    super.dispose();
  }

  /// Приехавшая картинка ломает готовый слой: он собирался, когда её ещё не
  /// было, и без сброса дыра осталась бы в кэше до следующей пересборки.
  void _onImageReady() => _layer.invalidate();

  /// Ревизия основы, на которой в последний раз подчищали растры.
  int _sweptRevision = -1;

  void _onStrokes() {
    // Растры держим только для тех картинок, что сейчас в рисунке: удалённая
    // заливка иначе занимала бы память до выхода с холста.
    //
    // Перебор идёт ТОЛЬКО когда ревизия основы сдвинулась, то есть при отмене,
    // замене или пересортировке. Пока штрихи дописываются в конец, картинка
    // пропасть не может, а проход по всему списку на каждую клетку пиксельной
    // раскраски — это ровно та квадратичная работа, из-за которой холст уже
    // дёргался.
    final snapshot = widget.strokes.value;
    if (snapshot.revision == _sweptRevision) return;
    _sweptRevision = snapshot.revision;
    final keys = <String>[];
    for (final s in snapshot.list) {
      if (!s.isImageStroke) continue;
      final key = CanvasImageCache.sourceOf(
        s,
        localPath: widget.localImagePaths[s.id],
      );
      if (key != null) keys.add(key);
    }
    _images.retainOnly(keys);
  }

  @override
  void didUpdateWidget(covariant _CanvasScene old) {
    super.didUpdateWidget(old);
    if (old.repaintNotifier != widget.repaintNotifier ||
        old.partnerNotifier != widget.partnerNotifier ||
        old.selection != widget.selection ||
        old.strokes != widget.strokes) {
      old.strokes.removeListener(_onStrokes);
      widget.strokes.addListener(_onStrokes);
      // Канал рамки повторяется и здесь: забудешь — выделение перестанет
      // перерисовываться после первой же пересборки сцены, и фигура поедет
      // без рамки.
      _repaint = Listenable.merge([
        widget.repaintNotifier,
        widget.partnerNotifier,
        widget.strokes,
        if (widget.selection != null) widget.selection!,
        _images,
      ]);
      _onStrokes();
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
    // Ничего за краем холста не видно: у рисунков, сделанных до обрезки точек на
    // вводе, штрихи уходят за лист, и заливка вслед за ними расползалась по
    // столу. Клип чинит и их, не переписывая сами штрихи. Клип живёт на самом
    // Container: ему нужна decoration вместо color, иначе clipBehavior молчит.
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: widget.bgColor),
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
                strokes: widget.strokes,
                layer: _layer,
                pixelCols: widget.pixelCols,
                pixelRows: widget.pixelRows,
                currentPoints: widget.currentPoints,
                symmetry: widget.symmetry,
                symmetrySectors: widget.symmetrySectors,
                currentColorValue: widget.currentColorValue,
                currentStrokeWidth: widget.currentStrokeWidth,
                currentIsEraser: widget.currentIsEraser,
                currentIsFilledShape: widget.currentIsFilledShape,
                currentShapeType: widget.currentShapeType,
                partnerNotifier: widget.partnerNotifier,
                canvasSize: widget.canvasSize,
                selection: widget.selection,
                images: _images,
                localImagePaths: widget.localImagePaths,
                selectedImageId: widget.selectedImageId,
                repaint: _repaint,
              ),
            ),
          ),
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
}

//  _DrawingPainter

/// Сколько свежих штрихов рисуем поверх слоя, прежде чем свернуть его заново.
const int _tailLimit = 48;

class _DrawingPainter extends CustomPainter {
  /// Состав рисунка каналом: painter берёт его в момент отрисовки, поэтому
  /// новый штрих не заставляет пересобирать дерево виджетов.
  final ValueListenable<StrokesSnapshot> strokes;
  final List<DrawPoint> currentPoints;

  /// Симметрия текущего мазка. Копии рисуются здесь же, на лету: в базу они
  /// уходят только при отпускании пальца, а видеть их надо сразу.
  final SymmetryMode symmetry;
  final int symmetrySectors;

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

  /// Растры картинок-штрихов: заливок и вставленных фото (живут там же).
  final CanvasImageCache images;

  /// Свои только что сделанные картинки: id → путь на диске.
  final Map<String, String> localImagePaths;

  /// Какую картинку человек взял инструментом «Фото»: вокруг неё рамка.
  final String? selectedImageId;

  /// Что выделено инструментом «Выделение»: вокруг него рисуется рамка с
  /// ручками. Рисуем её здесь, в координатах холста, — иначе рамка разъезжается
  /// с рисунком при повороте и масштабе листа.
  final ValueListenable<DrawStroke?>? selection;


  _DrawingPainter({
    required this.strokes,
    required this.layer,
    required this.images,
    this.localImagePaths = const {},
    this.selectedImageId,
    this.selection,
    this.pixelCols,
    this.pixelRows,
    required this.currentPoints,
    required this.symmetry,
    required this.symmetrySectors,
    required this.currentColorValue,
    required this.currentStrokeWidth,
    required this.currentIsEraser,
    required this.currentIsFilledShape,
    required this.currentShapeType,
    required this.partnerNotifier,
    required this.canvasSize,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// Рамка выделения: тонкий контур и восемь ручек по краям.
  void _paintSelection(Canvas canvas, Size size) {
    final stroke = selection?.value;
    if (stroke == null || stroke.points.isEmpty) return;
    final b = strokeBounds(stroke, size).inflate(kSelectionPad);

    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF2F6BFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(b, const Radius.circular(4)),
      frame,
    );

    final knob = Paint()..color = const Color(0xFFFFFFFF);
    final knobEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF2F6BFF);
    for (final p in [
      b.topLeft, b.topCenter, b.topRight,
      b.centerLeft, b.centerRight,
      b.bottomLeft, b.bottomCenter, b.bottomRight,
    ]) {
      canvas.drawCircle(p, 6, knob);
      canvas.drawCircle(p, 6, knobEdge);
    }

    // Ручка поворота: кружок на ножке над рамкой со стрелкой по дуге внутри.
    final spin = b.topCenter.translate(0, -kSelectionSpinGap);
    canvas.drawLine(b.topCenter, spin.translate(0, 8), knobEdge);
    canvas.drawCircle(spin, 8.5, knob);
    canvas.drawCircle(spin, 8.5, knobEdge);
    canvas.drawArc(
      Rect.fromCircle(center: spin, radius: 4),
      -math.pi * 0.85,
      math.pi * 1.5,
      false,
      knobEdge,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final snapshot = strokes.value;
    final strokesRevision = snapshot.revision;
    // Картинки идут ОДНИМ списком с мазками: заливка ведром — такая же краска,
    // и лежать она обязана там, где её положили. Пока их рисовали виджетами
    // поверх холста, пятно закрывало всё, что нарисовано позже, на любом слое.
    final strokeList = snapshot.list;

    // Ластик снимает краску (`BlendMode.dstOut`), а значит рисовать штрихи
    // надо в своём слое: иначе стирание выест и фон холста — сетку, узор,
    // сам лист. Слой заводим только когда ластик в рисунке есть: saveLayer
    // на весь холст стоит кадра, и платить за него всем незачем.
    final needsLayer = currentIsEraser ||
        strokeList.any((s) => s.isEraser) ||
        partnerNotifier.value.any((s) => s.isEraser);
    if (needsLayer) canvas.saveLayer(Offset.zero & size, Paint());

    // Закоммиченные штрихи выкладываем готовым слоем. Слой держит ПРЕФИКС
    // состава: пока штрихи только дописываются в конец, картинка не трогается
    // вовсе, а свежие рисуются поверх неё. Раньше ключом было число штрихов, и
    // каждая новая клетка пиксельной раскраски пересобирала весь рисунок — на
    // холсте в тысячу штрихов это и есть «дёргается».
    //
    // Разделять слои по-настоящему нельзя: ластик работает по общему полотну.
    // Поэтому картинка одна, меняется только цена кадра.
    var picture = layer.prefixFor(
      revision: strokesRevision,
      available: strokeList.length,
      size: size,
    );
    var painted = picture == null ? 0 : layer.prefixCount;

    // Хвост длиннее порога — дешевле свернуть его в слой, чем рисовать каждый
    // кадр. Порог небольшой: полсотни путей рисуются за доли миллисекунды.
    if (picture != null && strokeList.length - painted > _tailLimit) {
      picture = null;
      painted = 0;
    }

    if (picture == null) {
      // Слой доходит ровно до первой ещё не приехавшей картинки: запиши её
      // отсутствие в картинку — и дыра осталась бы там до пересборки.
      final ready = _readyPrefix(strokeList);
      final recorder = ui.PictureRecorder();
      final buffer = Canvas(recorder);
      paintStrokeRange(
        buffer,
        strokeList,
        size,
        end: ready,
        pixelCols: pixelCols,
        pixelRows: pixelRows,
        imageOf: _imageOf,
      );
      picture = recorder.endRecording();
      layer.save(
        picture,
        revision: strokesRevision,
        size: size,
        prefixCount: ready,
      );
      painted = ready;
    }
    canvas.drawPicture(picture);

    // Хвост: штрихи, которых в слое ещё нет.
    paintStrokeRange(
      canvas,
      strokeList,
      size,
      start: painted,
      pixelCols: pixelCols,
      pixelRows: pixelRows,
      imageOf: _imageOf,
    );

    if (currentPoints.isNotEmpty) {
      final drafts = <List<DrawPoint>>[
        currentPoints,
        ...mirrorStroke(
          currentPoints,
          symmetry,
          sectors: symmetrySectors,
          aspect: size.height == 0 ? 1 : size.width / size.height,
        ),
      ];
      for (final points in drafts) {
        if (currentShapeType != null && points.length >= 2) {
          _drawShape(
            canvas,
            points,
            currentColorValue,
            currentStrokeWidth,
            currentShapeType!,
            size,
            isFilledShape: currentIsFilledShape,
          );
        } else if (currentShapeType == null) {
          _drawStroke(
            canvas,
            points,
            currentColorValue,
            currentStrokeWidth,
            currentIsEraser,
            size,
          );
        }
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

    if (needsLayer) canvas.restore();

    // Рамка рисуется ПОСЛЕ восстановления слоя: внутри него ластик съел бы и
    // её вместе с краской.
    _paintSelection(canvas, size);
    _paintImageSelection(canvas, size, strokeList);
  }

  /// Растр картинки-штриха, если он уже приехал.
  ui.Image? _imageOf(DrawStroke stroke) =>
      images.imageFor(stroke, localPath: localImagePaths[stroke.id]);

  /// До какого места слой можно свернуть в картинку: до первой картинки,
  /// растра которой ещё нет.
  int _readyPrefix(List<DrawStroke> strokes) {
    for (var i = 0; i < strokes.length; i++) {
      final s = strokes[i];
      if (s.isImageStroke && _imageOf(s) == null) return i;
    }
    return strokes.length;
  }

  /// Рамка вокруг картинки, взятой инструментом «Фото». Раньше её рисовал сам
  /// виджет картинки; теперь картинки живут в холсте, и рамка вместе с ними.
  void _paintImageSelection(Canvas canvas, Size size, List<DrawStroke> list) {
    final id = selectedImageId;
    if (id == null) return;
    for (final s in list) {
      if (s.id != id || !s.isImageStroke) continue;
      final w = (s.imageWidth ?? 0.5) * size.width;
      final h = (s.imageHeight ?? 0.5) * size.height;
      if (w <= 0 || h <= 0) return;
      final cx = (s.imageX ?? 0.5) * size.width;
      final cy = (s.imageY ?? 0.5) * size.height;
      final frame = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF42A5F5);
      canvas.save();
      canvas.translate(cx, cy);
      final rot = s.imageRotation ?? 0.0;
      if (rot != 0) canvas.rotate(rot);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(4),
        ),
        frame,
      );
      canvas.restore();
      return;
    }
  }

  /// Тонкие обёртки над общей отрисовкой (`widgets/draw/stroke_painting.dart`):
  /// сам код рисования живёт там, потому что его же показывает повтор.
  void _drawShape(
    Canvas canvas,
    List<DrawPoint> points,
    int colorValue,
    double strokeWidth,
    DrawShapeType shapeType,
    Size size, {
    double alpha = 1.0,
    required bool isFilledShape,
  }) =>
      paintShape(canvas, points, colorValue, strokeWidth, shapeType, size,
          alpha: alpha,
          isFilledShape: isFilledShape,
          // Сетку передаём так же, как штрихам: без неё фигура рисовалась
          // гладкой кривой поверх клеток пиксельного холста.
          pixelCols: pixelCols,
          pixelRows: pixelRows);

  void _drawStroke(
    Canvas canvas,
    List<DrawPoint> points,
    int colorValue,
    double strokeWidth,
    bool isEraser,
    Size size, {
    double alpha = 1.0,
  }) =>
      paintStroke(canvas, points, colorValue, strokeWidth, isEraser, size,
          alpha: alpha, pixelCols: pixelCols, pixelRows: pixelRows);

  @override
  bool shouldRepaint(covariant _DrawingPainter old) =>
      old.strokes != strokes ||
      old.currentPoints != currentPoints ||
      old.currentColorValue != currentColorValue ||
      old.currentStrokeWidth != currentStrokeWidth ||
      old.currentIsEraser != currentIsEraser ||
      old.currentShapeType != currentShapeType ||
      old.symmetry != symmetry ||
      old.symmetrySectors != symmetrySectors ||
      old.canvasSize != canvasSize ||
      old.selectedImageId != selectedImageId ||
      old.localImagePaths != localImagePaths ||
      old.pixelCols != pixelCols ||
      old.pixelRows != pixelRows;
}

/// Одна правка формы: что за фигура, как выглядела до жеста и после.
///
/// Хранится точками, а не готовым штрихом: за время между правкой и отменой
/// у штриха мог смениться слой или цвет, и возвращать его целиком значило бы
/// откатывать заодно и это.
class _ShapeEdit {
  const _ShapeEdit({
    required this.id,
    required this.before,
    required this.after,
    required this.seq,
  });

  final String id;
  final List<DrawPoint> before;
  final List<DrawPoint> after;

  /// Номер по общей шкале действий холста.
  final int seq;
}
