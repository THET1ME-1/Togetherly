import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Завеса над миниатюрой записи 18+: снимок размыт, поверх замок.
///
/// Касанием не раскрывается и касаний не перехватывает: открыть снимок можно
/// в самой записи, где обложка раскрывается по касанию. Нужна там, где
/// миниатюру видно мимоходом: плёнка кадров под обложкой, плёнка
/// полноэкранного просмотра, превью ленты на главной, карта воспоминаний
/// (обращение 256, 11.10.2026).
class AdultVeil extends StatelessWidget {
  const AdultVeil({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // `clamp` тянет крайние пиксели: без него размытие у краёв уходит в
          // прозрачность, и по кромке плитки проступает резкий снимок.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: 14, sigmaY: 14, tileMode: TileMode.clamp),
            child: child,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: const Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.lock_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
