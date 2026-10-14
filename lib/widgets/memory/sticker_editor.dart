import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart';
import '../../models/memory_sticker.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import 'sticker_layer.dart';

/// Что вернул редактор наклейки.
class StickerEditResult {
  const StickerEditResult.placed(MemorySticker this.sticker) : removed = false;
  const StickerEditResult.removed()
      : sticker = null,
        removed = true;

  /// Наклейка на новом месте.
  final MemorySticker? sticker;

  /// Крестиком убрали уже наклеенную.
  final bool removed;
}

/// Поставить наклейку на место прямо на карточке ленты.
///
/// Лента затемняется, карточка [card] остаётся светлой, наклейка встаёт на
/// блок [block] (оба прямоугольника — на экране). Одним пальцем наклейку
/// двигают, двумя крутят и тянут, кружок в углу рамки делает то же одним
/// пальцем. Крестик у новой наклейки отменяет её, у наклеенной — убирает.
/// null — отмена.
///
/// [others] — остальные наклейки блока: их края свисают за карточку, и
/// затемнение легло бы на них полосой, поэтому редактор рисует их поверх.
Future<StickerEditResult?> placeStickerOnCard(
  BuildContext context, {
  required Rect block,
  required Rect card,
  required MemorySticker sticker,
  required bool isNew,
  List<MemorySticker> others = const [],
}) {
  return Navigator.of(context).push(PageRouteBuilder<StickerEditResult>(
    opaque: false,
    settings: const RouteSettings(name: '/sticker_place'),
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, _, _) => StickerEditor(
      block: block,
      card: card,
      sticker: sticker,
      isNew: isNew,
      others: others,
    ),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  ));
}

/// Экран наклеивания поверх ленты (см. [placeStickerOnCard]).
class StickerEditor extends StatefulWidget {
  const StickerEditor({
    super.key,
    required this.block,
    required this.card,
    required this.sticker,
    this.isNew = true,
    this.others = const [],
  });

  final Rect block;
  final Rect card;
  final MemorySticker sticker;
  final bool isNew;
  final List<MemorySticker> others;

  /// Скругление карточки ленты: вырез в затемнении повторяет её.
  static const double cardRadius = 28;

  @override
  State<StickerEditor> createState() => _StickerEditorState();
}

class _StickerEditorState extends State<StickerEditor> {
  late MemorySticker _s = clampSticker(widget.sticker);

  // Щипок считается шагами от прошлого кадра: Flutter сбрасывает свою точку
  // отсчёта при каждой смене числа пальцев, и счёт от начала жеста швырял бы
  // наклейку (та же грабля, что у холста, см. canvas_pinch.dart).
  int _pointers = 0;
  double _lastScale = 1;
  double _lastRotation = 0;
  Offset? _lastFocal;

  // Ручка в углу рамки: поворот и размер вокруг центра наклейки.
  double _grabAngle = 0;
  double _grabDistance = 1;
  double _grabSize = kStickerDefaultSize;
  double _grabTurn = 0;

  Rect get _block => widget.block;

  Offset get _center =>
      Offset(_block.left + _s.x * _block.width, _block.top + _s.y * _block.height);

  double get _side => _s.size * _block.width;

  void _set(MemorySticker next) => setState(() => _s = clampSticker(next));

