import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart' show Cubic;

/// Числа перехода «экран вырастает из нажатого».
///
/// Сняты с макета https://claude.ai/artifact/Ssgdjfc37xm7TigCWy6NGC, вариант
/// «А · Как в ролике», который владелец выбрал 11.10.2026. Всё считается от
/// прошедшего времени в миллисекундах, а не от доли пути: у пружины нет
/// «половины», у неё есть перелёт, и на отрезке 0…1 он пропадает.
abstract final class UnfoldTiming {
  /// Сколько держим открытие: пружина успокаивается к 420-й мс, остальное —
  /// запас на последний блок содержимого.
  static const double openMs = 620;

  /// Закрытие: пружина без перелёта, быстрее открытия.
  static const double closeMs = 430;

  /// Возврат на место, когда жест «назад» отпустили до порога.
  static const double settleMs = 260;

  /// Проявление и уход без движения: при «уменьшить движение» и там, где
  /// расти не из чего.
  static const double fadeInMs = 180;
  static const double fadeOutMs = 140;

  /// Ход пальца, за который экран сжимается до предела.
  static const double dragTravel = 210;

  /// До какой доли сжимается экран под пальцем.
  static const double dragMinScale = 0.56;
}

double _unit(double value) => value.clamp(0.0, 1.0).toDouble();

double _mix(double from, double to, double t) => from + (to - from) * t;

/// Пружина: какая доля пути пройдена через [ms] миллисекунд.
///
/// [omega] — собственная частота (корень из жёсткости при массе 1), [zeta] —
/// затухание. Ниже единицы пружина проскакивает цель и возвращается, от
/// единицы и выше подходит к ней без перелёта.
double unfoldSpring(double ms, {required double omega, required double zeta}) {
  if (ms <= 0) return 0;
  final t = ms / 1000;
  if (zeta >= 1) return 1 - math.exp(-omega * t) * (1 + omega * t);
  final damped = omega * math.sqrt(1 - zeta * zeta);
  return 1 -
      math.exp(-zeta * omega * t) *
          (math.cos(damped * t) + (zeta * omega / damped) * math.sin(damped * t));
}

/// Один кадр перехода: где окно, как оно скруглено и что в нём видно.
class UnfoldFrame {
  const UnfoldFrame({
    required this.rect,
    required this.radius,
    required this.tint,
    required this.ghost,
    required this.flight,
  });

  /// Окно, в котором виден новый экран.
  final Rect rect;
  final double radius;

  /// Заливка нажатого элемента поверх экрана: 1 — экран под ней не виден.
  final double tint;

  /// Снимок содержимого нажатого элемента: 1 — виден целиком.
  final double ghost;

  /// Путь общих элементов: 0 — на старом месте, 1 — на новом. У пружины
  /// заходит за единицу.
  final double flight;
}

/// Кадр открытия: окно растёт из [source] до [full].
UnfoldFrame unfoldOpenFrame({
  required double ms,
  required Rect source,
  required Rect full,
  required double sourceRadius,
}) {
  final travel = unfoldSpring(ms, omega: 18, zeta: 0.82);
  return UnfoldFrame(
    rect: Rect.lerp(source, full, travel)!,
    radius: _mix(sourceRadius, 0, _unit(travel)),
    tint: 1 - _unit(ms / 240),
    ghost: 1 - _unit(ms / 110),
    flight: travel,
  );
}

/// Кадр закрытия: окно складывается из [from] обратно в [source].
///
/// [from] — полный экран либо то место, где карточку отпустил палец.
UnfoldFrame unfoldCloseFrame({
  required double ms,
  required Rect source,
  required Rect from,
  required double sourceRadius,
  required double fromRadius,
}) {
  final left = 1 - unfoldSpring(ms, omega: 21, zeta: 1);
  return UnfoldFrame(
    rect: Rect.lerp(source, from, left)!,
    radius: _mix(sourceRadius, fromRadius, left),
    tint: _unit((ms - 40) / 170),
    ghost: _unit((ms - 150) / 120),
    flight: left,
  );
}

/// Появление блока номер [index] на новом экране: блоки идут сверху вниз с
/// шагом 30 мс и приезжают снизу на 18 точек.
({double opacity, double shift}) unfoldItemIn(double ms, int index) {
  final own = ms - 80 - index * 30;
  return (
    opacity: _unit(own / 170),
    shift: (1 - unfoldSpring(own, omega: 15, zeta: 0.8)) * 18,
  );
}

/// Содержимое экрана при закрытии гаснет разом и быстро: складывается уже
/// пустая плитка.
double unfoldItemOutOpacity(double ms) => 1 - _unit(ms / 90);

const Cubic _easeOut = Cubic(0, 0, 0.2, 1);

/// Экран под пальцем: сжимается в карточку и едет за рукой.
///
/// [delta] — сдвиг пальца от места касания. [fromRight] — жест начат от
/// правого края (на Android системный «назад» работает с обеих сторон).
({Rect rect, double radius, double progress}) unfoldDragFrame({
  required Offset delta,
  required Size screen,
  bool fromRight = false,
}) {
  final pull = math.max(0.0, fromRight ? -delta.dx : delta.dx);
  final progress = _unit(pull / UnfoldTiming.dragTravel);
  if (progress == 0) {
    return (rect: Offset.zero & screen, radius: 0, progress: 0);
  }
  final scale =
      1 - (1 - UnfoldTiming.dragMinScale) * _easeOut.transform(progress);
  final width = screen.width * scale;
  final height = screen.height * scale;
  final left = fromRight ? screen.width - pull * 0.62 - width : pull * 0.62;
  final free = screen.height - height;
  final top = (free * 0.42 + delta.dy * 0.45).clamp(0.0, free).toDouble();
  return (
    rect: Rect.fromLTWH(left, top, width, height),
    radius: 46 * math.sqrt(progress),
    progress: progress,
  );
}

/// Отпустили дальше трети хода — экран закрывается, ближе — возвращается.
bool unfoldDragCommits(double progress) => progress > 0.33;
