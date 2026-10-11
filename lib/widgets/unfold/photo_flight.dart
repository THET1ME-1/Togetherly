import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'unfold_math.dart';
import 'unfold_touch.dart';

/// Просмотр кадра: снимок вылетает из нажатой миниатюры на середину экрана,
/// фон под ним темнеет, кнопки проявляются следом.
///
/// Закрыть можно кнопкой или потянув кадр вниз: он едет за пальцем, фон
/// светлеет, а отпущенный за порогом кадр летит обратно в миниатюру (макет
/// 11.10.2026, сцена «Фото → просмотр»). Прежде просмотр появлялся мгновенно
/// и жеста не знал.
///
/// Место вызова миниатюру не называет — её находит [UnfoldTouch] по касанию.
/// Экран просмотра размечает себя тремя обёртками:
/// ```dart
/// Stack(children: [
///   PhotoFlightBackdrop(child: чёрный фон),
///   PhotoFlightStage(child: сам кадр),
///   PhotoFlightChrome(index: 0, child: шапка),
///   PhotoFlightChrome(index: 1, child: кнопки внизу),
/// ])
/// ```
/// Вне [PhotoFlightRoute] обёртки ничего не делают.
class PhotoFlightRoute<T> extends PageRoute<T> {
  PhotoFlightRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  UnfoldPhoto? _shot;
  bool _calm = false;
  _PhotoFlightState? _view;

  @override
  void install() {
    final context = navigator?.context;
    _calm = context != null &&
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    // Картинку берём в миг нажатия: через кадр миниатюра может перестроиться.
    final shot = UnfoldTouch.takeImage();
    if (_calm) {
      shot?.dispose();
    } else {
      _shot = shot;
    }
    super.install();
  }

  @override
  Duration get transitionDuration => Duration(
      milliseconds:
          (_calm ? UnfoldTiming.fadeInMs : PhotoTiming.openMs).round());

  @override
  Duration get reverseTransitionDuration => Duration(
      milliseconds:
          (_calm ? UnfoldTiming.fadeOutMs : PhotoTiming.closeMs).round());

  // Под просмотром виден прежний экран: фон темнеет не сразу, а под пальцем
  // светлеет снова.
  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool didPop(T? result) {
    _view?._beginClose();
    return super.didPop(result);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return _PhotoFlight(route: this, animation: animation, child: child);
  }

  @override
  void dispose() {
    _shot?.dispose();
    _shot = null;
    super.dispose();
  }
}

/// Что экран просмотра может спросить у своего перехода.
abstract final class PhotoFlight {
  /// Картинка миниатюры, из которой вылетел кадр. Годится заглушкой, пока
  /// грузится полный снимок: кадр прилетел, а на его месте не крутилка, а он
  /// сам, только мельче.
  static ui.Image? thumbOf(BuildContext context) =>
      _PhotoFlightScope.maybeOf(context)?._route._shot?.image;
}

enum _Phase { opening, open, dragging, settling, closing }

class _PhotoFlight extends StatefulWidget {
  const _PhotoFlight({
    required this.route,
    required this.animation,
    required this.child,
  });

  final PhotoFlightRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_PhotoFlight> createState() => _PhotoFlightState();
}

