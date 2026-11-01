import 'dart:async';
import 'storage_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dict_strings.dart' show ruEn;
import '../models/cloud_mascot.dart';
import '../models/mascot.dart';
import 'mascot/cloud_mascot_view.dart';
import '../screens/tu_wardrobe_screen.dart';
import '../screens/home/home_bottom_nav.dart' show kHomeBottomNavHeight;
import '../utils/mascot_bounds.dart';
import '../services/locale_service.dart';
import '../models/mascot_anim.dart';
import '../models/mascot_sleep.dart';
import '../services/catalog_service.dart';
import '../services/mascot_service.dart';
import 'mascot/pixel_mascot_view.dart';
import '../theme/app_theme.dart';
import '../services/offline/media_view_cache.dart';

const String _kHiddenKey = 'mascot_hidden';

/// Чьим настроением красится облачко: партнёра (по умолчанию) или своим.
const String _kCloudMineKey = 'cloud_mood_mine';
const String _kOnboardingKey = 'mascot_onboarding_shown';

/// Global notifier for the mascot's hidden state.
/// Listen to this in other widgets (e.g. home screen mascot row)
/// to react when the user hides/shows the floating mascot.
final ValueNotifier<bool> mascotHiddenNotifier = ValueNotifier<bool>(false);

/// Часы серии тапов по Ту. Тест подставляет поддельные: настоящие идут мимо
/// поддельного времени теста, и два тапа склеивались бы в один.
@visibleForTesting
DateTime Function() mascotTapClock = DateTime.now;

/// Floating mascot overlay rendered inside the home screen Stack.
/// Draggable + pinch-to-scale. Position and scale sync via [MascotService].
class ActiveMascotWidget extends StatefulWidget {
  final MascotService mascotService;
  final AppTheme theme;
  final VoidCallback onOpenGallery;

  /// Окно ночной сцены персонажа: у каждого своё, задаётся в настройках.
  final SleepWindow Function(String mascotId) sleepOf;

  /// Сегодняшнее настроение (id) — своё при `mine`, иначе партнёра. Облачко
  /// красится им; остальным маскотам не нужно.
  final String? Function(bool mine)? moodOf;

  const ActiveMascotWidget({
    super.key,
    required this.mascotService,
    required this.theme,
    required this.onOpenGallery,
    required this.sleepOf,
    this.moodOf,
  });

  @override
  State<ActiveMascotWidget> createState() => _ActiveMascotWidgetState();
}

