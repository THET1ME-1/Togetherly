import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../unfold/unfold_touch.dart';

/// Завеса над миниатюрой записи 18+: снимок размыт, поверх замок.
///
/// Касанием не раскрывается и касаний не перехватывает: открыть снимок можно
/// в самой записи, где обложка раскрывается по касанию. Нужна там, где
/// миниатюру видно мимоходом: плёнка кадров под обложкой, плёнка
/// полноэкранного просмотра, превью ленты на главной, карта воспоминаний
/// (обращение 256, 11.10.2026).
class AdultVeil extends StatelessWidget {
  const AdultVeil({
    super.key,
    required this.child,
    this.sigma = 14,
    this.iconSize = 18,
  });

  final Widget child;

  /// Сила размытия. Плитке хватает 14, кадру на весь экран нужно больше:
  /// иначе силуэт читается.
  final double sigma;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // Метка для полёта кадра в просмотр: под размытием картинка чистая, и
    // без метки в полёт ушёл бы открытый снимок.
    return UnfoldVeiled(
      child: ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // `clamp` тянет крайние пиксели: без него размытие у краёв уходит в
          // прозрачность, и по кромке плитки проступает резкий снимок.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
            child: child,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.lock_rounded,
                          color: Colors.white, size: iconSize),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
