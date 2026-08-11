import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';

/// Одноразовая подсказка-пузырь у кнопки.
///
/// Приём взят у подсказки про боковую кнопку навбара, которая живёт в
/// приложении с июля: пузырь акцентом, стрелка на цель, «Понятно» закрывает,
/// тап мимо — тоже. Здесь он вынесен отдельно, потому что таких подсказок
/// стало несколько, а copy-paste оверлея на каждую новую функцию — верный
/// способ развести три разных пузыря по виду.
///
/// Куда смотрит стрелка, решает [HintSide]: подсказка про кнопку внизу экрана
/// встаёт над ней и указывает вниз, подсказка про счётчик в шапке — под ним и
/// указывает вверх.
enum HintSide { above, below }

/// Показывает пузырь у цели [targetKey] и возвращает управление, когда его
/// закрыли — сами, тапом мимо или по истечении [life].
///
/// Возврат именно по закрытию нужен очереди: следующая подсказка не должна
/// появляться, пока видна предыдущая.
Future<void> showHintBubble(
  BuildContext context, {
  required GlobalKey targetKey,
  required String text,
  required String gotIt,
  required IconData icon,
  required AppTheme theme,
  HintSide side = HintSide.above,
  Duration life = const Duration(seconds: 9),
}) async {
  final targetContext = targetKey.currentContext;
  if (targetContext == null) return;
  final box = targetContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  final pos = box.localToGlobal(Offset.zero);
  final screen = MediaQuery.sizeOf(context);
  const bubbleWidth = 250.0;

  // Пузырь держится за центр цели, но не вылезает за края экрана.
  final targetCenterX = pos.dx + box.size.width / 2;
  final left = (targetCenterX - bubbleWidth / 2).clamp(
    12.0,
    screen.width - bubbleWidth - 12,
  );
  // Стрелка остаётся под центром цели, куда бы ни съехал сам пузырь.
  final arrowLeft = (targetCenterX - left - 14).clamp(14.0, bubbleWidth - 42);

  final done = Completer<void>();
  OverlayEntry? entry;
  Timer? timer;

  void close() {
    if (done.isCompleted) return;
    timer?.cancel();
    // Оверлей мог уехать вместе с экраном раньше, чем истёк срок жизни
    // пузыря: снимать уже снятую запись нельзя.
    if (entry?.mounted ?? false) entry!.remove();
    entry = null;
    done.complete();
  }

  final onAccent = AppThemes.onColor(theme.fillColor, mode: theme.brightness);

  Widget arrow() => Padding(
    padding: EdgeInsets.only(left: arrowLeft),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Transform.translate(
        offset: Offset(0, side == HintSide.above ? -6 : 6),
        child: Icon(
          side == HintSide.above
              ? Icons.arrow_drop_down
              : Icons.arrow_drop_up,
          color: theme.fillColor,
          size: 38,
        ),
      ),
    ),
  );

  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: close,
        child: Stack(
          children: [
            Positioned(
              left: left,
              width: bubbleWidth,
              top: side == HintSide.below ? pos.dy + box.size.height - 6 : null,
              bottom: side == HintSide.above
                  ? screen.height - pos.dy + 6
                  : null,
              child: _Bubble(
                text: text,
                gotIt: gotIt,
                icon: icon,
                fill: theme.fillColor,
                ink: onAccent,
                onClose: close,
                arrow: arrow(),
                side: side,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  overlay.insert(entry!);
  timer = Timer(life, close);
  await done.future;
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.text,
    required this.gotIt,
    required this.icon,
    required this.fill,
    required this.ink,
    required this.onClose,
    required this.arrow,
    required this.side,
  });

  final String text;
  final String gotIt;
  final IconData icon;
  final Color fill;
  final Color ink;
  final VoidCallback onClose;
  final Widget arrow;
  final HintSide side;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Motion.block,
    value: 0,
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
        decoration: BoxDecoration(
          color: widget.fill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, color: widget.ink, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      color: widget.ink,
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onClose,
                style: TextButton.styleFrom(
                  foregroundColor: widget.ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  widget.gotIt,
                  style: const TextStyle(
                    fontFamily: 'Onest',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return FadeTransition(
      opacity: _ctrl,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            0,
            (1 - _ctrl.value) * (widget.side == HintSide.above ? 10 : -10),
          ),
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.side == HintSide.above
              ? [card, widget.arrow]
              : [widget.arrow, card],
        ),
      ),
    );
  }
}
