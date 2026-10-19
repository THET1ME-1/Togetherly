import 'package:flutter/material.dart';

import '../theme/app_palettes.dart';

/// Кружок-превью палитры: 4 квадранта из тонов M3-схемы (как в пикере Material
/// You), а не одноцветная точка. Скопировано из Kadr, адаптировано под наш
/// [SchemeFlavor]. Квадранты: primaryContainer / primary / tertiaryContainer /
/// tertiary.
class SeedSwatch extends StatelessWidget {
  final Palette palette;
  final bool selected;
  final double size;
  final SchemeFlavor flavor;
  final VoidCallback? onTap;
  const SeedSwatch({
    super.key,
    required this.palette,
    this.selected = false,
    this.size = 46,
    this.flavor = SchemeFlavor.soft,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Светлая схема из акцента палитры — ровно та, что достанется экрану:
    // вариант считается общим правилом [variantOf], иначе кружок показывает
    // одно, а тема даёт другое.
    final s = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: Brightness.light,
      dynamicSchemeVariant: variantOf(palette, flavor),
    );
    final scheme = Theme.of(context).colorScheme;
    final quads = <Color>[
      s.primaryContainer,
      s.primary,
      s.tertiaryContainer,
      s.tertiary,
    ];
    // Палитра с рисунком показывает его на своём фоне: квадранты из сида
    // говорили бы об акценте, а тема узнаётся ночью и тыквой.
    final badge = palette.badge;
    final face = badge == null
        ? CustomPaint(painter: _QuadrantPainter(quads))
        : ColoredBox(
            color: badge.background,
            child: Padding(
              padding: EdgeInsets.all(size * 0.12),
              child: Image.asset(badge.asset, fit: BoxFit.contain),
            ),
          );
    return GestureDetector(
      onTap: onTap,
      // Горизонтальный список раздаёт детям ЖЁСТКУЮ высоту (лента «Палитра»
      // живёт в SizedBox на 62), и Container со своими 46 растягивался до неё —
      // кружок выходил эллипсом. `widthFactor: 1` оставляет ширину по ребёнку,
      // а высоту забирает Align, центруя кружок. Стережёт
      // test/widgets/palette_strip_shape_test.dart.
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: badge?.background,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                face,
                if (selected)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: size * 0.34,
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

class _QuadrantPainter extends CustomPainter {
  final List<Color> colors;
  _QuadrantPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()..style = PaintingStyle.fill;
    p.color = colors[0];
    canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h / 2), p);
    p.color = colors[1];
    canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h / 2), p);
    p.color = colors[2];
    canvas.drawRect(Rect.fromLTWH(0, h / 2, w / 2, h / 2), p);
    p.color = colors[3];
    canvas.drawRect(Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2), p);
  }

  @override
  bool shouldRepaint(covariant _QuadrantPainter old) =>
      old.colors[0] != colors[0] ||
      old.colors[1] != colors[1] ||
      old.colors[2] != colors[2] ||
      old.colors[3] != colors[3];
}
