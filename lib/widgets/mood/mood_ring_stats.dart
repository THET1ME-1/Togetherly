import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/mood_summary.dart';
import '../../services/locale_service.dart';
import '../../theme/fonts.dart';
import '../mood_image.dart';

/// Кольцо настроений и тройка лидеров — блок статистики в календаре.
///
/// Прежний блок показывал полосу и девять подписей с процентами: семь из них
/// были по девять процентов, цвет повторялся у разных эмоций, и читать там
/// было нечего. Кольцо отвечает на «чего было больше» сразу, тройка называет
/// лидеров, хвост живёт под кнопкой.
///
/// Цвета мягкие — те же, что у клеток календаря: цвет настроения кладётся на
/// поверхность с прозрачностью, а не заливается в полную силу. Иначе блок
/// кричит громче самой сетки, ради которой открывают экран.
class MoodRingStats extends StatefulWidget {
  const MoodRingStats({
    super.key,
    required this.counts,
    required this.scheme,
  });

  final Map<String, int> counts;
  final ColorScheme scheme;

  @override
  State<MoodRingStats> createState() => _MoodRingStatsState();
}

class _MoodRingStatsState extends State<MoodRingStats> {
  bool _expanded = false;

  /// Мягкий тон настроения: тот же приём, что у клеток сетки.
  static Color soften(Color color, ColorScheme scheme, {double alpha = 0.55}) =>
      Color.alphaBlend(
          color.withValues(alpha: alpha), scheme.surfaceContainerHighest);

  @override
  Widget build(BuildContext context) {
    final summary = MoodSummary.of(widget.counts);
    if (summary.isEmpty) return const SizedBox.shrink();

    final cs = widget.scheme;
    final ru = LocaleService.instance.isRussian;
    final shown = _expanded ? summary.slices : summary.top;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 118,
              height: 118,
              child: CustomPaint(
                painter: _RingPainter(
                  slices: summary.slices,
                  scheme: cs,
                  track: cs.surfaceContainerHighest,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${summary.brightPercent}%',
                        style: AppFonts.unbounded(
                            size: 21, weight: 600, color: cs.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ru ? 'светлых' : 'bright',
                        style: AppFonts.onest(
                            size: 11.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final slice in summary.top)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MoodChip(slice: slice, scheme: cs),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_expanded && summary.restCount > 0) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slice in shown.skip(3))
                _MoodChip(slice: slice, scheme: cs, compact: true),
            ],
          ),
        ],
        if (summary.restCount > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                _expanded
                    ? (ru ? 'Свернуть' : 'Collapse')
                    : (ru
                        ? 'Ещё ${summary.restCount}'
                        : '${summary.restCount} more'),
                style: AppFonts.onest(size: 13.5, weight: 600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.slice,
    required this.scheme,
    this.compact = false,
  });

  final MoodSlice slice;
  final ColorScheme scheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mood = slice.option;
    final tint = _MoodRingStatsState.soften(
        mood?.color ?? scheme.outlineVariant, scheme,
        alpha: 0.35);

    return Container(
      padding: EdgeInsets.fromLTRB(6, 5, compact ? 10 : 12, 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: mood != null && mood.imagePath.isNotEmpty
                ? MoodImage(mood.imagePath, width: 18, height: 18)
                : null,
          ),
          const SizedBox(width: 8),
          if (!compact) ...[
            Flexible(
              child: Text(
                mood?.localizedLabel ?? slice.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.onest(
                    size: 13, weight: 600, color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${slice.percent}%',
            style: AppFonts.onest(
                size: 13, weight: 700, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Кольцо долей. Рисуется дугами с зазором: сегменты не слипаются даже когда
/// доли одинаковые, а тонкая дорожка под ними держит форму на пустых местах.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.slices,
    required this.scheme,
    required this.track,
  });

  final List<MoodSlice> slices;
  final ColorScheme scheme;
  final Color track;

  static const double _stroke = 14;
  static const double _gap = 0.035; // радианы между долями

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(_stroke / 2, _stroke / 2,
        size.width - _stroke, size.height - _stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);

    var start = -math.pi / 2 + _gap / 2;
    for (final slice in slices) {
      final sweep = math.pi * 2 * (slice.percent / 100) - _gap;
      if (sweep <= 0) {
        start += math.pi * 2 * (slice.percent / 100);
        continue;
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = _MoodRingStatsState.soften(
            slice.option?.color ?? scheme.outlineVariant, scheme);
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep + _gap;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.slices != slices || old.track != track;
}