class _ActiveMascotWidgetState extends State<ActiveMascotWidget>
    with TickerProviderStateMixin {
  bool _hidden = false;
  bool _onboardingShown = false;

  // Gesture tracking
  Offset _position = Offset.zero; // screen-space position of mascot center
  double _scale = 1.0;

  /// Границы размера маскота. Те же, что у щипка двумя пальцами: настройка
  /// одна, и разъехаться они не должны.
  static const double _kMinScale = 1.0;
  static const double _kMaxScale = 3.0;
  bool _positionInitialized = false;

  // Pinch state
  double _baseScale = 1.0;
  bool _isInteracting = false;

  // Push-debounce for Firestore writes
  Timer? _syncTimer;

  /// Серия тапов по Ту ([MascotTapCombo]): меню, кувырок, раздувание тучей
  /// и дождик. Что делать, решается, когда тапы прекратились
  /// ([kMascotTapChain] тишины).
  final MascotTapCombo _combo = MascotTapCombo();
  Timer? _menuTimer;

  /// Насколько Ту раздуло тапами: 0 — обычный, 1 — туча перед дождём.
  double _fed = 0;

  /// Полёт после броска: Ту летит по инерции и отскакивает от краёв.
  Ticker? _flight;
  Offset _flightVelocity = Offset.zero;
  Duration _flightLast = Duration.zero;
  int _flightHits = 0;

  /// Удар о стену: когда был (время полёта), насколько сильный и о какую
  /// стену — Ту сплющивается к ней и пружинит обратно ([mascotSquash]).
  Duration? _hitAt;
  double _hitStrength = 0;

  /// Кружок касания в точке, куда ткнули: точка, пока палец прижат, и
  /// кольцо, которое расходится, когда его отпустили. Раньше кружок был
  /// запечён в сцену и всегда стоял на макушке.
  Offset? _touchPoint;
  bool _touchHeld = false;
  late final AnimationController _ringCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  Alignment _hitSide = Alignment.bottomCenter;
  ({double flat, double wide}) _squash = (flat: 1.0, wide: 1.0);

  // Entrance animation
  late AnimationController _entranceCtrl;
  late Animation<double> _entranceAnim;

  MascotService get _svc => widget.mascotService;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entranceAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.elasticOut,
    );

    _loadPrefs();
    unawaited(_reactToStreak());
    _svc.addListener(_onServiceChanged);
    mascotHiddenNotifier.addListener(_onExternalVisibilityChanged);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _syncTimer?.cancel();
    _menuTimer?.cancel();
    _flight?.dispose();
    _ringCtrl.dispose();
    _svc.removeListener(_onServiceChanged);
    mascotHiddenNotifier.removeListener(_onExternalVisibilityChanged);
    super.dispose();
  }

  /// Called when another widget changes [mascotHiddenNotifier] (e.g. home row).
  void _onExternalVisibilityChanged() {
    final shouldHide = mascotHiddenNotifier.value;
    if (shouldHide != _hidden) {
      setState(() => _hidden = shouldHide);
      if (!shouldHide && _positionInitialized) {
        _entranceCtrl.forward(from: 0);
      }
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getBool(_kHiddenKey) ?? false;
    if (mounted) {
      setState(() {
        _hidden = hidden;
        _cloudMine = prefs.getBool(_kCloudMineKey) ?? false;
        _onboardingShown = prefs.getBool(_kOnboardingKey) ?? false;
      });
    }
    mascotHiddenNotifier.value = hidden;
  }

  void _onServiceChanged() {
    final state = _svc.state;
    if (!mounted) return;

    if (!_positionInitialized && mounted) {
      // First sync: adopt group position/scale
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final size = MediaQuery.of(context).size;
        setState(() {
          _position = Offset(
            state.positionX * size.width,
            state.positionY * size.height,
          );
          _scale = state.scale.clamp(_kMinScale, _kMaxScale);
          _positionInitialized = true;
        });
        _entranceCtrl.forward(from: 0);
        if (!_onboardingShown) _showOnboarding();
      });
      return;
    }

    if (_positionInitialized && !_isInteracting) {
      final size = MediaQuery.of(context).size;
      final nextPosition = Offset(
        state.positionX * size.width,
        state.positionY * size.height,
      );
      final nextScale = state.scale.clamp(_kMinScale, _kMaxScale);
      final shouldUpdatePosition =
          (_position.dx - nextPosition.dx).abs() > 0.5 ||
          (_position.dy - nextPosition.dy).abs() > 0.5;
      final shouldUpdateScale = (_scale - nextScale).abs() > 0.01;

      if (shouldUpdatePosition || shouldUpdateScale) {
        setState(() {
          _position = nextPosition;
          _scale = nextScale;
          _clampPosition();
        });
        return;
      }
    }

    setState(() {});
  }

  void _showOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingKey, true);
    if (!mounted) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 120,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, child) => Opacity(opacity: v, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  LocaleService.current.groupMascotBanner,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      entry.remove();
      if (mounted) setState(() => _onboardingShown = true);
    });
  }

  // ── Gestures ─────────────────────────────────────────────────────────────

  /// Сколько пальцем прошли за жест — по нему тап отличается от перетаскивания.
  double _travel = 0;

  /// Смещение, накопленное до порога: применяем разом, когда стало ясно, что
  /// это перетаскивание.
  Offset _pendingDelta = Offset.zero;

  /// Когда жест начался.
  DateTime? _gestureStartedAt;

  /// Лист уже открыт — второй раз не открываем (тап может прийти и с арены
  /// жестов, и из нашей проверки в конце жеста).
  bool _menuOpen = false;

  /// Насколько палец может уехать, чтобы жест всё ещё считался тапом.
  /// Правило целиком — в `mascotGestureIsTap` (под тестами).
  static const double _kTapSlop = 12;

  void _onScaleStart(ScaleStartDetails d) {
    // Поймали пальцем в полёте — летит дальше уже за пальцем.
    if (_flight != null) {
      _flight!.dispose();
      _flight = null;
      _hitAt = null;
      _squash = (flat: 1.0, wide: 1.0);
    }
    _isInteracting = true;
    _baseScale = _scale;
    _travel = 0;
    _pendingDelta = Offset.zero;
    _gestureStartedAt = DateTime.now();
    _setAnim(MascotAnimState.grab);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Тап по маскоту не открывал ничего: `onScaleUpdate` двигает его на любое
    // микродвижение пальца, распознаватель масштаба забирает жест себе, и
    // `onTap` до арены не доживает. Жалоба: «тыкаешь — ничего, а перемещать
    // можно». Поэтому пока палец не ушёл дальше порога, маскот стоит на месте,
    // а короткое касание в конце жеста открывает меню.
    _travel += d.focalPointDelta.distance;
    final dragging = _travel > _kTapSlop || (d.scale - 1.0).abs() > 0.02;
    if (!dragging) {
      _pendingDelta += d.focalPointDelta;
      return;
    }

    setState(() {
      // Нижняя граница — обычный размер: уменьшенного до точки маскота
      // потом не поймать пальцем, и вернуть его было нечем.
      _scale = (_baseScale * d.scale).clamp(_kMinScale, _kMaxScale);
      _position += _pendingDelta + d.focalPointDelta;
      _pendingDelta = Offset.zero;
      _clampPosition();
    });
    // Пальцем тянут или щиплют: маскот реагирует по-разному, поэтому одно
    // движение мы отличаем от другого по тому, менялся ли масштаб.
    final resizing = (d.scale - 1.0).abs() > 0.02;
    final moving = d.focalPointDelta.distance > 0.5;
    if (resizing) {
      _setAnim(MascotAnimState.resize);
    } else if (moving) {
      _setAnim(MascotAnimState.drag);
    }
    _scheduleSyncTimer();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _isInteracting = false;
    final started = _gestureStartedAt;
    final tap = started != null &&
        mascotGestureIsTap(
          travel: _travel,
          held: DateTime.now().difference(started),
          slop: _kTapSlop,
        );
    if (tap) {
      _tapped();
      return;
    }
    // Отпустили на ходу (не щипком): Ту летит дальше по инерции.
    final velocity = d.velocity.pixelsPerSecond;
    if (_isCloud && d.pointerCount <= 1 && mascotFlingWorth(velocity)) {
      _startFlight(velocity);
      return;
    }
    _setAnim(MascotAnimState.drop);
    _scheduleSync();
  }

  void _startFlight(Offset velocity) {
    _flight?.dispose();
    _flightVelocity = velocity;
    _flightLast = Duration.zero;
    _flightHits = 0;
    _setAnim(MascotAnimState.drag);
    _flight = createTicker(_flightTick)..start();
  }

  void _flightTick(Duration elapsed) {
    if (!mounted) return;
    final dt = ((elapsed - _flightLast).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _flightLast = elapsed;
    final media = MediaQuery.of(context);
    final half = 40.0 * _scale;
    final box = Rect.fromLTRB(
      half,
      media.viewPadding.top + half,
      media.size.width - half,
      media.size.height - media.viewPadding.bottom - kHomeBottomNavHeight - half,
    );
    if (box.width <= 0 || box.height <= 0) return _endFlight();
    final before = _flightVelocity;
    final step = mascotFlightStep(_position, _flightVelocity, dt, box);
    setState(() {
      _position = step.position;
      _flightVelocity = step.velocity;
      if (step.hit) {
        // Об стенку: прижимается к ней и сплющивается, сильнее на быстром.
        _hitAt = elapsed;
        _hitStrength = (before.distance / 1400).clamp(0.4, 1.0);
        // Прижимается к той стене, о которую ударился; в углу — к углу.
        _hitSide = Alignment(step.wall.dx, step.wall.dy);
      }
      final hitAt = _hitAt;
      _squash = hitAt == null
          ? (flat: 1.0, wide: 1.0)
          : mascotSquash(sinceHit: (elapsed - hitAt).inMicroseconds / 1e6, strength: _hitStrength);
    });
    if (step.hit) {
      _flightHits++;
      HapticFeedback.lightImpact();
    }
    final settled = _hitAt == null || elapsed - _hitAt! > const Duration(milliseconds: 600);
    if (_flightVelocity.distance < 60 && settled) _endFlight();
  }

  void _endFlight() {
    _flight?.dispose();
    _flight = null;
    _hitAt = null;
    if (mounted) setState(() => _squash = (flat: 1.0, wide: 1.0));
    // Бился о стены — приземляется оглушённым (спиральные глаза встряски),
    // а не довольным, как после обычного касания.
    if (_flightHits > 0) {
      _setAnim(MascotAnimState.live);
      CloudEvents.instance.fire(CloudEvent.shake);
    } else {
      _setAnim(MascotAnimState.drop);
    }
    _scheduleSync();
  }

  /// Текущая поза анимированного маскота. Разовые (подрос, обрадовался,
  /// приземлился) сами возвращают его к обычной жизни.
  MascotAnimState _anim = MascotAnimState.live;

  /// Облачко красится своим настроением, а не партнёра.
  bool _cloudMine = false;

  bool get _isCloud => _svc.activeMascot?.id == kCloudMascotId;

  /// Серия на прошлом показе — по ней и видно, что случилось за это время.
  static const String _kStreakKey = 'mascot_anim_last_streak';

  /// Сверяет серию с прошлым разом и играет подходящую сцену: выросла — рост,
  /// тот же день — радость, обнулилась — грусть. Состояние держим в prefs, а не
  /// в памяти: главную открывают заново после каждого убийства приложения.
  Future<void> _reactToStreak() async {
    final anim = CatalogService.instance.animById(_svc.activeMascot?.id);
    if (anim == null && !_isCloud) return;
    final streak = _svc.activeStreak;
    final prefs = await SharedPreferences.getInstance();
    final was = prefs.getInt(_kStreakKey);
    await prefs.setInt(_kStreakKey, streak);
    if (was == null || was == streak || !mounted) return;

    if (streak > was) {
      // Каждая третья отметка — рост, остальные просто радость: иначе маскот
      // растёт на глазах каждый день и ступени теряют смысл.
      _setAnim(streak % 3 == 0 ? MascotAnimState.grow : MascotAnimState.happy);
    } else if (streak == 0) {
      _setAnim(MascotAnimState.sad);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _setAnim(MascotAnimState.live);
      });
    }
  }

  void _setAnim(MascotAnimState s) {
    if (_anim == s || !mounted) return;
    setState(() => _anim = s);
  }

  void _clampPosition() {
    if (!mounted) return;
    final media = MediaQuery.of(context);
    _position = clampMascotPosition(
      _position,
      media.size,
      40.0 * _scale,
      top: media.viewPadding.top,
      bottom: media.viewPadding.bottom + kHomeBottomNavHeight,
    );
  }

  void _scheduleSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 300), _scheduleSync);
  }

  void _scheduleSync() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    _svc.updatePosition(
      x: (_position.dx / size.width).clamp(0.0, 1.0),
      y: (_position.dy / size.height).clamp(0.0, 1.0),
      scale: _scale,
    );
  }

  // ── Menu ─────────────────────────────────────────────────────────────────

  /// Касание по маскоту. У Ту второй тап вслед за первым — кувырок вместо
  /// меню; остальные маскоты открывают меню сразу.
  void _tapped() {
    if (!_isCloud) {
      _setAnim(MascotAnimState.live);
      _onTap();
      return;
    }
    _menuTimer?.cancel();
    switch (_combo.tap(mascotTapClock())) {
      case MascotTapStep.burst:
        // Десятый тап: Ту лопается на облачка и собирается обратно сам.
        setState(() => _fed = 0);
        CloudEvents.instance.fire(CloudEvent.burst);
        return;
      case MascotTapStep.feed:
        setState(() => _fed = _combo.fed);
      case MascotTapStep.wait:
        _setAnim(MascotAnimState.drop);
    }
    _menuTimer = Timer(kMascotTapChain, _settleTaps);
  }

  /// Тапы прекратились: один — меню, два — кувырок, серия без дождя —
  /// сдуться обратно.
  void _settleTaps() {
    if (!mounted) return;
    switch (_combo.settle()) {
      case MascotTapEnd.menu:
        _onTap();
      case MascotTapEnd.flip:
        _setAnim(MascotAnimState.grow);
      case MascotTapEnd.deflate:
        setState(() => _fed = 0);
      case MascotTapEnd.none:
        break;
    }
  }

  void _onTap() {
    if (_menuOpen || !mounted) return;
    _menuOpen = true;
    // Облачко отвечает на касание само, меню выезжает под ним.
    if (_isCloud) _setAnim(MascotAnimState.drop);
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.theme.cardSurface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.theme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Размер: щипок двумя пальцами по маскоту работал и раньше, но о нём
            // никто не догадывался. Ползунок делает ту же настройку явной, а
            // масштаб уезжает партнёру тем же путём (`mascot_scale` группы).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Row(
                children: [
                  Icon(Icons.photo_size_select_small_rounded,
                      size: 18, color: widget.theme.textMuted),
                  Expanded(
                    child: Slider(
                      value: _scale.clamp(_kMinScale, _kMaxScale),
                      min: _kMinScale,
                      max: _kMaxScale,
                      // Шаг заметен глазу и не даёт промахнуться пальцем мимо
                      // «того же самого» размера.
                      divisions: 16,
                      label: '${(_scale * 100).round()}%',
                      onChanged: (v) {
                        setSheetState(() {});
                        setState(() => _scale = v);
                      },
                      onChangeEnd: (_) {
                        HapticFeedback.selectionClick();
                        _scheduleSync();
                      },
                    ),
                  ),
                  Icon(Icons.photo_size_select_large_rounded,
                      size: 22, color: widget.theme.textMuted),
                ],
              ),
            ),
            // Облачко в цвете настроения: партнёра или своём.
            if (_isCloud)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ruEn('Цвет настроения', 'Mood colour'),
                        style: TextStyle(color: widget.theme.textPrimary, fontSize: 15),
                      ),
                    ),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: false, label: Text(ruEn('Партнёра', 'Partner'))),
                        ButtonSegment(value: true, label: Text(ruEn('Моё', 'Mine'))),
                      ],
                      selected: {_cloudMine},
                      onSelectionChanged: (v) async {
                        setSheetState(() {});
                        setState(() => _cloudMine = v.first);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool(_kCloudMineKey, v.first);
                      },
                    ),
                  ],
                ),
              ),
            // Гардероб Ту — первым пунктом: нажал на Ту и переодел.
            if (_isCloud)
              ListTile(
                leading: Icon(Icons.checkroom_outlined, color: widget.theme.primary),
                title: Text(ruEn('Гардероб', 'Wardrobe')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TuWardrobeScreen(),
                    settings: const RouteSettings(name: '/tu_wardrobe'),
                  ));
                },
              ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: widget.theme.primary,
              ),
              title: Text(LocaleService.current.goToGallery),
              onTap: () {
                Navigator.of(ctx).pop();
                widget.onOpenGallery();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.visibility_off_outlined,
                color: widget.theme.textMuted,
              ),
              title: Text(LocaleService.current.hide),
              onTap: () async {
                Navigator.of(ctx).pop();
                setState(() => _hidden = true);
                mascotHiddenNotifier.value = true;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_kHiddenKey, true);
              },
            ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) _menuOpen = false;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mascot = _svc.activeMascot;
    if (mascot == null || _hidden || !_positionInitialized) {
      return const SizedBox.shrink();
    }

    final mascotSize = 80.0 * _scale;

    return Positioned(
      left: _position.dx - mascotSize / 2,
      top: _position.dy - mascotSize / 2,
      child: ScaleTransition(
        scale: _entranceAnim,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _tapped,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              if (!_isCloud) return;
              _ringCtrl.stop();
              setState(() {
                _touchPoint = e.localPosition;
                _touchHeld = true;
              });
            },
            onPointerUp: (_) => _releaseTouch(),
            onPointerCancel: (_) => _releaseTouch(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _mascotBody(mascot, mascotSize),
                if (_touchPoint != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _ringCtrl,
                        builder: (_, _) => CustomPaint(
                          painter: _TouchMarkPainter(
                            point: _touchPoint!,
                            unit: mascotSize * 1.4 / 100,
                            held: _touchHeld,
                            ring: _ringCtrl.value,
                          ),
                        ),
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

  void _releaseTouch() {
    if (!_touchHeld) return;
    setState(() => _touchHeld = false);
    _ringCtrl.forward(from: 0).whenComplete(() {
      if (mounted && !_touchHeld) setState(() => _touchPoint = null);
    });
  }

  Widget _mascotBody(Mascot mascot, double mascotSize) {
    return SizedBox(
            width: mascotSize,
            height: mascotSize,
            // Раздутый тапами Ту растёт от низа; об край экрана в полёте
            // сплющивается вдоль удара.
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _fed),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              builder: (context, fed, child) {
                final grow = 1 + 0.21 * fed;
                // Сплющивание идёт от стены удара: Ту прижат к ней. Ось,
                // по которой бился, сплющена, другая раздаётся; в углу
                // сплющены обе — Ту вжат в угол.
                final hitX = _hitSide.x != 0, hitY = _hitSide.y != 0;
                final sx = hitX ? _squash.flat : (hitY ? _squash.wide : 1.0);
                final sy = hitY ? _squash.flat : (hitX ? _squash.wide : 1.0);
                return Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(grow, grow, 1),
                  child: Transform(
                    alignment: _hitSide,
                    transform: Matrix4.diagonal3Values(sx, sy, 1),
                    child: child,
                  ),
                );
              },
              child: _MascotImage(
                mascot: mascot,
                service: _svc,
                cloudMood: widget.moodOf?.call(_cloudMine),
                anim: _anim,
                level: MascotAnim.levelForStreak(_svc.activeStreak),
                sleep: widget.sleepOf(mascot.id),
                onAnimDone: () => _setAnim(MascotAnimState.live),
              ),
            ),
    );
  }
}

