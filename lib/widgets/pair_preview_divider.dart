import 'package:flutter/material.dart';

/// Разделитель половин парного виджета: линия, сердце, линия на белой полосе.
///
/// Повторяет нативную разметку один к одному — `love_widget.xml` на Android
/// (`LinearLayout` 20dp, две линии `#33000000` по весу, `♥` 12sp с отступами
/// 2dp) и `LoveDivider` в `LoveWidget.swift` (те же числа). Превью в каталоге
/// приложения обещало совпадение, но рисовало полосу 14 без линий, и сердце
/// вылезало на половину партнёра: тестер обвёл его на снимке и попросил
/// «поставить ровнее» (17.08.2026).
///
/// Сердце нарисовано иконкой, а не символом `♥`: у шрифта приложения этого
/// глифа нет, подставлялся запасной со своими метриками, и по центру полосы
/// сердце не стояло ни по вертикали, ни по горизонтали.
class PairPreviewDivider extends StatelessWidget {
  const PairPreviewDivider({super.key});

  /// Ширина белой полосы, как в нативной разметке.
  static const double width = 20;

  /// Кегль сердца в нативной разметке; иконке даём тот же размер.
  static const double heartSize = 12;

  static const Color heartColor = Color(0xFFFF6B8A);
  static const Color lineColor = Color(0x33000000);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: Colors.white,
      child: Column(
        children: [
          const Expanded(child: _DividerLine()),
          const SizedBox(height: 2),
          Icon(
            Icons.favorite_rounded,
            size: heartSize,
            color: heartColor,
          ),
          const SizedBox(height: 2),
          const Expanded(child: _DividerLine()),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 1,
      child: ColoredBox(color: PairPreviewDivider.lineColor),
    ),
  );
}
