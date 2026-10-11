import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'unfold_math.dart';

/// Переход «экран вырастает из нажатого».
///
/// Три движения, выбранные по макету 11.10.2026:
///  * окно нового экрана растёт из карточки или плитки, на которую нажали;
///  * общие элементы ([UnfoldShared]: обложка, аватар, имя) перелетают со
///    старого места на новое отдельно от окна;
///  * назад за пальцем — экран сжимается в карточку, едет за рукой и
///    складывается обратно в ту же плитку.
///
/// Стекла и размытия нет: растёт непрозрачная заливка самого элемента.
///
/// Как подключить:
/// ```dart
/// UnfoldSource(
///   fill: theme.cardSurface,
///   radius: 28,
///   builder: (context, source) => GestureDetector(
///     onTap: () => Navigator.of(context).push(
///       UnfoldRoute(source: source, builder: (_) => const DetailScreen()),
///     ),
///     child: card,
///   ),
/// )
/// ```
/// Без [UnfoldSource] маршрут работает простым проявлением — так открывается
/// экран, у которого на прежнем нет своей карточки (переход по уведомлению).

/// Как общий элемент меняет размер в полёте.
enum UnfoldFit {
  /// Картинка: рамка тянется к новым размерам, снимок заполняет её целиком.
  cover,

  /// Текст: снимок растёт равномерно по высоте, буквы не плющит.
  scale,
}

typedef UnfoldSourceBuilder = Widget Function(
    BuildContext context, UnfoldSourceState source);

Rect? _rectOf(BuildContext? context, RenderObject? ancestor) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (ancestor != null && !ancestor.attached) return null;
  return MatrixUtils.transformRect(
      box.getTransformTo(ancestor), Offset.zero & box.size);
}

ui.Image? _snapshotOf(BuildContext? context, double pixelRatio) {
  final boundary = context?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || !boundary.attached) return null;
  try {
    return boundary.toImageSync(pixelRatio: pixelRatio);
  } catch (_) {
    // Слой ещё не рисовался (элемент за краем списка): летим без снимка.
    return null;
  }
}

/// Правка состояния чужого виджета вне сборки кадра: маршрут уходит из
/// навигатора и посреди кадра тоже.
void _whenSafe(VoidCallback action) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.persistentCallbacks) {
    SchedulerBinding.instance.addPostFrameCallback((_) => action());
  } else {
    action();
  }
}

class _Nothing extends CustomClipper<Rect> {
  const _Nothing();

  @override
  Rect getClip(Size size) => Rect.zero;

  @override
  bool shouldReclip(_Nothing oldClipper) => false;
}

/// Прячет ребёнка, не выключая его отрисовку: слой остаётся живым, и с него
/// можно снять снимок. Прозрачность тут не годится — при нуле Flutter ребёнка
/// не рисует вовсе.
class _Vanish extends StatelessWidget {
  const _Vanish({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Обрезка «в ничто» заодно гасит касания; без неё виджет ведёт себя так,
    // будто обёртки нет.
    return ClipRect(
      clipper: hidden ? const _Nothing() : null,
      clipBehavior: hidden ? Clip.hardEdge : Clip.none,
      child: child,
    );
  }
}

/// То, из чего вырастает экран: карточка ленты, плитка, строка.
///
/// Сам ничего не рисует. Нужен маршруту, чтобы узнать место элемента, снять
/// с него снимок и спрятать его, пока экран открыт.
class UnfoldSource extends StatefulWidget {
  const UnfoldSource({
    super.key,
    required this.fill,
    this.radius = 28,
    required this.builder,
  });

  /// Заливка элемента: этим цветом растёт окно, пока экран не проявился.
  final Color fill;

  /// Скругление элемента.
  final double radius;

  final UnfoldSourceBuilder builder;

  /// Ближайший источник над [context] — для кнопок внутри карточки, которые
  /// открывают тот же экран, что и сама карточка.
  static UnfoldSourceState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<UnfoldSourceState>();

  @override
  State<UnfoldSource> createState() => UnfoldSourceState();
}

class UnfoldSourceState extends State<UnfoldSource> {
  final GlobalKey _boundary = GlobalKey();
  bool _hidden = false;

