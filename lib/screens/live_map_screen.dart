import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/geo_arc.dart';
import '../models/globe_math.dart';
import '../models/live_point_age.dart';
import '../services/live_location_service.dart';
import '../services/locale_service.dart';
import '../services/map/directions.dart';
import '../services/map/map_palette.dart';
import '../services/map/map_tiles.dart';
import '../services/miss_you_repository.dart';
import '../services/pocketbase_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../widgets/connect_expressive.dart';
import '../widgets/map/globe_view.dart';
import '../widgets/map/land_shapes.dart';
import '../widgets/map/map_arc_layer.dart';
import '../widgets/map/map_balloon.dart';

/// Дальше этого экран открывается глобусом: на плоской карте двое из разных
/// стран видят поле между собой и ни одной своей улицы.
const double kGlobeStartMeters = 1000 * 1000;

/// Доли перехода «глобус → карта»: приближение, развёртка, детали.
const double _t1 = .55, _t2 = .85;
const Duration _transitionTime = Duration(milliseconds: 1400);

/// Карта «Где мы»: глобус для дальнего плана, векторная карта в цветах темы
/// вблизи, дуга из точек между двумя людьми и «Скучаю» по ней.
///
/// Глобус и развёртку рисует свой painter (`GlobePainter`), плоскую карту —
/// flutter_map с `ThemedMapLayer`. Переход между ними — в
/// `GlobeTransition`: шар приезжает к камере карты, раскатывается в её
/// проекцию, и только тогда поверх проявляются тайлы.
class LiveMapScreen extends StatefulWidget {
  final String pairId;
  final String partnerUid;
  final String partnerName;
  final String partnerAvatarUrl;
  final String myAvatarUrl;
  final AppTheme theme;

  /// Стартовый центр (обычно «обе точки» из превью), чтобы перелёт читался.
  final LatLng? initialCenter;
  final double initialZoom;