/// Кружок касания, как был в сцене мастерской (`touchMark` в mascot.js):
/// белая подушечка с контуром тушью, пока палец прижат, и кольцо, которое
/// расходится и тает после отпускания. [unit] — сотая доля холста Ту.
class _TouchMarkPainter extends CustomPainter {
  _TouchMarkPainter({required this.point, required this.unit, required this.held, required this.ring});

  final Offset point;
  final double unit;
  final bool held;
  final double ring;

  static const Color _ink = Color(0xFF2A2D30);

  @override
  void paint(Canvas canvas, Size size) {
    if (held) {
      canvas.drawCircle(point, 5.5 * unit, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(point, 5.5 * unit, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * unit
        ..color = _ink);
      return;
    }
    if (ring <= 0 || ring >= 1) return;
    canvas.drawCircle(point, (4 + 12 * ring) * unit, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * (1 - ring * 0.6) * unit
      ..color = _ink.withValues(alpha: 1 - ring));
  }

  @override
  bool shouldRepaint(_TouchMarkPainter old) =>
      old.point != point || old.held != held || old.ring != ring || old.unit != unit;
}

// ── Mascot image renderer ─────────────────────────────────────────────────────

class _MascotImage extends StatelessWidget {
  final Mascot mascot;
  final MascotService service;

