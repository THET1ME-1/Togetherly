import 'dart:math' as math;
import 'dart:ui';

/// Правила щипка по холсту рисовалки.
///
/// До 1.23.0 обработчик проверял число пальцев только на входе в жест: стоило
/// поднять один палец, как Flutter продолжал слать события уже с одним, фокус
/// скачком уезжал к нему, и лист прыгал следом. В отзыве это выглядело как
/// «экран метается туда-сюда, мешая рисовать».
enum PinchAction {
  /// Двигаем холст.
  transform,

  /// Пальцев меньше двух — стоим на месте.
  pause,

  /// Второй палец вернулся: сначала берём новую опору, только потом двигаем.
  rebase,
}

PinchAction pinchAction({required int pointerCount, required bool paused}) {
  if (pointerCount < 2) return PinchAction.pause;
  return paused ? PinchAction.rebase : PinchAction.transform;
}

Offset _rotate(Offset v, double angle) {
  if (angle == 0) return v;
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

/// Смещение холста так, чтобы точка под пальцами осталась под пальцами.
Offset pinchOffset({
  required Offset focal,
  required Offset baseFocal,
  required Offset baseOffset,
  required double baseScale,
  required double nextScale,
  required double baseRotation,
  required double nextRotation,
}) {
  final focalCanvas = _rotate((baseFocal - baseOffset) / baseScale, -baseRotation);
  return focal - _rotate(focalCanvas * nextScale, nextRotation);
}