  /// Спрятан ли элемент: пока экран открыт, на его месте пусто.
  bool get hidden => _hidden;

  void _setHidden(bool value) {
    if (!mounted || _hidden == value) return;
    setState(() => _hidden = value);
  }

  List<UnfoldSharedState> _sharedInside() {
    final found = <UnfoldSharedState>[];
    if (!mounted) return found;
    void visit(Element element) {
      if (element is StatefulElement && element.state is UnfoldSharedState) {
        found.add(element.state as UnfoldSharedState);
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return _Vanish(
      hidden: _hidden,
      child: RepaintBoundary(
        key: _boundary,
        child: widget.builder(context, this),
      ),
    );
  }
}

/// Элемент, общий для старого и нового экрана: один и тот же [tag] стоит на
/// обложке в карточке и на обложке в открытой записи.
class UnfoldShared extends StatefulWidget {
  const UnfoldShared({
    super.key,
    required this.tag,
    this.radius = 0,
    this.fit = UnfoldFit.cover,
    required this.child,
  });

  final String tag;

  /// Скругление элемента на этом экране; в полёте переходит в скругление пары.
  final double radius;

  final UnfoldFit fit;
  final Widget child;

  @override
  State<UnfoldShared> createState() => UnfoldSharedState();
}

class UnfoldSharedState extends State<UnfoldShared> {
  final GlobalKey _boundary = GlobalKey();
  _UnfoldHost? _host;
  bool _hidden = false;

  /// Спрятан ли элемент: в полёте вместо него на экране его снимок.
  bool get hidden => _hidden;

  void _setHidden(bool value) {
    if (!mounted || _hidden == value) return;
    setState(() => _hidden = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = _UnfoldScope.maybeOf(context);
    if (identical(host, _host)) return;
    _host?.shared.remove(this);
    _host = host;
    if (host != null) {
      host.shared.add(this);
      // Экран ещё растёт: место занято летящим снимком.
      if (host.hidesNewShared) _hidden = true;
    }
  }

  @override
  void dispose() {
    _host?.shared.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Vanish(
      hidden: _hidden,
      child: RepaintBoundary(key: _boundary, child: widget.child),
    );
  }
}

/// Блок нового экрана, который проявляется в свой черёд: чем больше [index],
/// тем позже. Вне [UnfoldRoute] ничего не делает.
class UnfoldStagger extends StatelessWidget {
  const UnfoldStagger({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final host = _UnfoldScope.maybeOf(context);
    if (host == null) return child;
    return AnimatedBuilder(
      animation: host.ticks,
      builder: (context, child) {
        final item = host.item(index);
        return Opacity(
          opacity: item.opacity,
          child: Transform.translate(
            offset: Offset(0, item.shift),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Что новый экран знает о своём переходе.
abstract class _UnfoldHost {
  final Set<UnfoldSharedState> shared = <UnfoldSharedState>{};

  Listenable get ticks;

  bool get hidesNewShared;

  ({double opacity, double shift}) item(int index);
}

class _UnfoldScope extends InheritedWidget {
  const _UnfoldScope({required this.host, required super.child});

  final _UnfoldHost host;

  static _UnfoldHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UnfoldScope>()?.host;

  @override
  bool updateShouldNotify(_UnfoldScope oldWidget) =>
      !identical(host, oldWidget.host);
}

/// Общий элемент в полёте.
class _Flier {
  _Flier({
    required this.tag,
    required this.fit,
    required this.from,
    required this.fromRadius,
    this.image,
  });

  final String tag;
  final UnfoldFit fit;

  /// Место на старом экране (в ленте).
  Rect from;
  double fromRadius;

  /// Место на новом экране; пока пары нет — пусто.
  Rect? to;
  double toRadius = 0;

  ui.Image? image;

  /// Снимок того же элемента на дальнем конце пути и тот, с кого его снять.
  /// Нужен тексту: имя в карточке и в шапке экрана набрано по-разному, и
  /// в полёте одно начертание перетекает в другое. Снимается не сразу —
  /// дальний конец сперва должен хоть раз нарисоваться.
  ui.Image? far;
  UnfoldSharedState? farFrom;

  /// Высота и левый верхний угол текста в полёте.
  ({Offset corner, double height}) textAt(double flight) {
    final target = to ?? from;
    return (
      corner: Offset.lerp(from.topLeft, target.topLeft, flight)!,
      height: from.height + (target.height - from.height) * flight,
    );
  }

  Rect rectAt(double flight) {
    final target = to;
    if (target == null) return from;
    if (fit == UnfoldFit.cover) return Rect.lerp(from, target, flight)!;
    // Текст: высота меняется плавно, ширина идёт за пропорцией снимка.
    final height = from.height + (target.height - from.height) * flight;
    final snap = image;
    final aspect = snap != null && snap.height > 0
        ? snap.width / snap.height
        : (from.height > 0 ? from.width / from.height : 1.0);
    final corner = Offset.lerp(from.topLeft, target.topLeft, flight)!;
    return corner & Size(height * aspect, height);
  }

  double radiusAt(double flight) =>
      fromRadius + (toRadius - fromRadius) * flight.clamp(0.0, 1.0);

  void dispose() {
    image?.dispose();
    image = null;
    far?.dispose();
    far = null;
    farFrom = null;
  }
}

enum _Phase { opening, open, dragging, settling, closing }

/// Маршрут, который раскрывает экран из [source].
class UnfoldRoute<T> extends PageRoute<T> {
  UnfoldRoute({
    required this.builder,
    UnfoldSourceState? source,
    super.settings,
  }) : _source = source;

  final WidgetBuilder builder;
  UnfoldSourceState? _source;

  /// Растём из элемента или просто проявляемся.
  bool _grows = false;

  /// В системе включено «уменьшить движение»: ни роста, ни жеста.
  bool _calm = false;

  Rect? _sourceRect;
  double _sourceRadius = 0;
  Color _fill = const Color(0x00000000);
  ui.Image? _ghost;
  final List<_Flier> _fliers = <_Flier>[];

  /// Новый экран уже разложен, и пары общих элементов найдены.
  bool _targetsKnown = false;

  _Phase _phase = _Phase.opening;

  /// Откуда складываемся: полный экран либо место под пальцем.
  Rect? _closeFrom;
  double _closeFromRadius = 0;

  /// Значение хода маршрута в момент закрытия: от него считается время.
  double _popValue = 1;

  /// Докуда долетели общие элементы, если закрыли посреди открытия.
  double _flightCap = 1;

  _UnfoldTransitionState? _view;

  @override
  Duration get transitionDuration => Duration(
      milliseconds:
          (_grows ? UnfoldTiming.openMs : UnfoldTiming.fadeInMs).round());

  @override
  Duration get reverseTransitionDuration => Duration(
      milliseconds:
          (_grows ? UnfoldTiming.closeMs : UnfoldTiming.fadeOutMs).round());

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  RenderObject? get _overlayBox => navigator?.overlay?.context.findRenderObject();

  double get _pixelRatio {
    final context = navigator?.context;
    return context == null
        ? 1
        : MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  }

  @override
  void install() {
    _measureSource();
    super.install();
  }

  /// Всё, что надо знать о карточке, снимается в момент нажатия: через кадр
  /// она уже спрятана под окном.
  void _measureSource() {
    final source = _source;
    final context = navigator?.context;
    if (context == null) return;
    _calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_calm || source == null || !source.mounted) return;
    final rect = _rectOf(source._boundary.currentContext, _overlayBox);
    if (rect == null || rect.isEmpty) return;

    _grows = true;
    _sourceRect = rect;
    _sourceRadius = source.widget.radius;
    _fill = source.widget.fill;
    _ghost = _snapshotOf(source._boundary.currentContext, _pixelRatio);
    for (final shared in source._sharedInside()) {
      final place = _rectOf(shared._boundary.currentContext, _overlayBox);
      if (place == null || place.isEmpty) continue;
      _fliers.add(_Flier(
        tag: shared.widget.tag,
        fit: shared.widget.fit,
        from: place,
        fromRadius: shared.widget.radius,
        image: _snapshotOf(shared._boundary.currentContext, _pixelRatio),
      ));
    }
  }

  /// Карточку прячем не в момент нажатия, а после первого кадра маршрута:
  /// этот кадр Flutter не рисует вовсе (меряет героев), и спрятанная раньше
  /// карточка оставила бы на его месте дыру.
  void _hideSource() {
    if (_grows) _source?._setHidden(true);
  }

  void _showSource() => _source?._setHidden(false);

  /// Куда лететь общим элементам, известно только после первой раскладки
  /// нового экрана.
  void _resolveTargets(_UnfoldTransitionState view) {
    if (_phase != _Phase.opening) return;
    final page = view._pageKey.currentContext?.findRenderObject();
    for (final flier in _fliers) {
      if (flier.to != null) continue;
      for (final shared in view.shared) {
        if (shared.widget.tag != flier.tag || !shared.mounted) continue;
        final place = _rectOf(shared._boundary.currentContext, page);
        if (place == null || place.isEmpty) continue;
        flier.to = place;
        flier.toRadius = shared.widget.radius;
        if (flier.fit == UnfoldFit.scale) flier.farFrom = shared;
        break;
      }
    }
    _targetsKnown = true;
    // Элемент нового экрана без пары в карточке никто не привезёт: пусть
    // стоит на месте с самого начала.
    final arriving = {
      for (final flier in _fliers)
        if (flier.to != null && flier.image != null) flier.tag,
    };
    for (final shared in view.shared) {
      if (!arriving.contains(shared.widget.tag)) shared._setHidden(false);
    }
  }

  void _finishOpening(_UnfoldTransitionState view) {
    if (_phase != _Phase.opening) return;
    _phase = _Phase.open;
    for (final flier in _fliers) {
      flier.dispose();
    }
    _fliers.clear();
    for (final shared in view.shared) {
      shared._setHidden(false);
    }
    view._refresh();
  }

  /// Держит маршрут чуть не дойдя до конца: пока ход равен единице, Flutter
  /// считает экран непрозрачным и не рисует ленту под ним.
  void _holdOpen(bool hold) {
    final ticker = controller;
    if (ticker == null) return;
    ticker.value = hold ? 0.999 : 1.0;
  }

  @override
  bool didPop(T? result) {
    _beginClose();
    return super.didPop(result);
  }

  void _beginClose() {
    final view = _view;
    final was = _phase;
    _popValue = controller?.value ?? 1;
    if (_popValue <= 0) _popValue = 1;
    if (!_grows || view == null || !view.mounted) {
      _phase = _Phase.closing;
      return;
    }

    final source = _source;
    final fresh = source != null && source.mounted
        ? _rectOf(source._boundary.currentContext, _overlayBox)
        : null;
    if (fresh != null && !fresh.isEmpty) {
      _sourceRect = fresh;
    } else if (source == null || !source.mounted) {
      // Карточки больше нет (запись удалили): складываться некуда.
      _sourceRect = null;
    }

    if (was == _Phase.opening) {
      // Закрыли посреди открытия: возвращаем то же окно и те же снимки.
      final now = view._frameNow();
      _closeFrom = now.rect;
      _closeFromRadius = now.radius;
      _flightCap = now.flight.clamp(0.0, 1.0);
    } else {
      _closeFrom ??= view._fullRect;
      _collectReturning(view);
      view._chaseTries = 0;
    }
    _phase = _Phase.closing;
  }

  /// Общие элементы летят обратно: снимок берём с открытого экрана, где они
  /// сейчас стоят, а цель — их место в карточке.
  void _collectReturning(_UnfoldTransitionState view) {
    for (final flier in _fliers) {
      flier.dispose();
    }
    _fliers.clear();
    final source = _source;
    if (_sourceRect == null || source == null || !source.mounted) return;
    final homes = <String, UnfoldSharedState>{
      for (final shared in source._sharedInside()) shared.widget.tag: shared,
    };
    for (final shared in view.shared) {
      final home = homes[shared.widget.tag];
      if (home == null || !shared.mounted) continue;
      final here = _rectOf(shared._boundary.currentContext, _overlayBox);
      final there = _rectOf(home._boundary.currentContext, _overlayBox);
      if (here == null || there == null || here.isEmpty || there.isEmpty) {
        continue;
      }
      final image = _snapshotOf(shared._boundary.currentContext, _pixelRatio);
      if (image == null) continue;
      _fliers.add(_Flier(
        tag: shared.widget.tag,
        fit: shared.widget.fit,
        from: there,
        fromRadius: home.widget.radius,
        image: image,
      )
        ..to = here
        ..toRadius = shared.widget.radius
        ..farFrom = shared.widget.fit == UnfoldFit.scale ? home : null);
      shared._setHidden(true);
    }
    _flightCap = 1;
  }

  /// Снимает дальний конец текста, как только тот нарисовался. Возвращает
  /// true, пока ждать ещё есть кого.
  bool _captureFar() {
    var waiting = false;
    for (final flier in _fliers) {
      final from = flier.farFrom;
      if (from == null || flier.far != null) continue;
      if (!from.mounted) {
        flier.farFrom = null;
        continue;
      }
      flier.far = _snapshotOf(from._boundary.currentContext, _pixelRatio);
      if (flier.far == null) waiting = true;
    }
    return waiting;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return _UnfoldTransition(route: this, animation: animation, child: child);
  }

  @override
  void dispose() {
    final source = _source;
    _source = null;
    if (source != null && _grows) {
      _whenSafe(() => source._setHidden(false));
    }
    _ghost?.dispose();
    _ghost = null;
    for (final flier in _fliers) {
      flier.dispose();
    }
    _fliers.clear();
    super.dispose();
  }
}

/// Маршрут для экрана, у которого плитка есть не всегда.
///
/// Нажали плитку — экран вырастет из неё. Пришли иначе (уведомление, кнопка
/// без своей плитки) — откроется штатным переходом Material, каким открывался
/// раньше, со своим системным жестом «назад».
Route<T> unfoldFrom<T>(
  UnfoldSourceState? source,
  WidgetBuilder builder, {
  RouteSettings? settings,
}) {
  if (source != null && source.mounted) {
    return UnfoldRoute<T>(source: source, builder: builder, settings: settings);
  }
  return MaterialPageRoute<T>(builder: builder, settings: settings);
}

class _UnfoldTransition extends StatefulWidget {
  const _UnfoldTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final UnfoldRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_UnfoldTransition> createState() => _UnfoldTransitionState();
}

class _UnfoldTransitionState extends State<_UnfoldTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements _UnfoldHost {
  final GlobalKey _pageKey = GlobalKey();

  @override
  final Set<UnfoldSharedState> shared = <UnfoldSharedState>{};

  late final AnimationController _settle;
  late final Listenable _ticks;

  Size _screen = Size.zero;

  // Экран под пальцем.
  Offset _dragDelta = Offset.zero;
  bool _dragFromRight = false;
  Offset? _backStart;

  UnfoldRoute<dynamic> get _route => widget.route;

  Rect get _fullRect => Offset.zero & _screen;

  @override
  Listenable get ticks => _ticks;

  @override
  bool get hidesNewShared =>
      _route._grows && _route._phase == _Phase.opening;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: UnfoldTiming.settleMs.round()),
    );
    _ticks = Listenable.merge(<Listenable>[widget.animation, _settle]);
    _route._view = this;
    widget.animation.addStatusListener(_onStatus);
    WidgetsBinding.instance.addObserver(this);
    if (_route._grows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _route._hideSource();
        _route._resolveTargets(this);
        _refresh();
      });
    } else if (widget.animation.isCompleted) {
      _route._phase = _Phase.open;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.animation.removeStatusListener(_onStatus);
    if (identical(_route._view, this)) _route._view = null;
    _settle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _route._phase == _Phase.opening) {
      _route._finishOpening(this);
    }
    // Окно сложилось: карточка возвращается в том же кадре, где навигатор
    // уберёт маршрут. Ждать его dispose нельзя — он приходит кадром позже,
    // и на месте записи мигала бы пустота.
    if (status == AnimationStatus.dismissed) _route._showSource();
  }

  // ── время перехода ────────────────────────────────────────────────────────

  /// Сколько прошло до первого нарисованного кадра. Первый кадр маршрута
  /// стоит за сценой, и без поправки окно начинало бы не с карточки, а уже
  /// чуть выросшим — заметным скачком.
  double? _openLead;

  double get _openMs {
    final passed = widget.animation.value * UnfoldTiming.openMs;
    if (_route.offstage) return 0;
    final lead = _openLead ??= passed;
    return passed - lead;
  }

  double get _closeMs =>
      (1 - widget.animation.value / _route._popValue).clamp(0.0, 1.0) *
      UnfoldTiming.closeMs;

  UnfoldFrame _frameNow() {
    final route = _route;
    final full = _fullRect;
    // Окно стоит или едет под пальцем: ни заливки, ни призрака, ни полёта.
    UnfoldFrame at(Rect rect, double radius) => UnfoldFrame(
        rect: rect, radius: radius, tint: 0, ghost: 0, flight: 1);

    final source = route._sourceRect;
    switch (route._phase) {
      case _Phase.opening:
        if (!route._grows || source == null) return at(full, 0);
        return unfoldOpenFrame(
          ms: _openMs,
          source: source,
          full: full,
          sourceRadius: route._sourceRadius,
        );
      case _Phase.open:
        return at(full, 0);
      case _Phase.dragging:
        final drag = unfoldDragFrame(
            delta: _dragDelta, screen: _screen, fromRight: _dragFromRight);
        return at(drag.rect, drag.radius);
      case _Phase.settling:
        final drag = unfoldDragFrame(
            delta: _dragDelta, screen: _screen, fromRight: _dragFromRight);
        final left = 1 -
            unfoldSpring(_settle.value * UnfoldTiming.settleMs,
                omega: 26, zeta: 1);
        return at(Rect.lerp(full, drag.rect, left)!, drag.radius * left);
      case _Phase.closing:
        // Складываться некуда: окно гаснет там, где его отпустили.
        if (!route._grows || source == null) {
          return at(route._closeFrom ?? full, route._closeFromRadius);
        }
        return unfoldCloseFrame(
          ms: _closeMs,
          source: source,
          from: route._closeFrom ?? full,
          sourceRadius: route._sourceRadius,
          fromRadius: route._closeFromRadius,
        );
    }
  }

  /// Прозрачность окна целиком: нужна только там, где оно не растёт.
  double get _windowOpacity {
    final route = _route;
    final fades = !route._grows ||
        (route._phase == _Phase.closing && route._sourceRect == null);
    if (!fades) return 1;
    return switch (route._phase) {
      _Phase.opening => widget.animation.value,
      _Phase.closing =>
        (widget.animation.value / route._popValue).clamp(0.0, 1.0),
      _ => 1,
    };
  }

  @override
  ({double opacity, double shift}) item(int index) {
    final route = _route;
    if (!route._grows) return (opacity: 1, shift: 0);
    // Пока места общих элементов не сняты, блоки стоят без сдвига: иначе
    // аватар в шапке померился бы на 18 точек ниже своего места.
    if (route._phase == _Phase.opening && !route._targetsKnown) {
      return (opacity: 0, shift: 0);
    }
    return switch (route._phase) {
      _Phase.opening => unfoldItemIn(_openMs, index),
      _Phase.closing => (opacity: unfoldItemOutOpacity(_closeMs), shift: 0),
      _ => (opacity: 1, shift: 0),
    };
  }

  // ── жест «назад» ──────────────────────────────────────────────────────────

  bool get _canDrag =>
      !_route._calm &&
      _route._phase == _Phase.open &&
      _route.isCurrent &&
      _route.popGestureEnabled;

  bool _beginDrag({required bool fromRight}) {
    if (!_canDrag) return false;
    _dragFromRight = fromRight;
    _dragDelta = Offset.zero;
    _route._phase = _Phase.dragging;
    _route.navigator?.didStartUserGesture();
    _route._holdOpen(true);
    _refresh();
    return true;
  }

  void _dragTo(Offset delta) {
    if (_route._phase != _Phase.dragging) return;
    setState(() => _dragDelta = delta);
  }

  void _endDrag({bool? commit}) {
    final route = _route;
    if (route._phase != _Phase.dragging) return;
    final drag = unfoldDragFrame(
        delta: _dragDelta, screen: _screen, fromRight: _dragFromRight);
    final closes = commit ?? unfoldDragCommits(drag.progress);
    final navigator = route.navigator;
    if (closes && navigator != null) {
      route._closeFrom = drag.rect;
      route._closeFromRadius = drag.radius;
      navigator.pop();
      navigator.didStopUserGesture();
      return;
    }
    route._phase = _Phase.settling;
    _settle.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || route._phase != _Phase.settling) return;
      route._phase = _Phase.open;
      route._holdOpen(false);
      route.navigator?.didStopUserGesture();
      _refresh();
    });
  }

  // Системный жест Android (предиктивный «назад»).

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent) return false;
    _backStart = backEvent.touchOffset;
    return _beginDrag(fromRight: backEvent.swipeEdge == SwipeEdge.right);
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    // Ход берём из доли жеста, которую считает сама система, а не из
    // координат: расстояние до срабатывания у прошивок своё.
    final pull = backEvent.progress * UnfoldTiming.dragTravel;
    final start = _backStart;
    final now = backEvent.touchOffset;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final drop =
        start != null && now != null ? (now.dy - start.dy) / ratio : 0.0;
    _dragTo(Offset(_dragFromRight ? -pull : pull, drop));
  }

