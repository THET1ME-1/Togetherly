import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'unfold_math.dart';
import 'unfold_touch.dart';

part 'unfold_auto.dart';

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

/// Экран сам называет цвет растущего окна.
///
/// Общий переход темы заливает окно поверхностью схемы — на ней стоит почти
/// всё приложение. Чёрный экран (плеер, камера, сканер) под такой заливкой
/// дал бы светлую вспышку, поэтому он оборачивает себя в [UnfoldTint]. У
/// экрана, открытого из своей плитки, заливку по-прежнему задаёт плитка.
class UnfoldTint extends StatelessWidget {
  const UnfoldTint({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  /// То же одной строкой из `build` экрана, когда оборачивать неудобно.
  static void claim(BuildContext context, Color color) =>
      _UnfoldScope.maybeOf(context)?.claimFill(color);

  @override
  Widget build(BuildContext context) {
    claim(context, color);
    return child;
  }
}

/// Что новый экран знает о своём переходе.
abstract class _UnfoldHost {
  final Set<UnfoldSharedState> shared = <UnfoldSharedState>{};

  Listenable get ticks;

  bool get hidesNewShared;

  /// Экран просит залить окно своим цветом.
  void claimFill(Color color);

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

/// Откуда растёт экран: плитка, обёрнутая в [UnfoldSource], либо место
/// нажатия, найденное само (см. `unfold_auto.dart`).
abstract class _UnfoldOrigin {
  /// Элемент ещё на экране: есть куда складываться.
  bool get alive;

  /// Место элемента в координатах [overlay].
  Rect? rect(RenderObject? overlay);

  double get radius;

  /// Этим цветом залито окно, пока экран не проявился.
  Color get fill;

  /// Снимок элемента: проступает сквозь заливку в начале и в конце пути.
  ui.Image? ghost(double pixelRatio);

  /// Снимок стоит переснять, когда экран открылся: в момент нажатия кнопка
  /// подсвечена, и при возврате эта подсветка мигнула бы.
  bool get reghosts;

  List<UnfoldSharedState> shared();

  void hide();

  void show();
}

class _SourceOrigin implements _UnfoldOrigin {
  _SourceOrigin(this.source);

  final UnfoldSourceState source;

  @override
  bool get alive => source.mounted;

  @override
  Rect? rect(RenderObject? overlay) =>
      source.mounted ? _rectOf(source._boundary.currentContext, overlay) : null;

  @override
  double get radius => source.widget.radius;

  @override
  Color get fill => source.widget.fill;

  @override
  ui.Image? ghost(double pixelRatio) =>
      _snapshotOf(source._boundary.currentContext, pixelRatio);

  @override
  bool get reghosts => false;

  @override
  List<UnfoldSharedState> shared() => source._sharedInside();

  @override
  void hide() => source._setHidden(true);

  @override
  void show() => source._setHidden(false);
}

/// Состояние одного перехода. Живёт рядом с маршрутом: у [UnfoldRoute] своё,
/// у обычного маршрута Material его держит [UnfoldPageTransitionsBuilder].
class _UnfoldSession {
  _UnfoldSession(this.route, {_UnfoldOrigin? origin}) : _origin = origin;

  final PageRoute<dynamic> route;
  _UnfoldOrigin? _origin;

  /// Сколько длится ход маршрута туда и обратно: от них считается время.
  double openMs = UnfoldTiming.openMs;
  double closeMs = UnfoldTiming.closeMs;

  /// Растём из элемента или просто проявляемся.
  bool grows = false;

  /// В системе включено «уменьшить движение»: ни роста, ни жеста.
  bool calm = false;

  /// Сессию завёл строитель темы: закрытие она узнаёт по ходу маршрута и
  /// убирает за собой вместе с виджетом перехода.
  bool auto = false;

  Rect? sourceRect;
  double sourceRadius = 0;
  Color fill = const Color(0x00000000);
  ui.Image? ghost;
  final List<_Flier> fliers = <_Flier>[];

  /// Новый экран уже разложен, и пары общих элементов найдены.
  bool targetsKnown = false;

  _Phase phase = _Phase.opening;

  /// Откуда складываемся: полный экран либо место под пальцем.
  Rect? closeFrom;
  double closeFromRadius = 0;

  /// Значение хода маршрута в момент закрытия: от него считается время.
  double popValue = 1;

  /// Докуда долетели общие элементы, если закрыли посреди открытия.
  double flightCap = 1;

  _UnfoldTransitionState? view;

  RenderObject? get _overlayBox =>
      route.navigator?.overlay?.context.findRenderObject();

  double get _pixelRatio {
    final context = route.navigator?.context;
    return context == null
        ? 1
        : MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  }

  /// Всё, что надо знать о карточке, снимается в момент нажатия: через кадр
  /// она уже спрятана под окном.
  void measure() {
    final origin = _origin;
    final context = route.navigator?.context;
    if (context == null) return;
    calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (calm || origin == null || !origin.alive) return;
    final rect = origin.rect(_overlayBox);
    if (rect == null || rect.isEmpty) return;

    grows = true;
    sourceRect = rect;
    sourceRadius = origin.radius;
    fill = origin.fill;
    ghost = origin.ghost(_pixelRatio);
    for (final shared in origin.shared()) {
      final place = _rectOf(shared._boundary.currentContext, _overlayBox);
      if (place == null || place.isEmpty) continue;
      fliers.add(_Flier(
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
  void hideSource() {
    if (grows) _origin?.hide();
  }

  void showSource() => _origin?.show();

  /// Куда лететь общим элементам, известно только после первой раскладки
  /// нового экрана.
  void resolveTargets(_UnfoldTransitionState view) {
    if (phase != _Phase.opening) return;
    final page = view._pageKey.currentContext?.findRenderObject();
    for (final flier in fliers) {
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
    targetsKnown = true;
    // Элемент нового экрана без пары в карточке никто не привезёт: пусть
    // стоит на месте с самого начала.
    final arriving = {
      for (final flier in fliers)
        if (flier.to != null && flier.image != null) flier.tag,
    };
    for (final shared in view.shared) {
      if (!arriving.contains(shared.widget.tag)) shared._setHidden(false);
    }
  }

  void finishOpening(_UnfoldTransitionState view) {
    if (phase != _Phase.opening) return;
    phase = _Phase.open;
    for (final flier in fliers) {
      flier.dispose();
    }
    fliers.clear();
    for (final shared in view.shared) {
      shared._setHidden(false);
    }
    final origin = _origin;
    if (grows && origin != null && origin.reghosts && origin.alive) {
      final fresh = origin.ghost(_pixelRatio);
      if (fresh != null) {
        ghost?.dispose();
        ghost = fresh;
      }
    }
    view._refresh();
  }

  /// Держит маршрут чуть не дойдя до конца: пока ход равен единице, Flutter
  /// считает экран непрозрачным и не рисует ленту под ним.
  void holdOpen(bool hold) {
    if (!route.isActive) return;
    route.handleUpdateBackGestureProgress(progress: hold ? 0.999 : 1.0);
  }

  void beginClose() {
    if (phase == _Phase.closing) return;
    final view = this.view;
    final was = phase;
    popValue = route.animation?.value ?? 1;
    if (popValue <= 0) popValue = 1;
    if (!grows || view == null || !view.mounted) {
      phase = _Phase.closing;
      return;
    }

    final origin = _origin;
    final fresh =
        origin != null && origin.alive ? origin.rect(_overlayBox) : null;
    if (fresh != null && !fresh.isEmpty) {
      sourceRect = fresh;
    } else if (origin == null || !origin.alive) {
      // Карточки больше нет (запись удалили): складываться некуда.
      sourceRect = null;
    }

    if (was == _Phase.opening) {
      // Закрыли посреди открытия: возвращаем то же окно и те же снимки.
      final now = view._frameNow();
      closeFrom = now.rect;
      closeFromRadius = now.radius;
      flightCap = now.flight.clamp(0.0, 1.0);
    } else {
      closeFrom ??= view._fullRect;
      _collectReturning(view);
      view._chaseTries = 0;
    }
    phase = _Phase.closing;
  }

  /// Общие элементы летят обратно: снимок берём с открытого экрана, где они
  /// сейчас стоят, а цель — их место в карточке.
  void _collectReturning(_UnfoldTransitionState view) {
    for (final flier in fliers) {
      flier.dispose();
    }
    fliers.clear();
    final origin = _origin;
    if (sourceRect == null || origin == null || !origin.alive) return;
    final homes = <String, UnfoldSharedState>{
      for (final shared in origin.shared()) shared.widget.tag: shared,
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
      fliers.add(_Flier(
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
    flightCap = 1;
  }

  /// Снимает дальний конец текста, как только тот нарисовался. Возвращает
  /// true, пока ждать ещё есть кого.
  bool captureFar() {
    var waiting = false;
    for (final flier in fliers) {
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

  /// Отпускает снимки. Источник при этом возвращается на экран.
  void dispose() {
    final origin = _origin;
    _origin = null;
    if (origin != null && grows) {
      _whenSafe(origin.show);
    }
    ghost?.dispose();
    ghost = null;
    for (final flier in fliers) {
      flier.dispose();
    }
    fliers.clear();
  }
}

/// Маршрут, который раскрывает экран из [source].
class UnfoldRoute<T> extends PageRoute<T> {
  UnfoldRoute({
    required this.builder,
    UnfoldSourceState? source,
    super.settings,
  }) {
    _session = _UnfoldSession(
      this,
      origin: source == null ? null : _SourceOrigin(source),
    );
  }

  final WidgetBuilder builder;
  late final _UnfoldSession _session;

  @override
  Duration get transitionDuration => Duration(
      milliseconds: (_session.grows
              ? UnfoldTiming.openMs
              : UnfoldTiming.fadeInMs)
          .round());

  @override
  Duration get reverseTransitionDuration => Duration(
      milliseconds: (_session.grows
              ? UnfoldTiming.closeMs
              : UnfoldTiming.fadeOutMs)
          .round());

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  void install() {
    // Касание забирает эта плитка: общему переходу темы оно уже не нужно.
    UnfoldTouch.forget();
    _session.measure();
    super.install();
  }

  @override
  bool didPop(T? result) {
    _session.beginClose();
    return super.didPop(result);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return _UnfoldTransition(
        session: _session, animation: animation, child: child);
  }

  @override
  void dispose() {
    _session.dispose();
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
    required this.session,
    required this.animation,
    required this.child,
  });

  final _UnfoldSession session;
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

  _UnfoldSession get _route => widget.session;

  Rect get _fullRect => Offset.zero & _screen;

  @override
  Listenable get ticks => _ticks;

  @override
  bool get hidesNewShared =>
      _route.grows && _route.phase == _Phase.opening;

  @override
  void claimFill(Color color) {
    // Первый кадр маршрута стоит за сценой, так что цвет успевает встать до
    // первого видимого.
    if (_route.auto) _route.fill = color;
  }

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: UnfoldTiming.settleMs.round()),
    );
    _ticks = Listenable.merge(<Listenable>[widget.animation, _settle]);
    _route.view = this;
    widget.animation.addStatusListener(_onStatus);
    WidgetsBinding.instance.addObserver(this);
    if (_route.grows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _route.hideSource();
        _route.resolveTargets(this);
        _refresh();
      });
    } else if (widget.animation.isCompleted) {
      _route.phase = _Phase.open;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.animation.removeStatusListener(_onStatus);
    if (identical(_route.view, this)) _route.view = null;
    if (_route.auto) _route.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _route.phase == _Phase.opening) {
      _route.finishOpening(this);
    }
    // Обычный маршрут Material о закрытии не скажет: узнаём по развороту
    // хода. У [UnfoldRoute] к этому мигу закрытие уже начато из didPop.
    if (status == AnimationStatus.reverse) _route.beginClose();
    // Окно сложилось: карточка возвращается в том же кадре, где навигатор
    // уберёт маршрут. Ждать его dispose нельзя — он приходит кадром позже,
    // и на месте записи мигала бы пустота.
    if (status == AnimationStatus.dismissed) _route.showSource();
  }

  // ── время перехода ────────────────────────────────────────────────────────

  /// Сколько прошло до первого нарисованного кадра. Первый кадр маршрута
  /// стоит за сценой, и без поправки окно начинало бы не с карточки, а уже
  /// чуть выросшим — заметным скачком.
  double? _openLead;

  double get _openMs {
    final passed = widget.animation.value * _route.openMs;
    if (_route.route.offstage) return 0;
    final lead = _openLead ??= passed;
    return passed - lead;
  }

  double get _closeMs =>
      (1 - widget.animation.value / _route.popValue).clamp(0.0, 1.0) *
      _route.closeMs;

  UnfoldFrame _frameNow() {
    final route = _route;
    final full = _fullRect;
    // Окно стоит или едет под пальцем: ни заливки, ни призрака, ни полёта.
    UnfoldFrame at(Rect rect, double radius) => UnfoldFrame(
        rect: rect, radius: radius, tint: 0, ghost: 0, flight: 1);

    final source = route.sourceRect;
    switch (route.phase) {
      case _Phase.opening:
        if (!route.grows || source == null) return at(full, 0);
        return unfoldOpenFrame(
          ms: _openMs,
          source: source,
          full: full,
          sourceRadius: route.sourceRadius,
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
        if (!route.grows || source == null) {
          return at(route.closeFrom ?? full, route.closeFromRadius);
        }
        return unfoldCloseFrame(
          ms: _closeMs,
          source: source,
          from: route.closeFrom ?? full,
          sourceRadius: route.sourceRadius,
          fromRadius: route.closeFromRadius,
        );
    }
  }

  /// Прозрачность окна целиком: нужна только там, где оно не растёт.
  double get _windowOpacity {
    final route = _route;
    final fades = !route.grows ||
        (route.phase == _Phase.closing && route.sourceRect == null);
    if (!fades) return 1;
    return switch (route.phase) {
      _Phase.opening => widget.animation.value,
      _Phase.closing =>
        (widget.animation.value / route.popValue).clamp(0.0, 1.0),
      _ => 1,
    };
  }

  @override
  ({double opacity, double shift}) item(int index) {
    final route = _route;
    if (!route.grows) return (opacity: 1, shift: 0);
    // Пока места общих элементов не сняты, блоки стоят без сдвига: иначе
    // аватар в шапке померился бы на 18 точек ниже своего места.
    if (route.phase == _Phase.opening && !route.targetsKnown) {
      return (opacity: 0, shift: 0);
    }
    return switch (route.phase) {
      _Phase.opening => unfoldItemIn(_openMs, index),
      _Phase.closing => (opacity: unfoldItemOutOpacity(_closeMs), shift: 0),
      _ => (opacity: 1, shift: 0),
    };
  }

  // ── жест «назад» ──────────────────────────────────────────────────────────

  bool get _canDrag =>
      !_route.calm &&
      _route.phase == _Phase.open &&
      _route.route.isCurrent &&
      _route.route.popGestureEnabled;

  bool _beginDrag({required bool fromRight}) {
    if (!_canDrag) return false;
    _dragFromRight = fromRight;
    _dragDelta = Offset.zero;
    _route.phase = _Phase.dragging;
    _route.route.navigator?.didStartUserGesture();
    _route.holdOpen(true);
    _refresh();
    return true;
  }

  void _dragTo(Offset delta) {
    if (_route.phase != _Phase.dragging) return;
    setState(() => _dragDelta = delta);
  }

  void _endDrag({bool? commit}) {
    final route = _route;
    if (route.phase != _Phase.dragging) return;
    final drag = unfoldDragFrame(
        delta: _dragDelta, screen: _screen, fromRight: _dragFromRight);
    final closes = commit ?? unfoldDragCommits(drag.progress);
    final navigator = route.route.navigator;
    if (closes && navigator != null) {
      route.closeFrom = drag.rect;
      route.closeFromRadius = drag.radius;
      navigator.pop();
      navigator.didStopUserGesture();
      return;
    }
    route.phase = _Phase.settling;
    _settle.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || route.phase != _Phase.settling) return;
      route.phase = _Phase.open;
      route.holdOpen(false);
      route.route.navigator?.didStopUserGesture();
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
    final pending = _route.fliers
        .any((flier) => flier.farFrom != null && flier.far == null);
    if (!pending) return;
    _chasing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chasing = false;
      _chaseTries++;
      if (!mounted) return;
      _route.captureFar();
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
    final resting = route.phase == _Phase.open;
    final source = route.sourceRect;
    final ghost = route.ghost;
    // Летящие стартуют ровно со своих мест и не выходят за то, докуда успели
    // долететь, если экран закрыли посреди открытия.
    final flight = route.phase == _Phase.closing
        ? frame.flight * route.flightCap
        : frame.flight;
    final flying = route.grows &&
        (route.phase == _Phase.opening || route.phase == _Phase.closing);

    if (flying && !route.route.offstage) _chaseFar();
    final moving = route.phase == _Phase.dragging ||
        route.phase == _Phase.settling ||
        route.phase == _Phase.closing;
    // До первой раскладки пары ещё не известны: все летящие стоят на своих
    // местах. Дальше летят только те, кому есть куда.
    final fliers = [
      for (final flier in route.fliers)
        if (flier.image != null && (flier.to != null || !route.targetsKnown))
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
                            color: route.fill.withValues(
                                alpha: route.fill.a * frame.tint),
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
                  opening: route.phase == _Phase.opening)
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
        if (_ownsEdgeSwipe && !route.calm)
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
