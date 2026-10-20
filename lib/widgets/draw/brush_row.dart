import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/draw_stroke.dart';
import '../../models/stroke_brush.dart';
import 'stroke_painting.dart';

/// Ряд кистей в панели холста (макет «Кисти и ластик», вариант «А. Ряд
/// образцов»): пять плиток, в каждой мазок этой кистью, под рядом имя и одна
/// строка, чем кисть хороша.
///
/// Мазок рисует тот же `paintStroke`, что и холст: образец не может
/// разойтись с тем, что потом ляжет на лист.
class BrushRow extends StatelessWidget {
  const BrushRow({
    super.key,
    required this.brushes,
    required this.selected,
    required this.names,
    required this.notes,
    required this.fill,
    required this.onFill,
    required this.onSelect,
    this.side = false,
  });

  final List<StrokeBrush> brushes;
  final StrokeBrush selected;
  final Map<StrokeBrush, String> names;
  final Map<StrokeBrush, String> notes;

  /// Цвет темы и то, что читается поверх него: так же, как выбранный
  /// инструмент в ряду выше.
  final Color fill;
  final Color onFill;

  final ValueChanged<StrokeBrush> onSelect;
  final bool side;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final brush in brushes) ...[
              Expanded(
                child: _Tile(
                  key: ValueKey('brush-${brush.name}'),
                  label: names[brush] ?? brush.name,
                  selected: brush == selected,
                  color: brush == selected ? fill : cs.surfaceContainerHigh,
                  height: side ? 46 : 52,
                  onTap: () => onSelect(brush),
                  child: CustomPaint(
                    painter: _BrushSamplePainter(
                      brush,
                      brush == selected ? onFill : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (brush != brushes.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: names[selected] ?? selected.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              TextSpan(text: ' · ${notes[selected] ?? ''}'),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 13,
            height: 1.3,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Режимы ластика: твёрдый, мягкий, линия целиком. Подписи стоят в самих
/// плитках: режимов три, и на них хватает места.
class EraserModeRow extends StatelessWidget {
  const EraserModeRow({
    super.key,
    required this.modes,
    required this.selected,
    required this.names,
    required this.fill,
    required this.onFill,
    required this.onSelect,
    this.side = false,
  });

  final List<EraserMode> modes;
  final EraserMode selected;
  final Map<EraserMode, String> names;
  final Color fill;
  final Color onFill;
  final ValueChanged<EraserMode> onSelect;
  final bool side;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mode in modes) ...[
          Expanded(
            child: _Tile(
              key: ValueKey('eraser-${mode.name}'),
              label: names[mode] ?? mode.name,
              selected: mode == selected,
              color: mode == selected ? fill : cs.surfaceContainerHigh,
              onTap: () => onSelect(mode),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: side ? 36 : 40,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _EraserSamplePainter(
                            mode,
                            paper: cs.surfaceContainerLowest,
                            ink: cs.onSurfaceVariant,
                            accent: cs.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      names[mode] ?? mode.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: mode == selected ? onFill : cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (mode != modes.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Плитка выбора: заливка и скругление, без обводки — как кнопки ряда
/// инструментов выше.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
    this.height,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: height == null
                ? child
                : SizedBox(
                    height: height,
                    width: double.infinity,
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Волна во всю плитку этой кистью.
class _BrushSamplePainter extends CustomPainter {
  const _BrushSamplePainter(this.brush, this.color);

  final StrokeBrush brush;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    paintStroke(
      canvas,
      _wave(size, inset: 10, amplitude: 0.22),
      color.toARGB32(),
      brush == StrokeBrush.airbrush ? 6 : 5,
      false,
      size,
      brush: brush,
      seed: 4,
    );
  }

  @override
  bool shouldRepaint(_BrushSamplePainter old) =>
      old.brush != brush || old.color != color;
}

/// Две линии на листе и то, как их снимает этот режим ластика.
class _EraserSamplePainter extends CustomPainter {
  const _EraserSamplePainter(
    this.mode, {
    required this.paper,
    required this.ink,
    required this.accent,
  });

  final EraserMode mode;
  final Color paper;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    canvas.saveLayer(Offset.zero & size, Paint());
    final wave = _wave(size, inset: 8, amplitude: 0.2);
    const straight = [DrawPoint(0.1, 0.78), DrawPoint(0.9, 0.7)];
    // «Линия целиком» убирает волну полностью: остаётся только прямая.
    if (mode != EraserMode.whole) {
      paintStroke(canvas, wave, ink.toARGB32(), 4.5, false, size);
    }
    paintStroke(canvas, straight, accent.toARGB32(), 3.5, false, size);
    if (mode != EraserMode.whole) {
      final cut = [DrawPoint(0.5, 0.0), DrawPoint(0.5, 1.0)];
      paintStroke(
        canvas,
        cut,
        0,
        size.width * 0.2,
        true,
        size,
        brush: brushForEraser(mode),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EraserSamplePainter old) =>
      old.mode != mode ||
      old.paper != paper ||
      old.ink != ink ||
      old.accent != accent;
}

/// Один период синуса поперёк плитки, в долях её размера.
List<DrawPoint> _wave(
  Size size, {
  required double inset,
  required double amplitude,
}) {
  const steps = 40;
  final from = inset / size.width;
  final to = 1 - from;
  return [
    for (var i = 0; i <= steps; i++)
      DrawPoint(
        from + (to - from) * i / steps,
        0.5 + math.sin(i / steps * 2 * math.pi) * amplitude,
      ),
  ];
}
