import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Куда человек только что нажал.
///
/// Экран растёт из нажатого элемента, а знать этот элемент место вызова не
/// обязано: в приложении больше сотни `Navigator.push`, и оборачивать каждую
/// кнопку в `UnfoldSource` значило бы править их все. Общий слушатель
/// указателя запоминает касание, а маршрут потом спрашивает, откуда расти.
abstract final class UnfoldTouch {
  static bool _installed = false;

  static int? _pointer;
  static Offset _downAt = Offset.zero;
  static bool _moved = false;
  static DateTime? _upAt;
  static RenderPointerListener? _target;

  /// Часы; тест подменяет их, чтобы проверить срок годности нажатия.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Палец уехал дальше — это уже прокрутка, а не нажатие.
  static const double slop = 18;

  /// Сколько нажатие годится после отпускания. Экран, открытый позже (долгий
  /// запрос, таймер), с касанием уже не связан и растёт штатным переходом.
  static const Duration fresh = Duration(milliseconds: 1500);

  /// Элемент во весь экран местом не считается: расти из экрана в экран —
  /// то же, что не расти.
  static const double _wholeScreen = 0.85;

  /// Вешает слушатель. Зовётся один раз из `main()`, повтор безвреден.
  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  /// Забыть последнее касание: его уже забрал маршрут со своей плиткой.
  static void forget() {
    _target = null;
    _pointer = null;
    _upAt = null;
    _moved = false;
  }