  /// Поза анимированного маскота. У обычных картинок не используется.
  final MascotAnimState anim;

  /// Ступень роста: считается по длине серии.
  final int level;
  final VoidCallback? onAnimDone;

  /// Когда этот персонаж уходит на ночную сцену.
  final SleepWindow sleep;

  /// Настроение, которым красится облачко (id), или null.
  final String? cloudMood;

  const _MascotImage({
    required this.mascot,
    required this.service,
    this.cloudMood,
    this.anim = MascotAnimState.live,
    this.level = 3,
    this.sleep = SleepWindow.standard,
    this.onAnimDone,
  });

  @override
  Widget build(BuildContext context) {
    if (mascot.id == kCloudMascotId) {
      return LayoutBuilder(
        builder: (_, c) {
          final side = c.biggest.shortestSide;
          return CloudMascotView(
            size: side.isFinite ? side : 96,
            anim: anim,
            tint: cloudTintForMood(cloudMood),
            night: sleep.contains(DateTime.now()),
            sick: cloudMood == 'sick',
            mood: cloudMood,
            listenEvents: true,
            onOneShotDone: onAnimDone,
          );
        },
      );
    }
    // Пиксельный маскот из каталога: рисуем кадр из атласа. Проверка идёт
    // первой — у такого маскота catalogUrl ведёт на атлас, и обычный Image
    // показал бы всю простыню кадров разом.
    final animated = CatalogService.instance.animById(mascot.id);
    if (animated != null) {
      return LayoutBuilder(
        builder: (_, c) {
          final side = c.biggest.shortestSide;
          return PixelMascotView(
            anim: animated,
            state: anim,
            level: level,
            sleep: sleep,
            // Без ограничений сверху сюда приходит бесконечность, а её нельзя
            // отдавать в размер: виджет схлопывает всё вокруг себя.
            size: side.isFinite ? side : 96,
            onOneShotDone: onAnimDone,
          );
        },
      );
    }

    final asset = service.resolvedAssetForMood(mascot);
    if (asset != null) {
      return buildMascotAssetImage(asset, fit: BoxFit.contain);
    }
    if (mascot.catalogUrl != null) {
      return CachedNetworkImage(
      cacheManager: OfflineImageCacheManager.instance,
        imageUrl: mascot.catalogUrl!,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const Icon(Icons.face, size: 40),
      );
    }
    if (mascot.imageUrl != null) {
      return StorageImage(
        imageUrl: mascot.imageUrl!,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const Icon(Icons.face, size: 40),
      );
    }
    return const Icon(Icons.face, size: 40);
  }
}

/// Renders a mascot from a local asset path.
/// Supports PNG/JPG (Image.asset) and SVG (SvgPicture.asset).
Widget buildMascotAssetImage(
  String assetPath, {
  BoxFit fit = BoxFit.contain,
  double? width,
  double? height,
}) {
  // Персонажи и их кадры приезжают двумя путями: часть лежит в сборке, часть —
  // записью в `catalog_items` (новый маскот появляется без обновления
  // приложения). Второй путь даёт полный адрес, и раньше он уходил в
  // `Image.asset` — «Unable to load asset: https://…» в панели крашей, а на
  // экране вместо персонажа заглушка.
  final lower = assetPath.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    if (lower.endsWith('.svg')) {
      return SvgPicture.network(
        assetPath,
        fit: fit,
        width: width,
        height: height,
      );
    }
    return CachedNetworkImage(
      cacheManager: OfflineImageCacheManager.instance,
      imageUrl: assetPath,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => const Icon(Icons.face, size: 40),
    );
  }
  if (lower.endsWith('.svg')) {
    return SvgPicture.asset(assetPath, fit: fit, width: width, height: height);
  }
  return Image.asset(
    assetPath,
    fit: fit,
    width: width,
    height: height,
    errorBuilder: (_, __, ___) => const Icon(Icons.face, size: 40),
  );
}

/// Un-hides the floating mascot from anywhere in the app.
Future<void> showMascotOverlay() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHiddenKey, false);
  mascotHiddenNotifier.value = false;
}