class _PhotoFlightState extends State<_PhotoFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  final ValueNotifier<int> _bump = ValueNotifier<int>(0);
  late final Listenable ticks;

  _Phase _phase = _Phase.opening;
  _PhotoFlightStageState? _stage;

  /// Кадр летит отдельным снимком; иначе просмотр просто проявляется.
  bool _flies = false;

  /// Места миниатюры и кадра в просмотре уже сняты.
  bool _resolved = false;

  Rect? _from;
  double _fromRadius = 0;
  Rect? _to;
  ui.Image? _image;

  /// Снимок кадра с экрана для обратного пути: он резче миниатюры.
  ui.Image? _returnShot;

  Offset _drag = Offset.zero;
  ({Offset shift, double scale}) _held = (shift: Offset.zero, scale: 1);
  double _popValue = 1;
  double _backdropFrom = 1;
  double _chromeFrom = 1;
  double? _openLead;

  PhotoFlightRoute<dynamic> get _route => widget.route;
  bool get _calm => _route._calm;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: PhotoTiming.settleMs.round()),
    );
    ticks = Listenable.merge(<Listenable>[widget.animation, _settle, _bump]);
    _route._view = this;
    widget.animation.addStatusListener(_onStatus);
    if (widget.animation.isCompleted && !_route.offstage) {
      _phase = _Phase.open;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    if (identical(_route._view, this)) _route._view = null;
    _returnShot?.dispose();
    _settle.dispose();
    _bump.dispose();
    super.dispose();
  }

  void _notify() => _bump.value++;

  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  double get _pixelRatio => MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;

  /// Куда лететь, известно только после первой раскладки просмотра.
  void _resolve() {
    if (!mounted || _resolved) return;
    _resolved = true;
    final shot = _route._shot;
    final stage = _stage;
    final box = _box;
    if (_phase == _Phase.opening &&
        shot != null &&
        shot.alive &&
        stage != null &&
        box != null) {
      final from = shot.rect(box);
      final area = stage.rect(box);
      if (from != null && !from.isEmpty && area != null && !area.isEmpty) {
        _from = from;
        _fromRadius = shot.radius;
        _to = photoFit(
          Size(shot.image.width.toDouble(), shot.image.height.toDouble()),
          area,
        );
        _image = shot.image;
        _flies = true;
      }
    }
    _notify();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _phase == _Phase.opening) {
      _phase = _Phase.open;
      _flies = false;
      _notify();
    }
  }

  // ── время ─────────────────────────────────────────────────────────────────

  double get _openMs {
    // Первый кадр маршрута стоит за сценой: время идёт с первого видимого.
    if (_route.offstage) return 0;
    final passed = widget.animation.value * PhotoTiming.openMs;
    final lead = _openLead ??= passed;
    return passed - lead;
  }

  double get _closeMs =>
      (1 - widget.animation.value / _popValue).clamp(0.0, 1.0) *
      PhotoTiming.closeMs;

  /// Сколько осталось до места при возврате отпущенного кадра: 1 → 0.
  double get _settleLeft =>
      1 -
      unfoldSpring(_settle.value * PhotoTiming.settleMs, omega: 26, zeta: 1);

  double get _fadeIn => _route.offstage ? 0 : widget.animation.value;

  double get _fadeOut =>
      (widget.animation.value / _popValue).clamp(0.0, 1.0);

  // ── что видят обёртки ─────────────────────────────────────────────────────

  double get backdrop {
    switch (_phase) {
      case _Phase.opening:
        return _calm ? _fadeIn : photoOpenFrame(_openMs).backdrop;
      case _Phase.open:
        return 1;
      case _Phase.dragging:
        return photoDragFrame(_drag).backdrop;
      case _Phase.settling:
        return 1 - (1 - photoDragFrame(_drag).backdrop) * _settleLeft;
      case _Phase.closing:
        return _calm
            ? _backdropFrom * _fadeOut
            : photoCloseFrame(_closeMs, backdropFrom: _backdropFrom).backdrop;
    }
  }

  double chrome(int index) {
    switch (_phase) {
      case _Phase.opening:
        return _calm ? _fadeIn : photoChromeIn(_openMs, index);
      case _Phase.open:
        return 1;
      case _Phase.dragging:
        return photoDragFrame(_drag).chrome;
      case _Phase.settling:
        return 1 - (1 - photoDragFrame(_drag).chrome) * _settleLeft;
      case _Phase.closing:
        return _calm
            ? _chromeFrom * _fadeOut
            : photoChromeOut(_closeMs, from: _chromeFrom);
    }
  }

  /// Сам кадр в просмотре: пока летит снимок, его не видно.
  double get stageOpacity {
    switch (_phase) {
      case _Phase.opening:
        // Места ещё не сняты, а миниатюра есть: считаем, что полетит.
        if (_flies || (!_resolved && _route._shot != null)) return 0;
        return _calm ? _fadeIn : photoOpenFrame(_openMs).backdrop;
      case _Phase.closing:
        if (_flies) return 0;
        return _calm ? _fadeOut : photoCloseFrame(_closeMs).backdrop;
      case _Phase.open:
      case _Phase.dragging:
      case _Phase.settling:
        return 1;
    }
  }

  ({Offset shift, double scale}) get stageDrag {
    switch (_phase) {
      case _Phase.dragging:
        final drag = photoDragFrame(_drag);
        return (shift: drag.shift, scale: drag.scale);
      case _Phase.settling:
        final drag = photoDragFrame(_drag);
        final left = _settleLeft;
        return (shift: drag.shift * left, scale: 1 - (1 - drag.scale) * left);
      case _Phase.closing:
        return _held;
      case _Phase.opening:
      case _Phase.open:
        return (shift: Offset.zero, scale: 1);
    }
  }

  // ── жест «вниз» ───────────────────────────────────────────────────────────

  bool get canDrag => !_calm && _phase == _Phase.open && _route.isCurrent;

  bool beginDrag() {
    if (!canDrag) return false;
    _phase = _Phase.dragging;
    _drag = Offset.zero;
    _notify();
    return true;
  }

  void dragBy(Offset delta) {
    if (_phase != _Phase.dragging) return;
    _drag += delta;
    _notify();
  }

  void endDrag({double velocity = 0, bool cancel = false}) {
    if (_phase != _Phase.dragging) return;
    final down = _drag.dy;
    // Резкий бросок вниз закрывает и с короткого пути.
    final closes =
        !cancel && (photoDragCommits(down) || (velocity > 900 && down > 24));
    final navigator = _route.navigator;
    if (closes && navigator != null) {
      navigator.pop();
      return;
    }
    _phase = _Phase.settling;
    _settle.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || _phase != _Phase.settling) return;
      _phase = _Phase.open;
      _drag = Offset.zero;
      _notify();
    });
    _notify();
  }

  // ── закрытие ──────────────────────────────────────────────────────────────

  Rect _moved(Rect rect, Rect area, ({Offset shift, double scale}) drag) {
    if (drag.scale == 1 && drag.shift == Offset.zero) return rect;
    // Сцена сжимается вокруг своего центра и сдвигается следом.
    final center = area.center + (rect.center - area.center) * drag.scale;
    return Rect.fromCenter(
      center: center + drag.shift,
      width: rect.width * drag.scale,
      height: rect.height * drag.scale,
    );
  }

  void _beginClose() {
    if (_phase == _Phase.closing) return;
    final was = _phase;
    final backdropNow = backdrop;
    final chromeNow = chrome(0);
    final held = stageDrag;
    final flightNow = was == _Phase.opening && _flies && !_calm
        ? photoOpenFrame(_openMs).flight
        : 1.0;

    _popValue = widget.animation.value;
    if (_popValue <= 0) _popValue = 1;
    _backdropFrom = backdropNow;
    _chromeFrom = chromeNow;
    _held = held;
    _settle.stop();

    final shot = _route._shot;
    final stage = _stage;
    final box = _box;
    final from = shot != null && shot.alive && box != null
        ? shot.rect(box)
        : null;
    final area = stage != null && box != null ? stage.rect(box) : null;

    Rect? now;
    ui.Image? image;
    if (was == _Phase.opening) {
      // Закрыли посреди полёта: снимок возвращается с того места, докуда
      // долетел.
      if (_flies && _from != null && _to != null) {
        now = Rect.lerp(_from, _to, flightNow);
        image = _image;
      }
    } else if (shot != null && area != null && (stage?.widget.returns ?? false)) {
      final rest = photoFit(
        Size(shot.image.width.toDouble(), shot.image.height.toDouble()),
        area,
      );
      now = _moved(rest, area, held);
      _returnShot?.dispose();
      _returnShot = null;
      // Мелкая миниатюра (плёнка кадров, аватар) во весь экран мылит, и
      // обратно летит снимок кадра с экрана. Крупной обложке хватает своей
      // картинки, а она надёжнее: на экране может стоять значок ошибки.
      final sharp = shot.image.width >= rest.width * _pixelRatio * 0.6;
      if (!sharp) {
        _returnShot = stage?.snapshot(rest.shift(-area.topLeft), _pixelRatio);
      }
      image = _returnShot ?? shot.image;
    }

    _flies = false;
    if (!_calm &&
        shot != null &&
        from != null &&
        !from.isEmpty &&
        now != null &&
        image != null) {
      _flies = true;
      _from = from;
      _fromRadius = shot.radius;
      _to = now;
      _image = image;
    }
    _phase = _Phase.closing;
    _notify();
  }

  // ── отрисовка ─────────────────────────────────────────────────────────────

  Widget? _flier() {
    if (!_flies || _route.offstage) return null;
    final from = _from, to = _to, image = _image;
    if (from == null || to == null || image == null) return null;
    final double flight;
    if (_phase == _Phase.opening) {
      flight = photoOpenFrame(_openMs).flight;
    } else if (_phase == _Phase.closing) {
      flight = photoCloseFrame(_closeMs).flight;
    } else {
      return null;
    }
    final radius = _fromRadius * (1 - flight.clamp(0.0, 1.0));
    return Positioned.fromRect(
      rect: Rect.lerp(from, to, flight)!,
      child: IgnorePointer(
        child: ClipRRect(
          key: const ValueKey<String>('photo-flier'),
          borderRadius: BorderRadius.circular(radius),
          child: RawImage(
            image: image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ticks,
      builder: (context, page) {
        final flier = _flier();
        return Stack(
          fit: StackFit.expand,
          children: [page!, ?flier],
        );
      },
      child: _PhotoFlightScope(host: this, child: widget.child),
    );
  }
}

class _PhotoFlightScope extends InheritedWidget {
  const _PhotoFlightScope({required this.host, required super.child});

  final _PhotoFlightState host;

  static _PhotoFlightState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PhotoFlightScope>()?.host;

  @override
  bool updateShouldNotify(_PhotoFlightScope oldWidget) =>
      !identical(host, oldWidget.host);
}

/// Фон просмотра: темнеет при открытии и светлеет под пальцем.
class PhotoFlightBackdrop extends StatelessWidget {
  const PhotoFlightBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final host = _PhotoFlightScope.maybeOf(context);
    if (host == null) return child;
    return AnimatedBuilder(
      animation: host.ticks,
      builder: (context, child) =>
          Opacity(opacity: host.backdrop.clamp(0.0, 1.0), child: child),
      child: child,
    );
  }
}

/// Кнопки просмотра: проявляются после кадра, [index] задаёт очередь.
class PhotoFlightChrome extends StatelessWidget {
  const PhotoFlightChrome({super.key, this.index = 0, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final host = _PhotoFlightScope.maybeOf(context);
    if (host == null) return child;
    return AnimatedBuilder(
      animation: host.ticks,
      builder: (context, child) {
        final opacity = host.chrome(index).clamp(0.0, 1.0);
        return IgnorePointer(
          // Погасшие кнопки не нажимаются: под пальцем их не видно.
          ignoring: opacity < 0.3,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: child,
    );
  }
}

/// Место кадра в просмотре: сюда прилетает снимок, отсюда кадр тянут вниз.
class PhotoFlightStage extends StatefulWidget {
  const PhotoFlightStage({
    super.key,
    this.canDismiss = true,
    this.returns = true,
    required this.child,
  });

  /// Можно ли закрыть жестом «вниз». Увеличенный кадр жест не закрывает:
  /// палец там двигает сам снимок.
  final bool canDismiss;

  /// На сцене тот же кадр, с миниатюры которого открыли просмотр: ему есть
  /// куда лететь обратно. Пролистали к другому — просмотр просто гаснет.
  final bool returns;

  final Widget child;

  @override
  State<PhotoFlightStage> createState() => _PhotoFlightStageState();
}

class _PhotoFlightStageState extends State<PhotoFlightStage> {
  final GlobalKey _paint = GlobalKey();
  _PhotoFlightState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = _PhotoFlightScope.maybeOf(context);
    if (identical(host, _host)) return;
    if (identical(_host?._stage, this)) _host?._stage = null;
    _host = host;
    host?._stage = this;
  }

  @override
  void dispose() {
    if (identical(_host?._stage, this)) _host?._stage = null;
    super.dispose();
  }

  Rect? rect(RenderObject ancestor) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
        box.getTransformTo(ancestor), Offset.zero & box.size);
  }

  /// Снимок куска сцены [crop] (в её координатах).
  ui.Image? snapshot(Rect crop, double pixelRatio) {
    final boundary = _paint.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    return unfoldSnapshot(boundary, crop, pixelRatio);
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) return widget.child;
    final drags = widget.canDismiss;
    return GestureDetector(
      onVerticalDragStart: drags ? (_) => host.beginDrag() : null,
      onVerticalDragUpdate: drags ? (details) => host.dragBy(details.delta) : null,
      onVerticalDragEnd: drags
          ? (details) =>
              host.endDrag(velocity: details.velocity.pixelsPerSecond.dy)
          : null,
      onVerticalDragCancel: drags ? () => host.endDrag(cancel: true) : null,
      child: AnimatedBuilder(
        animation: host.ticks,
        builder: (context, child) {
          final drag = host.stageDrag;
          return Opacity(
            opacity: host.stageOpacity.clamp(0.0, 1.0),
            child: Transform(
              transform: Matrix4.identity()
                ..translateByDouble(drag.shift.dx, drag.shift.dy, 0, 1)
                ..scaleByDouble(drag.scale, drag.scale, 1, 1),
              alignment: Alignment.center,
              child: child,
            ),
          );
        },
        child: RepaintBoundary(key: _paint, child: widget.child),
      ),
    );
  }
}