  static void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointer = event.pointer;
      _downAt = event.position;
      _moved = false;
      _upAt = null;
      _target = _hit(event);
      return;
    }
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      if ((event.position - _downAt).distance > slop) _moved = true;
    } else if (event is PointerUpEvent) {
      _upAt = clock();
    } else if (event is PointerCancelEvent) {
      _moved = true;
    }
  }

  /// Самый глубокий элемент под пальцем, который слушает нажатия.
  static RenderPointerListener? _hit(PointerDownEvent event) {
    final result = HitTestResult();
    try {
      WidgetsBinding.instance
          .hitTestInView(result, event.position, event.viewId);
    } catch (_) {
      return null;
    }
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderPointerListener || target.onPointerDown == null) {
        continue;
      }
      // Прокрутка и перетаскивание тоже слушают касание, но нажатия у них
      // нет: такой слушатель пропускаем и ищем кнопку выше.
      final parent = target.parent;
      if (parent is RenderSemanticsGestureHandler &&
          parent.onTap == null &&
          parent.onLongPress == null) {
        continue;
      }
      return target;
    }
    return null;
  }

  static RenderPointerListener? _takeTarget() {
    final target = _target;
    final moved = _moved;
    final up = _upAt;
    forget();
    if (target == null || !target.attached || !target.hasSize || moved) {
      return null;
    }
    if (up != null && clock().difference(up) > fresh) return null;
    return target;
  }

  /// Место последнего нажатия. Отдаётся один раз: второй экран от того же
  /// касания вырос бы из той же кнопки.
  static UnfoldSpot? take() {
    final target = _takeTarget();
    if (target == null) return null;
    final shape = _shapeOf(target);
    final spot = UnfoldSpot._(shape.box, shape.radius);
    final rect = spot.rect(null);
    if (rect == null || rect.isEmpty) return null;
    final screen = _screenOf(target);
    if (screen != null &&
        rect.width * rect.height >
            screen.width * screen.height * _wholeScreen) {
      return null;
    }
    return spot;
  }

  /// Картинка миниатюры, на которую нажали: она полетит в просмотр.
  static UnfoldPhoto? takeImage() {
    final at = _downAt;
    final target = _takeTarget();
    if (target == null) return null;
    final box = _imageIn(target, at);
    final image = box?.image;
    if (box == null || image == null || _veiled(box)) return null;
    try {
      return UnfoldPhoto._(box, image.clone(), _clipRadius(box));
    } catch (_) {
      // Картинку успели отпустить: полетит не снимок, а простое проявление.
      return null;
    }
  }

  static Size? _screenOf(RenderObject from) {
    RenderObject root = from;
    while (root.parent != null) {
      root = root.parent!;
    }
    return root is RenderView ? root.size : null;
  }

  // ── форма элемента ────────────────────────────────────────────────────────

  static double _area(RenderBox box) => box.size.width * box.size.height;

  /// Видимая форма кнопки. Слушатель нажатий формы не знает: у `IconButton`
  /// он 48×48 при круге в 40, у залитой кнопки форму держит `Material` над
  /// ним. Ищем ближайшую форму сперва вокруг, потом внутри.
  static ({RenderBox box, double radius}) _shapeOf(RenderBox target) {
    final own = _area(target);
    RenderObject? above = target.parent;
    for (var depth = 0; depth < 12 && above != null; depth++) {
      if (above is RenderBox && above.hasSize) {
        if (_area(above) > own * 1.6) break;
        final radius = _radiusOf(above);
        if (radius != null) return (box: above, radius: radius);
      }
      above = above.parent;
    }

    final queue = Queue<RenderObject>()..add(target);
    var seen = 0;
    while (queue.isNotEmpty && seen < 80) {
      final node = queue.removeFirst();
      seen++;
      if (node is RenderBox && node.hasSize && !identical(node, target)) {
        if (_area(node) < own * 0.45) continue;
        final radius = _radiusOf(node);
        if (radius != null) return (box: node, radius: radius);
      }
      node.visitChildren(queue.add);
    }
    return (box: target, radius: math.min(target.size.shortestSide / 2, 24));
  }

  static double? _radiusOf(RenderBox box) {
    final half = box.size.shortestSide / 2;
    double? raw;
    if (box is RenderClipRRect) {
      raw = box.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    } else if (box is RenderClipOval) {
      raw = half;
    } else if (box is RenderPhysicalModel) {
      raw = box.shape == BoxShape.circle
          ? half
          : (box.borderRadius?.topLeft.x ?? 0);
      // Холст страницы — тоже PhysicalModel без формы: это не кнопка.
      if (box.shape != BoxShape.circle && box.borderRadius == null) return null;
    } else if (box is RenderPhysicalShape) {
      final clipper = box.clipper;
      if (clipper is ShapeBorderClipper) raw = _radiusOfShape(clipper.shape, half);
    } else if (box is RenderClipPath) {
      final clipper = box.clipper;
      if (clipper is ShapeBorderClipper) raw = _radiusOfShape(clipper.shape, half);
    } else if (box is RenderDecoratedBox) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration) {
        final visible = decoration.color != null ||
            decoration.gradient != null ||
            decoration.image != null ||
            decoration.border != null;
        if (!visible) return null;
        raw = decoration.shape == BoxShape.circle
            ? half
            : (decoration.borderRadius?.resolve(TextDirection.ltr).topLeft.x ??
                0);
      } else if (decoration is ShapeDecoration) {
        raw = _radiusOfShape(decoration.shape, half);
      }
    }
    if (raw == null) return null;
    return raw.clamp(0.0, half).toDouble();
  }

  static double _radiusOfShape(ShapeBorder shape, double half) {
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    }
    if (shape is RoundedSuperellipseBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    }
    if (shape is ContinuousRectangleBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x / 2;
    }
    if (shape is BeveledRectangleBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    }
    // Стадион, круг, овал и фигурные формы M3 Expressive.
    return half;
  }

  // ── картинка под пальцем ──────────────────────────────────────────────────

  static RenderImage? _imageIn(RenderObject root, Offset at) {
    RenderImage? best;
    var bestScore = 0.0;
    final queue = Queue<RenderObject>()..add(root);
    var seen = 0;
    while (queue.isNotEmpty && seen < 240) {
      final node = queue.removeFirst();
      seen++;
      if (node is RenderImage && node.hasSize && node.image != null) {
        final rect = MatrixUtils.transformRect(
            node.getTransformTo(null), Offset.zero & node.size);
        // Картинка под самым пальцем важнее самой большой: в карточке рядом
        // с обложкой стоит аватар.
        final score =
            rect.width * rect.height * (rect.contains(at) ? 1000 : 1);
        if (score > bestScore) {
          bestScore = score;
          best = node;
        }
      }
      node.visitChildren(queue.add);
    }
    return best;
  }

  static bool _veiled(RenderObject from) {
    RenderObject? node = from.parent;
    for (var depth = 0; depth < 16 && node != null; depth++) {
      if (node is RenderMetaData && identical(node.metaData, _veilMark)) {
        return true;
      }
      node = node.parent;
    }
    return false;
  }

  static double _clipRadius(RenderImage image) {
    final own = _area(image);
    final half = image.size.shortestSide / 2;
    RenderObject? above = image.parent;
    for (var depth = 0; depth < 10 && above != null; depth++) {
      if (above is RenderBox && above.hasSize) {
        if (_area(above) > own * 1.3) break;
        final clips = above is RenderClipRRect ||
            above is RenderClipOval ||
            above is RenderClipPath ||
            above is RenderPhysicalShape ||
            above is RenderPhysicalModel;
        if (clips) {
          final radius = _radiusOf(above);
          if (radius != null) return math.min(radius, half);
        }
      }
      above = above.parent;
    }
    return 0;
  }
}