  @override
  void handleCommitBackGesture() => _endDrag(commit: true);

  @override
  void handleCancelBackGesture() => _endDrag(commit: false);

  /// На iPhone системного жеста нет — ведём сами полосой у левого края.
  bool get _ownsEdgeSwipe => defaultTargetPlatform != TargetPlatform.android;

  // ── отрисовка ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _screen = box.biggest;
      return AnimatedBuilder(
        animation: _ticks,
        builder: (context, page) => _buildFrame(context, page!),
        child: _UnfoldScope(
          host: this,
          child: RepaintBoundary(key: _pageKey, child: widget.child),
        ),
      );
    });
  }

  bool _chasing = false;
  int _chaseTries = 0;

  /// После кадра пробует снять дальний конец текста: до первой отрисовки
  /// снимать не с чего. Несколько попыток — и хватит, летим со старым.
  void _chaseFar() {
    if (_chasing || _chaseTries >= 8) return;
    final pending = _route._fliers
        .any((flier) => flier.farFrom != null && flier.far == null);
    if (!pending) return;
    _chasing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chasing = false;
      _chaseTries++;
      if (!mounted) return;
      _route._captureFar();
      _refresh();
    });
  }

  /// Текст в полёте: растёт равномерно, а начертание старого места
  /// перетекает в начертание нового в начале пути.
  Widget _textFlier(_Flier flier, double flight, {required bool opening}) {
    final at = flier.textAt(flight);
    final toward = opening ? flight : 1 - flight;
    final far = flier.far;
    final blend =
        far == null ? 0.0 : ((toward - 0.12) / 0.22).clamp(0.0, 1.0);
    Widget glyphs(ui.Image image, double opacity, String side) => Opacity(
          opacity: opacity,
          child: RawImage(
            key: ValueKey<String>('unfold-flier-${flier.tag}-$side'),
            image: image,
            height: at.height,
            fit: BoxFit.fitHeight,
            alignment: Alignment.topLeft,
            filterQuality: FilterQuality.medium,
          ),
        );
    return Positioned(
      left: at.corner.dx,
      top: at.corner.dy,
      child: IgnorePointer(
        child: Stack(
          key: ValueKey<String>('unfold-flier-${flier.tag}'),
          clipBehavior: Clip.none,
          children: [
            glyphs(flier.image!, 1 - blend, 'near'),
            if (far != null) glyphs(far, blend, 'far'),
          ],
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context, Widget page) {
    final route = _route;
    final frame = _frameNow();
    final full = _fullRect;
    final scale = full.width > 0 ? frame.rect.width / full.width : 1.0;
    final resting = route._phase == _Phase.open;
    final source = route._sourceRect;
    final ghost = route._ghost;
    // Летящие стартуют ровно со своих мест и не выходят за то, докуда успели
    // долететь, если экран закрыли посреди открытия.
    final flight = route._phase == _Phase.closing
        ? frame.flight * route._flightCap
        : frame.flight;
    final flying = route._grows &&
        (route._phase == _Phase.opening || route._phase == _Phase.closing);

    if (flying && !route.offstage) _chaseFar();
    final moving = route._phase == _Phase.dragging ||
        route._phase == _Phase.settling ||
        route._phase == _Phase.closing;
    // До первой раскладки пары ещё не известны: все летящие стоят на своих
    // местах. Дальше летят только те, кому есть куда.
    final fliers = [
      for (final flier in route._fliers)
        if (flier.image != null && (flier.to != null || !route._targetsKnown))
          flier,
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: frame.rect,
          child: Opacity(
            opacity: _windowOpacity,
            child: ClipRRect(
              key: const ValueKey<String>('unfold-window'),
              borderRadius: BorderRadius.circular(frame.radius),
              clipBehavior: resting ? Clip.none : Clip.antiAlias,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: full.width,
                maxWidth: full.width,
                minHeight: full.height,
                maxHeight: full.height,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AbsorbPointer(absorbing: moving, child: page),
                      if (frame.tint > 0)
                        IgnorePointer(
                          child: ColoredBox(
                            color: route._fill.withValues(
                                alpha: route._fill.a * frame.tint),
                          ),
                        ),
                      if (frame.ghost > 0 && ghost != null && source != null)
                        Positioned(
                          left: 0,
                          top: 0,
                          width: full.width,
                          height: full.width * source.height / source.width,
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _GhostPainter(
                                image: ghost,
                                opacity: frame.ghost,
                                holes: [
                                  for (final flier in fliers)
                                    RRect.fromRectAndRadius(
                                      flier.from.shift(-source.topLeft),
                                      Radius.circular(flier.fromRadius),
                                    ),
                                ],
                                sourceSize: source.size,
                              ),
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
        if (flying)
          for (final flier in fliers)
            if (flier.fit == UnfoldFit.scale)
              _textFlier(flier, flight,
                  opening: route._phase == _Phase.opening)
            else
            Positioned.fromRect(
              rect: flier.rectAt(flight),
              child: IgnorePointer(
                child: ClipRRect(
                  key: ValueKey<String>('unfold-flier-${flier.tag}'),
                  borderRadius: BorderRadius.circular(flier.radiusAt(flight)),
                  child: RawImage(
                    image: flier.image,
                    fit: flier.fit == UnfoldFit.cover
                        ? BoxFit.cover
                        : BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
        if (_ownsEdgeSwipe && !route._calm)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _beginDrag(fromRight: false),
              onHorizontalDragUpdate: (details) =>
                  _dragTo(_dragDelta + details.delta),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: () => _endDrag(commit: false),
            ),
          ),
      ],
    );
  }
}

/// Снимок содержимого карточки внутри окна. На местах общих элементов —
/// дыры: они летят отдельно, и дважды на экране их быть не должно.
class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.image,
    required this.opacity,
    required this.holes,
    required this.sourceSize,
  });

  final ui.Image image;
  final double opacity;
  final List<RRect> holes;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.saveLayer(
        area, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0, 1)));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      area,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (holes.isNotEmpty && sourceSize.width > 0) {
      final grow = size.width / sourceSize.width;
      final eraser = Paint()..blendMode = BlendMode.clear;
      for (final hole in holes) {
        canvas.drawRRect(
          RRect.fromLTRBXY(
            hole.left * grow,
            hole.top * grow,
            hole.right * grow,
            hole.bottom * grow,
            hole.tlRadiusX * grow,
            hole.tlRadiusY * grow,
          ),
          eraser,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GhostPainter oldDelegate) =>
      oldDelegate.opacity != opacity ||
      !identical(oldDelegate.image, image) ||
      oldDelegate.holes.length != holes.length;
}
