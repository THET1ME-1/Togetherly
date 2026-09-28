import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../main.dart' show LoveApp;
import '../../models/pair_jar.dart';
import '../common/ad_result.dart';
import 'jar_drops.dart';

/// Строка после ролика: капля упала в копилку пары, сколько набралось.
///
/// Ролик смотрят на разных экранах (монеты в профиле, сундук, подарок,
/// возврат серии), поэтому строка кладётся в корневой `Overlay` — выше любого
/// маршрута и нижнего листа — и уходит сама. Так человек узнаёт про копилку,
/// не заходя на главную.
///
/// Награда за ролик приходит, пока реклама ещё на экране и кадры не рисуются.
/// Поэтому строка ждёт, пока приложение снова видно, а убирается по флагу, а
/// не по `entry.mounted`: вставленная без кадра запись «не смонтирована», и
/// таймер её пропускал — строка оставалась навсегда (жалоба 28.09.2026).
Future<void> showJarToast(PairJar jar) async {
  if (!jar.added) return;
  await untilAppVisible();
  final overlay = LoveApp.rootNavigatorKey.currentState?.overlay;
  final context = LoveApp.rootNavigatorKey.currentContext;
  if (overlay == null || context == null || !context.mounted) return;
  final cs = Theme.of(context).colorScheme;
  final bottom = MediaQuery.of(context).padding.bottom + 96;
  final text = jar.filled
      ? trKey('jarToastFull')
      : trKey('jarToast').replaceAll('{k}', '${jar.count}').replaceAll('{n}', '${jar.size}');
  // Наполнилась — показываем полную копилку, а не пустую новую.
  final shown = jar.filled ? PairJar(size: jar.size, drops: List.filled(jar.size, true), bonus: jar.bonus) : jar;
  late final OverlayEntry entry;
  var removed = false;
  void close() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      // Закрыть можно касанием или смахиванием — не ждать таймера.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        onVerticalDragEnd: (_) => close(),
        onHorizontalDragEnd: (_) => close(),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
            ),
            child: Material(
              color: cs.inverseSurface,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      flex: 0,
                      child: JarDrops(
                        jar: shown,
                        mine: cs.inversePrimary,
                        partner: cs.onInverseSurface,
                        dropHeight: 17,
                        gap: 2,
                        popLast: !jar.filled,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
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
  Timer(Duration(milliseconds: jar.filled ? 2800 : 1800), close);
}