const Object _veilMark = Object();

/// Метка «под завесой»: картинку внутри в полёт брать нельзя.
///
/// Миниатюра 18+ размыта поверх, а сама картинка под размытием чистая. Без
/// метки в просмотр полетел бы открытый кадр.
class UnfoldVeiled extends StatelessWidget {
  const UnfoldVeiled({super.key, this.veiled = true, required this.child});

  /// Завеса сейчас опущена. Обёртка при этом стоит всегда: появись она
  /// только под завесой, картинка внутри пересоздавалась бы при раскрытии.
  final bool veiled;

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MetaData(metaData: veiled ? _veilMark : null, child: child);
}

Rect? _placeOf(RenderBox box, RenderObject? ancestor) {
  if (!box.attached || !box.hasSize) return null;
  if (ancestor != null && !ancestor.attached) return null;
  try {
    return MatrixUtils.transformRect(
        box.getTransformTo(ancestor), Offset.zero & box.size);
  } catch (_) {
    // Нажатый элемент живёт вне навигатора (плашка поверх приложения):
    // места в его координатах нет, экран откроется без роста.
    return null;
  }
}

/// Нажатый элемент: место, скругление и снимок.
class UnfoldSpot {
  UnfoldSpot._(this._box, this.radius);

  final RenderBox _box;

  final double radius;

  /// Элемент ещё на экране.
  bool get alive => _box.attached && _box.hasSize;

  /// Место элемента в координатах [ancestor]; без него — на экране.
  Rect? rect(RenderObject? ancestor) => _placeOf(_box, ancestor);

  /// Снимок элемента вместе с тем, что вокруг него в том же прямоугольнике.
  ///
  /// Снимается кусок слоя, а не весь слой: ближайшая граница перерисовки
  /// бывает длиной в весь прокручиваемый экран.
  ui.Image? snapshot(double pixelRatio) {
    if (!alive) return null;
    RenderObject? node = _box;
    while (node != null && node is! RenderRepaintBoundary) {
      node = node.parent;
    }
    if (node is! RenderRepaintBoundary || !node.attached) return null;
    final crop = MatrixUtils.transformRect(
        _box.getTransformTo(node), Offset.zero & _box.size);
    return unfoldSnapshot(node, crop, pixelRatio);
  }
}

/// Снимок куска [crop] слоя [boundary] (в его координатах).
///
/// Штатный `RenderRepaintBoundary.toImageSync` снимает слой целиком и в
/// отладке отказывает, пока тот ждёт перерисовки (кнопка подсвечена). Здесь
/// берётся последний нарисованный слой и только нужный кусок.
ui.Image? unfoldSnapshot(
    RenderRepaintBoundary boundary, Rect crop, double pixelRatio) {
  if (!boundary.attached || crop.isEmpty) return null;
  try {
    // Слой открыт только наследникам отрисовки.
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer) return null;
    return layer.toImageSync(crop, pixelRatio: pixelRatio);
  } catch (_) {
    return null;
  }
}

/// Картинка нажатой миниатюры и её место.
class UnfoldPhoto {
  UnfoldPhoto._(this._box, this.image, this.radius);

  final RenderImage _box;

  /// Своя ссылка на картинку: её надо отпустить через [dispose].
  final ui.Image image;

  final double radius;

  bool get alive => _box.attached && _box.hasSize;

  Rect? rect(RenderObject? ancestor) => _placeOf(_box, ancestor);

  void dispose() => image.dispose();
}
