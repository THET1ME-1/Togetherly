import 'dart:async';

import 'package:flutter/material.dart';

/// Короткое сообщение поверх всего — и поверх нижнего листа.
///
/// Лист воспоминания занимает девять десятых экрана, и снекбар корневого
/// `Scaffold` уезжал под него: «Подпись скопирована» никто не видел. Плашка
/// кладётся в корневой `Overlay`, выше любого маршрута, и уходит сама.
void showFloatingNote(
  BuildContext context,
  String text, {
  IconData icon = Icons.check_rounded,
  Duration duration = const Duration(milliseconds: 1800),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final cs = Theme.of(context).colorScheme;
  final bottom = MediaQuery.of(context).padding.bottom + 96;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 24,
      right: 24,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, (1 - v) * 12), child: child),
            ),
            child: Material(
              color: cs.inverseSurface,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 18, 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: cs.inversePrimary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onInverseSurface,
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
    ),
  );
  overlay.insert(entry);
  Timer(duration, () {
    if (entry.mounted) entry.remove();
  });
}
