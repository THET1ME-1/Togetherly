import 'dart:math' as math;
import 'dart:ui';

/// Правила щипка по холсту рисовалки.
///
/// Всё считается ОТ ПРОШЛОГО КАДРА. Абсолютная база (масштаб и фокус на начало
/// жеста) не годится: Flutter переназначает свою точку отсчёта при каждом
/// изменении состава пальцев, и две системы координат расходятся — лист
/// дёргается и улетает. Так это ломалось дважды: в 1.23.0 «экран метается
/// туда-сюда, мешая рисовать» и 21.08.2026 «двумя пальцами вообще капец».
Offset _rotate(Offset v, double angle) {
  if (angle == 0) return v;
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

/// Как холст лежит на экране: масштаб, поворот и смещение.
class CanvasView {
  const CanvasView({
    required this.scale,
    required this.rotation,
    required this.offset,
  });

  final double scale;
  final double rotation;
  final Offset offset;
}

/// Изменение щипка ОТНОСИТЕЛЬНО прошлого кадра.
///
/// Именно относительно, а не от начала жеста: Flutter при каждом изменении
/// состава пальцев назначает новую точку отсчёта — `scale` возвращается к
/// единице, `rotation` к нулю, средний фокус скачком уезжает к оставшимся
/// пальцам. Обработчик, считавший от своей базы, в этот момент рвал холст в
/// сторону; шаг от прошлого кадра с такой перестройкой согласован.
class PinchStep {
  const PinchStep({
    required this.focal,
    required this.focalDelta,
    required this.scaleStep,
    required this.rotationStep,
  });

  /// Где пальцы сейчас.
  final Offset focal;

  /// Куда фокус переехал с прошлого кадра.
  final Offset focalDelta;

  /// Во сколько раз изменился масштаб.
  final double scaleStep;

  /// На сколько радиан довернулись пальцы.
  final double rotationStep;
}

/// Новый вид холста после шага щипка.
///
/// Точка листа под пальцами остаётся под пальцами, а перемещение самих пальцев
/// тянет лист за собой.
CanvasView applyPinch(
  CanvasView view,
  PinchStep step, {
  double minScale = 0.2,
  double maxScale = 8,
}) {
  final nextScale = (view.scale * step.scaleStep).clamp(minScale, maxScale);
  final nextRotation = view.rotation + step.rotationStep;
  // Опора — фокус ПРОШЛОГО кадра: сегодняшний уже уехал на focalDelta, и
  // считать от него значило бы применить перемещение дважды.
  final prevFocal = step.focal - step.focalDelta;
  final underFinger =
      _rotate((prevFocal - view.offset) / view.scale, -view.rotation);
  return CanvasView(
    scale: nextScale,
    rotation: nextRotation,
    offset: step.focal - _rotate(underFinger * nextScale, nextRotation),
  );
}

/// Порог поворота: пока пальцы не развернулись примерно на девять градусов,
/// лист не кренится. Иначе он заваливался от любого щипка.
const double kPinchRotationSlop = 0.16;

/// Ведёт щипок от кадра к кадру и гасит кадры перестройки жеста.
class PinchTracker {
  int? _pointers;
  double _scale = 1;
  double _rotation = 0;
  bool _rotationUnlocked = false;
  double _rotationSlopUsed = 0;
  double _turnedApplied = 0;

  /// Новый жест: опоры сбрасываются.
  void begin() {
    _pointers = null;
    _scale = 1;
    _rotation = 0;
    _rotationUnlocked = false;
    _rotationSlopUsed = 0;
    _turnedApplied = 0;
  }

  /// Шаг жеста или `null`, если этот кадр двигать холст нельзя.
  ///
  /// Двигать нельзя в двух случаях: пальцев меньше двух и состав пальцев
  /// только что изменился. Во втором случае Flutter уже переназначил отсчёт, а
  /// средний фокус скакнул — применив такой кадр, холст улетает в сторону.
  PinchStep? step({
    required int pointerCount,
    required double scale,
    required double rotation,
    required Offset focal,
    required Offset focalDelta,
  }) {
    if (pointerCount < 2) {
      _pointers = pointerCount;
      _scale = scale;
      _rotation = rotation;
      return null;
    }
    if (_pointers != pointerCount) {
      _pointers = pointerCount;
      _scale = scale;
      _rotation = rotation;
      _rotationUnlocked = false;
      _rotationSlopUsed = 0;
      _turnedApplied = 0;
      return null;
    }

    final scaleStep = _scale == 0 ? 1.0 : scale / _scale;
    if (!_rotationUnlocked && rotation.abs() > kPinchRotationSlop) {
      _rotationUnlocked = true;
      // Порог вычитается один раз: иначе в момент срабатывания лист
      // довернулся бы на все девять градусов рывком.
      _rotationSlopUsed = rotation.sign * kPinchRotationSlop;
    }
    final turned = _rotationUnlocked ? rotation - _rotationSlopUsed : 0.0;
    final rotationStep = turned - _turnedApplied;
    _turnedApplied = turned;

    _scale = scale;
    _rotation = rotation;
    return PinchStep(
      focal: focal,
      focalDelta: focalDelta,
      scaleStep: scaleStep,
      rotationStep: rotationStep,
    );
  }
}
