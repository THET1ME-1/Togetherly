import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/mood_trend.dart';

/// График «Среднее настроение» в календаре настроений.
///
/// Точки — дни, недели или месяцы (`moodTrendPoints`): каждый день отдельным
/// кружком за полгода давал 63 точки друг на друге (жалоба владельца
/// 08.11.2026). Вынесен из экрана, чтобы его можно было снять на стенде
/// (`test/goldens/mood_trend_preview.dart`).
class MoodTrendChart extends StatelessWidget {
  const MoodTrendChart({
    super.key,
    required this.points,
    required this.scheme,
    required this.emptyText,
    this.labelOf,
  });

  final List<MoodTrendPoint> points;
  final ColorScheme scheme;

  /// Подпись точки при нажатии (`moodTrendPointLabel`): дата и среднее.
  /// Без неё график показывал голую цифру.
  final String Function(MoodTrendPoint point)? labelOf;

  /// Подпись, когда точка одна или их нет.
  final String emptyText;

  TextStyle get _axisStyle => TextStyle(
        fontFamily: 'Onest',
        color: scheme.onSurfaceVariant,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
      );

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(
            fontFamily: 'Onest',
            fontVariations: const [FontVariation('wght', 400)],
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final labelInterval = (points.length / 6).ceil().toDouble();
    return LineChart(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutExpo,
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant,
            strokeWidth: 1,
            dashArray: [5, 6],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value == 1 || value == 3 || value == 5) {
                  return Text(value.toInt().toString(), style: _axisStyle);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: labelInterval,
              getTitlesWidget: (value, meta) {
                final idx = value.round();
                if (idx < 0 ||
                    idx >= points.length ||
                    (value - idx).abs() >= 0.01 ||
                    idx % labelInterval.toInt() != 0) {
                  return const SizedBox.shrink();
                }
                final date = points[idx].start;
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('${date.day}/${date.month}', style: _axisStyle),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(12),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  labelOf?.call(points[s.spotIndex]) ?? s.y.toStringAsFixed(1),
                  TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: scheme.onInverseSurface,
                  ),
                ),
            ],
          ),
        ),
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: 1,
        maxY: 5,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            // Кривая не выезжает за 5 и под 1 между точками.
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: moodTrendShowsDots(points.length),
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: scheme.surface,
                strokeWidth: 2.5,
                strokeColor: scheme.primary,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.22),
                  scheme.primary.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
