import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/profile_theme.dart';
import 'guide_hint_layout.dart';
import 'guide_mascot.dart';

/// Подсказка облачком-гидом вместо пузыря со стрелкой (`showHintBubble`).
///
/// Облачко прилетает к кнопке и смотрит на неё, рядом пузырь с текстом и
/// «Понятно», вокруг кнопки пульсирует кольцо цвета темы. Тап мимо и истёкший
/// срок закрывают так же, как прежний пузырь, — очередь подсказок ждёт
/// закрытия, прежде чем показать следующую.
Future<void> showGuideHint(
  BuildContext context, {
  required GlobalKey targetKey,
  required String text,
  required String gotIt,
  required AppTheme theme,
  Duration life = const Duration(seconds: 12),
}) async {
  final targetContext = targetKey.currentContext;
  if (targetContext == null) return;
  final box = targetContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  final target = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.sizeOf(context);
  final layout = guideHintLayout(target: target, screen: screen);
  final cs = ProfileTheme.schemeFor(theme);

  final done = Completer<void>();
  OverlayEntry? entry;
  Timer? timer;
  void close() {
    if (done.isCompleted) return;
    timer?.cancel();
    if (entry?.mounted ?? false) entry!.remove();
    entry = null;
    done.complete();
  }

  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: close,
        child: _GuideHintView(layout: layout, target: target, targetKey: targetKey, text: text, gotIt: gotIt, scheme: cs, onClose: close),
      ),
    ),
  );
  overlay.insert(entry!);
  timer = Timer(life, close);
  await done.future;
}

class _GuideHintView extends StatefulWidget {
  const _GuideHintView({required this.layout, required this.target, required this.targetKey, required this.text, required this.gotIt, required this.scheme, required this.onClose});

  final GuideHintLayout layout;
  final Rect target;
  final GlobalKey targetKey;
  final String text;
  final String gotIt;
  final ColorScheme scheme;
  final VoidCallback onClose;

  @override
  State<_GuideHintView> createState() => _GuideHintViewState();
}

class _GuideHintViewState extends State<_GuideHintView> with TickerProviderStateMixin {
  // Появление: облачко подлетает и встаёт на место, пузырь раскрывается
  // следом. Только размером и сдвигом, без растворения у облачка.
  late final AnimationController _in = AnimationController(vsync: this, duration: Motion.block * 2)..forward();
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _in.dispose();
    _ring.dispose();
    super.dispose();
  }

  /// Где кнопка сейчас. Главная прокручивается под подсказкой, и облачко с
  /// кольцом обязаны ехать вместе с кнопкой, а не висеть на месте.
  Offset _shift() {
    final box = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) {
      // Кнопка ушла с экрана вместе со страницей — подсказке не на что смотреть.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return Offset.zero;
    }
    return box.localToGlobal(Offset.zero) - widget.target.topLeft;
  }

  @override
  Widget build(BuildContext context) {
    // Пересчёт каждый кадр: кольцо пульсирует без конца, им и тикаем.
    return AnimatedBuilder(
      animation: _ring,
      builder: (context, child) => Transform.translate(offset: _shift(), child: child),
      child: _content(),
    );
  }

  Widget _content() {
    final l = widget.layout, cs = widget.scheme;
    final fly = CurvedAnimation(parent: _in, curve: const Interval(0, 0.7, curve: Curves.easeOutBack));
    final pop = CurvedAnimation(parent: _in, curve: const Interval(0.45, 1, curve: Curves.easeOutCubic));
    final ring = widget.target.inflate(5);
    return Stack(
      children: [
        Positioned.fromRect(
          rect: ring,
          child: IgnorePointer(
            child: ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _ring, curve: Curves.easeInOut)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ring.shortestSide / 2),
                  border: Border.all(color: cs.primary, width: 3),
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: l.cloud,
          child: AnimatedBuilder(
            animation: fly,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, (1 - fly.value) * (l.cloud.center.dy < widget.target.center.dy ? -40 : 40)),
              child: Transform.scale(scale: 0.6 + 0.4 * fly.value, child: child),
            ),
            child: IgnorePointer(child: GuideMascot(l.art, side: l.cloud.width)),
          ),
        ),
        Positioned(
          left: l.bubbleLeft,
          top: l.bubbleTop,
          width: l.bubbleWidth,
          child: ScaleTransition(
            scale: pop,
            alignment: l.bubbleLeft < l.cloud.left ? Alignment.centerRight : Alignment.centerLeft,
            child: Material(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.text,
                      style: TextStyle(fontFamily: 'Onest', color: cs.onPrimaryContainer, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: widget.onClose,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const StadiumBorder(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(widget.gotIt, style: const TextStyle(fontFamily: 'Onest', fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