  void _onScaleStart(ScaleStartDetails d) {
    _pointers = d.pointerCount;
    _lastScale = 1;
    _lastRotation = 0;
    _lastFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _pointers) {
      // Палец добавился или ушёл: кадр пропускаем, обновляем только опоры.
      _pointers = d.pointerCount;
      _lastScale = d.scale;
      _lastRotation = d.rotation;
      _lastFocal = d.focalPoint;
      return;
    }
    final delta = d.focalPoint - (_lastFocal ?? d.focalPoint);
    final ratio = _lastScale == 0 ? 1.0 : d.scale / _lastScale;
    final turn = d.rotation - _lastRotation;
    _lastFocal = d.focalPoint;
    _lastScale = d.scale;
    _lastRotation = d.rotation;
    final two = d.pointerCount > 1;
    _set(_s.copyWith(
      x: _s.x + delta.dx / _block.width,
      y: _s.y + delta.dy / _block.height,
      size: two ? _s.size * ratio : null,
      angle: two ? _s.angle + turn : null,
    ));
  }

  void _onGrabStart(DragStartDetails d) {
    final v = d.globalPosition - _center;
    _grabAngle = v.direction;
    _grabDistance = v.distance < 1 ? 1 : v.distance;
    _grabSize = _s.size;
    _grabTurn = _s.angle;
    HapticFeedback.selectionClick();
  }

  void _onGrabUpdate(DragUpdateDetails d) {
    final v = d.globalPosition - _center;
    _set(_s.copyWith(
      size: _grabSize * v.distance / _grabDistance,
      angle: _grabTurn + v.direction - _grabAngle,
    ));
  }

  void _done() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(StickerEditResult.placed(_s));
  }

  void _cross() => Navigator.of(context).pop(
      widget.isNew ? null : const StickerEditResult.removed());

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    final onFill = AppThemes.onColor(t.fillColor, mode: t.brightness);
    final bottom = MediaQuery.paddingOf(context).bottom;

    // Рамка с ручками вокруг наклейки: крестик снаружи левого верхнего угла,
    // кружок поворота — правого нижнего. Поле касания у ручек 44 точки,
    // видимый кружок 30, как в макете.
    const hit = 44.0;
    const knob = 30.0;
    const frameGap = 7.0;
    const pad = hit / 2 + 5; // центр ручки на 5 точек за углом наклейки
    final side = _side;
    final box = side + pad * 2;

    Widget handle({
      required IconData icon,
      required Color fill,
      required Color ink,
      required String label,
      VoidCallback? onTap,
      GestureDragStartCallback? onStart,
      GestureDragUpdateCallback? onUpdate,
    }) =>
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Отсчёт от касания, а не от конца порога сдвига: иначе ручка
            // отставала бы от пальца.
            dragStartBehavior: DragStartBehavior.down,
            onTap: onTap,
            onPanStart: onStart,
            onPanUpdate: onUpdate,
            child: SizedBox(
              width: hit,
              height: hit,
              child: Center(
                child: Container(
                  width: knob,
                  height: knob,
                  decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: ink),
                ),
              ),
            ),
          ),
        );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Затемнение с вырезом под карточку; любой жест по экрану двигает
          // наклейку — попасть пальцем в маленькую картинку не нужно.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Наклейка идёт за пальцем с самого касания, без отставания
              // на порог сдвига.
              dragStartBehavior: DragStartBehavior.down,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: CustomPaint(
                painter: _ScrimPainter(
                  hole: RRect.fromRectAndRadius(
                    widget.card,
                    const Radius.circular(StickerEditor.cardRadius),
                  ),
                  color: Colors.black.withValues(alpha: 0.62),
                ),
              ),
            ),
          ),
          for (final o in widget.others)
            Positioned.fromRect(
              rect: stickerRect(o, _block.size).shift(_block.topLeft),
              child: IgnorePointer(
                child: StickerPicture(
                  image: o.image,
                  side: o.size * _block.width,
                  angle: o.angle,
                ),
              ),
            ),
          Positioned(
            left: _center.dx - box / 2,
            top: _center.dy - box / 2,
            width: box,
            height: box,
            child: Transform.rotate(
              angle: _s.angle,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: pad - frameGap,
                    top: pad - frameGap,
                    width: side + frameGap * 2,
                    height: side + frameGap * 2,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.primary, width: 2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: pad,
                    top: pad,
                    width: side,
                    height: side,
                    child: IgnorePointer(
                      child: StickerPicture(image: _s.image, side: side),
                    ),
                  ),
                  Positioned(
                    left: pad - hit / 2 - 5,
                    top: pad - hit / 2 - 5,
                    child: handle(
                      icon: Icons.close_rounded,
                      fill: cs.surfaceContainerHigh,
                      ink: cs.onSurface,
                      label: widget.isNew
                          ? LocaleService.current.cancel
                          : trKey('stickerRemove'),
                      onTap: _cross,
                    ),
                  ),
                  Positioned(
                    left: pad + side + 5 - hit / 2,
                    top: pad + side + 5 - hit / 2,
                    child: handle(
                      icon: Icons.rotate_right_rounded,
                      fill: t.fillColor,
                      ink: onFill,
                      label: trKey('stickerHint'),
                      onStart: _onGrabStart,
                      onUpdate: _onGrabUpdate,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 22 + bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IgnorePointer(
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cs.inverseSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    // Пилюля по тексту, а не во всю ширину.
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                      trKey('stickerHint'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onInverseSurface,
                      ),
                    ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 100,
                      child: _pill(
                        key: const Key('sticker-cancel'),
                        label: LocaleService.current.cancel,
                        fill: cs.surfaceContainerHigh,
                        ink: cs.onSurface,
                        radius: const BorderRadius.horizontal(
                          left: Radius.circular(28),
                          right: Radius.circular(8),
                        ),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: 135,
                      child: _pill(
                        key: const Key('sticker-done'),
                        label: LocaleService.current.done,
                        icon: Icons.check_rounded,
                        fill: t.fillColor,
                        ink: onFill,
                        radius: const BorderRadius.horizontal(
                          left: Radius.circular(8),
                          right: Radius.circular(28),
                        ),
                        onTap: _done,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required Key key,
    required String label,
    IconData? icon,
    required Color fill,
    required Color ink,
    required BorderRadius radius,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: fill,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: ink),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
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
}

/// Затемнение ленты с вырезом под карточку, которую сейчас украшают.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.hole, required this.color});

  final RRect hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color;
}
