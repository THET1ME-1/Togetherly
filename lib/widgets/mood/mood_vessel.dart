import 'package:flutter/material.dart';

import '../../models/mood_vessel.dart';
import '../../theme/cycle_colors.dart';
import '../../theme/motion.dart';

/// Сосуд месяца: блоки падают сверху и укладываются кладкой.
///
/// Ставится рядом с календарём-сеткой как второй вид. Сетка отвечает «какое
/// было настроение», сосуд — «сколько нас было друг у друга»: высота блока это
/// события дня, цвет — настроение, щербина — пропуск.
class MoodVessel extends StatefulWidget {
  const MoodVessel({
    super.key,
    required this.days,
    required this.columns,
    this.height = 300,
    this.previousLevel,
  });

  final List<VesselDay> days;

  /// Сколько столбцов в кладке. На узком экране шесть — предел: дальше блок
  /// становится уже пальца, и значок в нём не читается.
  final int columns;

  final double height;

  /// Уровень прошлого месяца в этажах. Пунктирная черта, обгонять которую —
  /// единственное уместное здесь соревнование.
  final int? previousLevel;

  @override
  State<MoodVessel> createState() => _MoodVesselState();
}

class _MoodVesselState extends State<MoodVessel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall;

  @override
  void initState() {
    super.initState();
    _fall = AnimationController(
      vsync: this,
      duration: Motion.long2 + const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant MoodVessel old) {
    super.didUpdateWidget(old);
    // Сменился месяц — кладка наполняется заново, а не подменяется рывком.
    if (old.days.length != widget.days.length ||
        old.days.first.date != widget.days.first.date) {
      _fall.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocks = layoutVessel(widget.days, columns: widget.columns);
    final top = vesselHeight(blocks);

    return LayoutBuilder(
      builder: (context, box) {
        const pad = 12.0;
        const gap = 4.0;
        final width = box.maxWidth - pad * 2;
        final colWidth = (width - gap * (widget.columns - 1)) / widget.columns;
        final inner = widget.height - pad * 2;
        // Этаж сжимается, пока кладка не влезет: у плотного месяца этажей
        // втрое больше, чем у пустого, а сосуд один и тот же.
        final floor = top == 0
            ? 26.0
            : (inner / (top + 1)).clamp(13.0, 30.0).toDouble();

        return Container(
          height: widget.height,
          padding: const EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (widget.previousLevel != null && widget.previousLevel! > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: widget.previousLevel! * floor,
                  child: _PreviousLine(color: cs.primary),
                ),
              for (var i = 0; i < blocks.length; i++)
                _fallingBlock(blocks[i], i, blocks.length, colWidth, floor, gap, cs),
            ],
          ),
        );
      },
    );
  }

  Widget _fallingBlock(
    VesselBlock block,
    int index,
    int total,
    double colWidth,
    double floor,
    double gap,
    ColorScheme cs,
  ) {
    final height = block.floors * floor - 2;
    final start = total == 1 ? 0.0 : (index / total) * 0.7;
    final curve = CurvedAnimation(
      parent: _fall,
      curve: Interval(start, (start + 0.3).clamp(0.0, 1.0),
          curve: Motion.emphasizedIn),
    );

    return Positioned(
      left: block.column * (colWidth + gap),
      bottom: block.bottom * floor,
      width: colWidth,
      height: height,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, child) {
          final t = curve.value;
          return Transform.translate(
            offset: Offset(0, -(1 - t) * widget.height),
            child: Opacity(opacity: t == 0 ? 0 : 1, child: child),
          );
        },
        child: _Block(day: block.day, floor: floor),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.day, required this.floor});

  final VesselDay day;
  final double floor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    // Этаж красится тем, кто его положил: снизу своя отметка, над ней
    // партнёрская, сверху общая близость. Две краски в одном блоке — это и
    // есть «мы оба сегодня были», и читается оно без легенды.
    final floors = <(IconData, Color)>[
      if (day.mineMood != null) (Icons.mood_rounded, day.mineMood!),
      if (day.partnerMood != null) (Icons.mood_rounded, day.partnerMood!),
      if (day.intimacy) (Icons.favorite_rounded, cs.primary),
    ];

    return Semantics(
      label: '${day.date.day}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Column(
              children: [
                // Column идёт сверху вниз, а кладка растёт снизу: свою отметку
                // кладём в основание блока.
                for (final (icon, color) in floors.reversed)
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color),
                      child: Center(
                        child: Icon(
                          icon,
                          size: (floor * 0.5).clamp(11.0, 17.0),
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Месячные — тонкая кромка, а не значок и не этаж: со стороны это
            // просто полоска, и высоту кладки она не двигает. Своя кромка
            // слева, партнёрская справа — как точки у разных краёв клетки в
            // календаре: в паре из двух девушек иначе не разобрать, чья.
            if (day.period)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(
                  color: CycleColors.period(brightness, partner: false),
                ),
              ),
            if (day.partnerPeriod)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(
                  color: CycleColors.period(brightness, partner: true),
                ),
              ),
            Positioned(
              right: 4,
              bottom: 2,
              child: Text(
                '${day.date.day}',
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пунктирная черта уровня прошлого месяца.
class _PreviousLine extends StatelessWidget {
  const _PreviousLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1.5,
        child: CustomPaint(painter: _DashPainter(color)),
      );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 5.0, space = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + space;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}