  const LiveMapScreen({
    super.key,
    required this.pairId,
    required this.partnerUid,
    required this.partnerName,
    required this.partnerAvatarUrl,
    required this.myAvatarUrl,
    required this.theme,
    this.initialCenter,
    this.initialZoom = 13,
  });

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> with TickerProviderStateMixin {
  final MapController _map = MapController();

  StreamSubscription<LivePoint?>? _partnerSub;
  StreamSubscription<Position>? _meSub;
  LatLng? _me;
  LivePoint? _partner;
  bool _mapReady = false;
  bool _decided = false;
  Timer? _decideTimer;

  /// 0 — глобус, 1 — карта; между ними идёт переход.
  late final AnimationController _mode =
      AnimationController(vsync: this, value: 1, duration: _transitionTime);
  late final Animation<double> _tiles = _mode.drive(CurveTween(curve: const Interval(_t2, 1)));
  late final AnimationController _fly =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  final ValueNotifier<double?> _flyValue = ValueNotifier(null);
  late final AnimationController _bump =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _bumpScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.14).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.14, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
  ]).animate(_bump);

  GlobeTransition? _transition;
  Offset _drag = Offset.zero; // поворот шара пальцем, градусы (долгота, широта)
  bool _scaledToMap = false;
  double? _fitZoom;

  List<LandRing>? _land110, _land50;
  RoundedPolygon _partnerShape = kAvatarShapes.first;
  RoundedPolygon _myShape = kAvatarShapes[4];

  String? _toast;
  Timer? _toastTimer;

  // Раскладка экрана, пересчитывается в build.
  Size _size = Size.zero;
  double _topBar = 0, _panelTop = 0;
  double _panelHeight = 200;
  Offset _focus = Offset.zero;

  bool get _inMap => _mode.value >= 1 && !_mode.isAnimating;
  bool get _paired => _me != null && _partner != null;

  @override
  void initState() {
    super.initState();
    _partnerSub = LiveLocationService.instance.watchPartner(widget.pairId, widget.partnerUid).listen(_onPartner);
    _startMyStream();
    _loadShapes();
    LandShapes.coarse().then((v) => mounted ? setState(() => _land110 = v) : null);
    LandShapes.detailed().then((v) => mounted ? setState(() => _land50 = v) : null);
    _fly.addListener(() => _flyValue.value = _fly.isAnimating ? _fly.value : null);
    _fly.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _flyValue.value = null;
        _bump.forward(from: 0);
      }
    });
    _mode.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        if (mounted) setState(() {});
      }
    });
    // Без второй точки дольше четырёх секунд — открываемся тем, что есть.
    _decideTimer = Timer(const Duration(seconds: 4), () => _decide(force: true));
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _meSub?.cancel();
    _decideTimer?.cancel();
    _toastTimer?.cancel();
    _mode.dispose();
    _fly.dispose();
    _bump.dispose();
    _flyValue.dispose();
    super.dispose();
  }

  Future<void> _loadShapes() async {
    final prefs = await SharedPreferences.getInstance();
    RoundedPolygon shapeFor(String uid) {
      final i = prefs.getInt('avatar_shape_$uid') ?? defaultShapeIndexForUid(uid);
      return kAvatarShapes[i.clamp(0, kAvatarShapes.length - 1)];
    }

    if (!mounted) return;
    setState(() {
      _partnerShape = shapeFor(widget.partnerUid);
      _myShape = shapeFor(PocketBaseService().userId ?? '');
    });
  }

  Future<void> _startMyStream() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _onMe(LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
    _meSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) => _onMe(LatLng(pos.latitude, pos.longitude)), onError: (_) {});
  }

  void _onMe(LatLng p) {
    if (!mounted) return;
    setState(() => _me = p);
    _decide();
  }

  void _onPartner(LivePoint? p) {
    if (!mounted) return;
    setState(() => _partner = p);
    _decide();
  }

  /// С чего начать: далеко — глобус, близко — карта с обоими в кадре.
  void _decide({bool force = false}) {
    if (_decided) return;
    final me = _me, partner = _partner?.latLng;
    if (!force && (me == null || partner == null)) return;
    if (me == null && partner == null) return;
    _decided = true;
    _decideTimer?.cancel();
    if (me != null && partner != null && LiveLocationService.distanceMeters(me, partner) > kGlobeStartMeters) {
      _mode.value = 0;
      setState(() {});
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBoth(animate: false));
    }
  }

  // ── Камера карты ────────────────────────────────────────────────────────

  EdgeInsets get _fitPadding => EdgeInsets.fromLTRB(72, _topBar + 100, 72, _size.height - _panelTop + 36);

  MapCamera? _fitCamera() {
    if (!_mapReady) return null;
    final coords = [?_me, ?_partner?.latLng];
    if (coords.isEmpty) return null;
    try {
      return CameraFit.coordinates(coordinates: coords, padding: _fitPadding, maxZoom: 16).fit(_map.camera);
    } catch (_) {
      return null;
    }
  }

  void _fitBoth({bool animate = true}) {
    final fit = _fitCamera();
    if (fit == null) return;
    _fitZoom = fit.zoom;
    try {
      _map.move(fit.center, fit.zoom);
    } catch (_) {}
  }

  void _centerOnMe() {
    final me = _me;
    if (me == null || !_mapReady) return;
    try {
      _map.move(me, math.max(_map.camera.zoom, 15));
    } catch (_) {}
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    if (!hasGesture || !_inMap || !_paired) return;
    final threshold = math.min(3.0, (_fitZoom ?? 6) - 1.5);
    if (camera.zoom < threshold) _goGlobe();
  }

  // ── Переходы ────────────────────────────────────────────────────────────

  double get _gap => math.max(60, _focus.dy - (_topBar + 20));

  GlobeView _restView() {
    final me = _me, partner = _partner?.latLng;
    final a = me ?? partner!, b = partner ?? me!;
    final mid = greatCircle(a, b, segments: 2)[1];
    final ang = LiveLocationService.distanceMeters(a, b) / 6371008.8;
    final w = _size.width;
    final r = (.42 * w / math.max(ang, 1e-4)).clamp(.42 * w, 1.45 * w).toDouble();
    return GlobeView(
      lat: (mid.latitude + _drag.dy).clamp(-80.0, 80.0).toDouble(),
      lon: mid.longitude + _drag.dx,
      radius: r,
    );
  }

  GlobeTransition _transitionFor(MapCamera cam, GlobeView rest) {
    final c = cam.screenOffsetToLatLng(_focus);
    return GlobeTransition(
      rest: rest,
      target: GlobeTarget(
        lat: c.latitude,
        lon: c.longitude,
        radius: matchRadius(zoom: cam.zoom, lat: c.latitude),
      ),
      focus: _focus,
      horizonGap: _gap,
      camera: MercatorCamera(
        centerLat: cam.center.latitude,
        centerLon: cam.center.longitude,
        zoom: cam.zoom,
        size: cam.size,
      ),
    );
  }

  Duration _timeFor(double distance) => _transitionTime * distance.abs().clamp(.2, 1.0);

  Future<void> _goMap() async {
    if (_mode.isAnimating || _mode.value >= 1 || !_paired) return;
    final fit = _fitCamera();
    if (fit == null) return;
    _fitZoom = fit.zoom;
    try {
      _map.move(fit.center, fit.zoom);
    } catch (_) {}
    _transition = _transitionFor(fit, _restView());
    HapticFeedback.selectionClick();
    await _mode.animateTo(1, duration: _timeFor(1 - _mode.value), curve: Curves.linear);
  }

  void _goGlobe() {
    if (_mode.isAnimating || _mode.value <= 0 || !_paired || !_mapReady) return;
    _drag = Offset.zero;
    _transition = _transitionFor(_map.camera, _restView());
    HapticFeedback.selectionClick();
    setState(() {});
    _mode.animateBack(0, duration: _timeFor(_mode.value), curve: Curves.linear);
  }

  /// Как точка сферы попадает на экран в этот кадр.
  GlobeScene? _scene() {
    if (!_paired || _size.isEmpty) return null;
    final p = _mode.value;
    if (p <= 0 && !_mode.isAnimating) {
      final rest = _restView();
      return GlobeScene.globe(GlobeTransition(
        rest: rest,
        target: GlobeTarget(lat: rest.lat, lon: rest.lon, radius: rest.radius),
        focus: _focus,
        horizonGap: _gap,
        camera: MercatorCamera(centerLat: rest.lat, centerLon: rest.lon, zoom: 0, size: _size),
      ).viewAt(0));
    }
    final t = _transition;
    if (t == null) return null;
    if (p <= _t1) return GlobeScene.globe(t.viewAt(p / _t1));
    final a = Curves.easeInOutCubic.transform(((p - _t1) / (_t2 - _t1)).clamp(0.0, 1.0));
    return GlobeScene.unroll(t, a, landMix: ((p - _t2) / (1 - _t2)).clamp(0.0, 1.0));
  }

  // ── «Скучаю» и «Как доехать» ────────────────────────────────────────────

  Future<void> _sendMissYou() async {
    final s = LocaleService.current;
    HapticFeedback.lightImpact();
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _fly.forward(from: 0);
    } else {
      _bump.forward(from: 0);
    }
    _showToast(s.liveMapMissYouSent);
    final ok = await MissYouRepository().sendMissYou(widget.pairId);
    if (!ok && mounted) _showToast(s.giftFailed);
  }

  void _openRoute() {
    final p = _partner;
    if (p == null) return;
    openDirections(context, p.latLng, widget.partnerName);
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final palette = MapTiles.paletteOf(widget.theme);
    final media = MediaQuery.of(context);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        body: LayoutBuilder(builder: (context, box) {
          _size = box.biggest;
          _topBar = media.padding.top + 12 + 48;
          _panelTop = box.maxHeight - _panelHeight;
          _focus = Offset(box.maxWidth / 2, (_topBar + _panelTop) / 2);
          return Stack(
            children: [
              Positioned.fill(child: _globeLayer(palette)),
              Positioned.fill(child: _mapLayer(palette, cs)),
              Positioned.fill(child: _overlayBalloons(cs, palette)),
              _topControls(cs),
              _sideButtons(cs),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _MeasureSize(
                  onChange: (s) {
                    if ((s.height - _panelHeight).abs() > .5) setState(() => _panelHeight = s.height);
                  },
                  child: _panel(cs, media.padding.bottom),
                ),
              ),
              _toastView(cs),
            ],
          );
        }),
      ),
    );
  }

  Widget _globeLayer(MapPalette palette) {
    return AnimatedBuilder(
      animation: Listenable.merge([_mode, _flyValue]),
      builder: (context, _) {
        if (_inMap) return const SizedBox.shrink();
        final scene = _scene();
        if (scene == null) return const SizedBox.shrink();
        final land = scene.radius > 700 ? (_land50 ?? _land110) : (_land110 ?? _land50);
        final arc = scene.arc(greatCircle(_me!, _partner!.latLng, segments: 64));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _goMap,
          onScaleStart: (_) => _scaledToMap = false,
          onScaleUpdate: (d) {
            if (_mode.isAnimating || _mode.value > 0) return;
            if (d.pointerCount >= 2) {
              if (d.scale > 1.18 && !_scaledToMap) {
                _scaledToMap = true;
                _goMap();
              }
              return;
            }
            final r = _restView().radius;
            setState(() {
              _drag += Offset(
                -d.focalPointDelta.dx / r * 180 / math.pi,
                d.focalPointDelta.dy / r * 180 / math.pi,
              );
            });
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: GlobePainter(
              scene: scene,
              land: land ?? const [],
              palette: palette,
              arc: arc,
              fly: _flyValue.value,
            ),
          ),
        );
      },
    );
  }

  Widget _mapLayer(MapPalette palette, ColorScheme cs) {
    final me = _me, partner = _partner;
    final center = widget.initialCenter ?? partner?.latLng ?? me ?? const LatLng(47.0105, 28.8638);
    return IgnorePointer(
      ignoring: !_inMap,
      child: FadeTransition(
        opacity: _tiles,
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: widget.initialZoom,
            minZoom: 1.5,
            maxZoom: 18,
            backgroundColor: palette.land,
            // Поворот выключен: двумя пальцами карту переворачивали вверх
            // ногами, а вернуть север было нечем.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _mapReady = true;
              if (_decided && _mode.value >= 1) _fitBoth(animate: false);
            },
            onPositionChanged: _onMapMoved,
          ),
          children: [
            ThemedMapLayer(theme: widget.theme),
            if (_inMap && me != null && partner != null)
              MapArcLayer(from: me, to: partner.latLng, palette: palette, fly: _flyValue),
            if (_inMap)
              MarkerLayer(
                markers: [
                  if (me != null)
                    Marker(
                      point: me,
                      width: kBalloonWidth,
                      height: kBalloonHeight,
                      alignment: kBalloonAlignment,
                      child: _myBalloon(cs, palette),
                    ),
                  if (partner != null)
                    Marker(
                      point: partner.latLng,
                      width: kBalloonWidth,
                      height: kBalloonHeight,
                      alignment: kBalloonAlignment,
                      child: _partnerBalloon(cs, palette),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Шарики поверх глобуса и развёртки — там, где карта ещё не видна.
  Widget _overlayBalloons(ColorScheme cs, MapPalette palette) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _mode,
        builder: (context, _) {
          if (_inMap) return const SizedBox.shrink();
          final scene = _scene();
          if (scene == null) return const SizedBox.shrink();
          final m = scene.toScreen(_me!), p = scene.toScreen(_partner!.latLng);
          return Stack(
            children: [
              if (m != null)
                Positioned(
                  left: m.dx - kBalloonWidth / 2,
                  top: m.dy - kBalloonDotY,
                  child: _myBalloon(cs, palette),
                ),
              if (p != null)
                Positioned(
                  left: p.dx - kBalloonWidth / 2,
                  top: p.dy - kBalloonDotY,
                  child: _partnerBalloon(cs, palette),
                ),
            ],
          );
        },
      ),
    );
  }

  BalloonColors _colors(ColorScheme cs, MapPalette palette, {required bool partner}) => BalloonColors(
        ring: cs.surface,
        string: cs.onSecondaryContainer,
        dot: palette.thread,
        face: partner ? cs.secondaryContainer : cs.tertiaryContainer,
        onFace: partner ? cs.onSecondaryContainer : cs.onTertiaryContainer,
      );

  Widget _myBalloon(ColorScheme cs, MapPalette palette) => MapBalloon(
        key: const ValueKey('me'),
        shape: _myShape,
        avatarUrl: widget.myAvatarUrl,
        name: LocaleService.current.liveMapYou,
        colors: _colors(cs, palette, partner: false),
        live: true,
      );

  Widget _partnerBalloon(ColorScheme cs, MapPalette palette) {
    final p = _partner;
    final stale = p != null && _isStale(p.updatedAt);
    return ScaleTransition(
      scale: _bumpScale,
      alignment: const Alignment(0, .85),
      child: MapBalloon(
        key: const ValueKey('partner'),
        shape: _partnerShape,
        avatarUrl: widget.partnerAvatarUrl,
        name: widget.partnerName,
        colors: _colors(cs, palette, partner: true),
        live: true,
        stale: stale,
      ),
    );
  }

  Widget _topControls(ColorScheme cs) {
    final s = LocaleService.current;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _RoundButton(
            icon: Icons.arrow_back_rounded,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.pop(context),
            cs: cs,
          ),
          const Spacer(),
          if (_paired)
            AnimatedBuilder(
              animation: _mode,
              builder: (context, _) => _ModeSwitch(
                cs: cs,
                globe: _mode.value < .5,
                globeLabel: s.liveMapGlobe,
                mapLabel: s.liveMapMapMode,
                onGlobe: _goGlobe,
                onMap: _goMap,
              ),
            ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _sideButtons(ColorScheme cs) {
    final s = LocaleService.current;
    return Positioned(
      right: 16,
      top: _topBar + 16,
      child: AnimatedBuilder(
        animation: _mode,
        builder: (context, _) {
          final globe = _mode.value < .5 && _paired;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: globe
                ? _RoundButton(
                    key: const ValueKey('zoom'),
                    icon: Icons.zoom_in_map_rounded,
                    tooltip: s.liveMapZoomIn,
                    onTap: _goMap,
                    cs: cs,
                    squircle: true,
                  )
                : Column(
                    key: const ValueKey('map'),
                    children: [
                      if (_paired)
                        _RoundButton(
                          icon: Icons.group_rounded,
                          tooltip: s.liveMapShowBoth,
                          onTap: _fitBoth,
                          cs: cs,
                          squircle: true,
                        ),
                      if (_paired) const SizedBox(height: 8),
                      _RoundButton(
                        icon: Icons.my_location_rounded,
                        tooltip: s.liveMapCenterMe,
                        onTap: _centerOnMe,
                        cs: cs,
                        squircle: true,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _panel(ColorScheme cs, double bottomInset) {
    final s = LocaleService.current;
    final me = _me, partner = _partner;
    final fill = widget.theme.fillColor;
    final onFill = AppThemes.onColor(fill, mode: widget.theme.brightness);
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(22, 22, 20, 16 + bottomInset),
      child: partner == null
          ? Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.liveMapWaitingPartner,
                    style: AppFonts.onest(size: 15, weight: 500, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          me == null
                              ? '—'
                              : LiveLocationService.formatDistance(
                                  LiveLocationService.distanceMeters(me, partner.latLng)),
                          style: AppFonts.unbounded(size: 40, weight: 800, color: cs.onSurface, height: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: s.missYouTitle,
                      child: Material(
                        color: fill,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _sendMissYou,
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: Icon(Icons.favorite_rounded, color: onFill, size: 26),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    AvatarFace(
                      shape: _partnerShape,
                      size: 30,
                      avatarUrl: widget.partnerAvatarUrl,
                      name: widget.partnerName,
                      fill: cs.secondaryContainer,
                      onFill: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: widget.partnerName,
                            style: AppFonts.onest(size: 15, weight: 700, color: cs.onSurface),
                          ),
                          if (_ageCaption(partner) != null)
                            TextSpan(
                              text: ' · ${_ageCaption(partner)}',
                              style: AppFonts.onest(size: 14.5, weight: 500, color: cs.onSurfaceVariant),
                            ),
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _openRoute,
                  icon: const Icon(Icons.directions_rounded, size: 22),
                  label: Text(s.liveMapRoute),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    textStyle: AppFonts.onest(size: 15, weight: 700),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _toastView(ColorScheme cs) {
    final text = _toast;
    return Positioned(
      left: 16,
      right: 16,
      bottom: _panelHeight + 12,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: text == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(22)),
              child: Text(
                text ?? '',
                style: AppFonts.onest(size: 14, weight: 600, color: cs.onInverseSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// «Обновлено 2 д. назад» — или null, пока точка свежая.
  String? _ageCaption(LivePoint? point) {
    if (point == null) return null;
    final age = LivePointAge.of(point.updatedAt, nowMs: DateTime.now().millisecondsSinceEpoch);
    if (!age.needsCaption) return null;
    final s = LocaleService.current;
    final ago = switch (age.unit) {
      LivePointAgeUnit.minutes => s.minutesAgo(age.value),
      LivePointAgeUnit.hours => s.hoursAgo(age.value),
      _ => s.daysAgo(age.value),
    };
    return '${s.liveMapUpdated} $ago';
  }

  bool _isStale(int updatedAt) {
    if (updatedAt <= 0) return false;
    return LivePointAge.of(updatedAt, nowMs: DateTime.now().millisecondsSinceEpoch).needsCaption;
  }
}

/// Круглая кнопка поверх карты: инверсная поверхность, как у остальной
/// «хромы» экрана, без теней.
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool squircle;

  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.cs,
    this.squircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(squircle ? 18 : 24);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.inverseSurface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            width: squircle ? 52 : 48,
            height: squircle ? 52 : 48,
            child: Icon(icon, color: cs.onInverseSurface, size: 24),
          ),
        ),
      ),
    );
  }
}

/// Переключатель «Глобус · Карта».
class _ModeSwitch extends StatelessWidget {
  final ColorScheme cs;
  final bool globe;
  final String globeLabel, mapLabel;
  final VoidCallback onGlobe, onMap;

  const _ModeSwitch({
    required this.cs,
    required this.globe,
    required this.globeLabel,
    required this.mapLabel,
    required this.onGlobe,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    final on = cs.inversePrimary;
    final onText = ThemeData.estimateBrightnessForColor(on) == Brightness.dark ? Colors.white : const Color(0xFF1B1516);
    Widget part(String label, bool selected, VoidCallback tap) => Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: selected ? null : tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? on : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: AppFonts.onest(size: 14, weight: 600, color: selected ? onText : cs.onInverseSurface),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(24)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          part(globeLabel, globe, onGlobe),
          const SizedBox(width: 2),
          part(mapLabel, !globe, onMap),
        ],
      ),
    );
  }
}

/// Сообщает размер ребёнка после раскладки: высота панели нужна, чтобы шар и
/// камера карты держали пару в свободной части экрана.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const _MeasureSize({required this.onChange, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _MeasureSizeBox(onChange);

  @override
  void updateRenderObject(BuildContext context, covariant _MeasureSizeBox renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeBox extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _last;

  _MeasureSizeBox(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}
