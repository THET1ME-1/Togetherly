part of 'unfold_route.dart';

/// Место нажатия как источник: у него нет обёртки [UnfoldSource], поэтому
/// спрятать кнопку нечем — её закрывает само окно, а под сжатым экраном она
/// стоит на своём месте, как и весь прежний экран.
class _TapOrigin implements _UnfoldOrigin {
  _TapOrigin(this.spot, this.fill);

  final UnfoldSpot spot;

  @override
  final Color fill;

  @override
  bool get alive => spot.alive;

  @override
  Rect? rect(RenderObject? overlay) => spot.rect(overlay);

  @override
  double get radius => spot.radius;

  @override
  ui.Image? ghost(double pixelRatio) => spot.snapshot(pixelRatio);

  @override
  bool get reghosts => true;

  @override
  List<UnfoldSharedState> shared() => const <UnfoldSharedState>[];

  @override
  void hide() {}

  @override
  void show() {}
}

/// Каким цветом залито окно, пока экран не проявился.
typedef UnfoldFill = Color Function(BuildContext context);

/// Переход темы: любой `MaterialPageRoute` растёт из кнопки, по которой
/// нажали, и складывается обратно в неё.
///
/// Места вызова об этом не знают. Кнопку находит [UnfoldTouch], а экран,
/// открытый не касанием (уведомление, ссылка, таймер), идёт прежним
/// переходом платформы — его рисует [fallback].
///
/// Окно залито цветом самого экрана, а не кнопки: маленькая тёмная кнопка
/// давала бы тёмную вспышку во весь экран (макет 11.10.2026, сцена
/// «Кнопка → экран»).
class UnfoldPageTransitionsBuilder extends PageTransitionsBuilder {
  const UnfoldPageTransitionsBuilder({required this.fallback, this.fill});

  /// Переход платформы для экранов, которым расти не из чего.
  final PageTransitionsBuilder fallback;

  /// Цвет экрана; без него берётся фон `Scaffold` из темы.
  final UnfoldFill? fill;

  /// Общий выключатель: при `false` все экраны идут через [fallback].
  static bool enabled = true;

  static final Expando<_UnfoldSession> _sessions =
      Expando<_UnfoldSession>('unfold session');

  // Длительность у строителя одна на все маршруты, поэтому берём штатную:
  // пружина окна успокаивается раньше, а запасной переход идёт как шёл.
  @override
  Duration get transitionDuration => fallback.transitionDuration;

  @override
  Duration get reverseTransitionDuration => fallback.reverseTransitionDuration;

  _UnfoldSession _begin(
      PageRoute<dynamic> route, BuildContext context, Animation<double> animation) {
    final session = _UnfoldSession(route)
      ..auto = true
      ..openMs = transitionDuration.inMilliseconds.toDouble()
      ..closeMs = reverseTransitionDuration.inMilliseconds.toDouble();
    // Растёт только экран, который открывают прямо сейчас и поверх другого:
    // у заменившего всю стопку возвращаться некуда.
    // Первый кадр нового маршрута Flutter держит за сценой и на это время
    // подменяет его ход «уже дошедшим»: по одному статусу такой маршрут не
    // отличить от давно открытого.
    final opening =
        route.offstage || animation.status == AnimationStatus.forward;
    if (!enabled || !opening || route.isFirst) return session;
    final spot = UnfoldTouch.take();
    if (spot == null) return session;
    session
      .._origin = _TapOrigin(
        spot,
        fill?.call(context) ?? Theme.of(context).scaffoldBackgroundColor,
      )
      ..measure();
    return session;
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final session = _sessions[route] ??= _begin(route, context, animation);
    if (!session.grows) {
      // Экран под растущим окном стоит на месте, поэтому уход «вбок» под
      // следующий экран здесь выключен целиком.
      return fallback.buildTransitions<T>(
          route, context, animation, kAlwaysDismissedAnimation, child);
    }
    return _UnfoldTransition(
        session: session, animation: animation, child: child);
  }
}
