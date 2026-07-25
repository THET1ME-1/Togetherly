import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../utils/cycle_math.dart';

/// Аналитика цикла: цифры и графики в сворачиваемом блоке.
///
/// Свёрнут по умолчанию — на экран заходят отметить день, а не изучать
/// статистику. Содержимое строится только раскрытым: графики недёшевы, и
/// собирать их на каждый кадр ради закрытого блока незачем.
///
/// Показываем только то, что посчитано по своим данным. Пока циклов меньше
/// двух, средних не существует — вместо выдуманных «28 дней» блока просто нет.
class CycleAnalytics extends StatefulWidget {
  const CycleAnalytics({
    super.key,
    required this.scheme,
    required this.periodDays,
    required this.periodColor,
  });

  final ColorScheme scheme;

  /// Дни, отмеченные как месячные, — единственный вход всех расчётов.
  final List<DateTime> periodDays;

  final Color periodColor;

  @override
  State<CycleAnalytics> createState() => _CycleAnalyticsState();
}

class _CycleAnalyticsState extends State<CycleAnalytics> {
  bool _expanded = false;

  ColorScheme get _cs => widget.scheme;
  AppStrings get _s => LocaleService.current;

  /// Длины последних циклов — по ним и цифры, и столбики.
  List<int> get _lengths {
    final starts = CycleMath.starts(widget.periodDays);
    if (starts.length < 2) return const [];
    final all = <int>[];
    for (var i = 1; i < starts.length; i++) {
      final gap = starts[i].difference(starts[i - 1]).inDays;
      if (gap >= CycleMath.minPlausible && gap <= CycleMath.maxPlausible) {
        all.add(gap);
      }
    }
    return all.length > CycleMath.windowCycles
        ? all.sublist(all.length - CycleMath.windowCycles)
        : all;
  }

  /// Длительности самих месячных — вторая серия.
  List<int> get _durations {
    final days = widget.periodDays.map((d) => DateTime(d.year, d.month, d.day)).toSet().toList()
      ..sort();
    if (days.isEmpty) return const [];
    final runs = <int>[];
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i].difference(days[i - 1]).inDays == 1) {
        run++;
      } else {
        runs.add(run);
        run = 1;
      }
    }
    runs.add(run);
    return runs.length > CycleMath.windowCycles
        ? runs.sublist(runs.length - CycleMath.windowCycles)
        : runs;
  }

  @override
  Widget build(BuildContext context) {
    final lengths = _lengths;
    if (lengths.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.insights_rounded,
                        size: 22, color: _cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _s.cycleAnalyticsTitle,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontVariations: const [FontVariation('wght', 600)],
                            color: _cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _s.cycleAnalyticsHint(lengths.length),
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 13,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(Icons.expand_more_rounded,
                        color: _cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: _content(lengths),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _content(List<int> lengths) {
    final durations = _durations;
    final avg = (lengths.reduce((a, b) => a + b) / lengths.length).round();
    final min = lengths.reduce((a, b) => a < b ? a : b);
    final max = lengths.reduce((a, b) => a > b ? a : b);
    final spread = max - min;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _numberTile(_s.cycleAverageShort, '$avg', _s.cycleDaysUnit),
            const SizedBox(width: 10),
            _numberTile(_s.cycleRangeShort, '$min–$max', _s.cycleDaysUnit),
            const SizedBox(width: 10),
            _numberTile(
              _s.cycleRegularity,
              spread >= CycleMath.irregularSpread
                  ? _s.cycleRegularityLow
                  : _s.cycleRegularityOk,
              null,
              accent: spread >= CycleMath.irregularSpread
                  ? _cs.error
                  : _cs.primary,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          _s.cycleChartLengths,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(height: 140, child: _lengthsChart(lengths, avg)),
        if (durations.length > 1) ...[
          const SizedBox(height: 20),
          Text(
            _s.cycleChartDurations,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 110, child: _durationsChart(durations)),
        ],
      ],
    );
  }

  Widget _numberTile(String label, String value, String? unit,
      {Color? accent}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: _cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                letterSpacing: -0.5,
                color: accent ?? _cs.onSurface,
              ),
            ),
            if (unit != null)
              Text(
                unit,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 11,
                  color: _cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Длины циклов столбиками. Пунктирная линия — среднее: по ней сразу видно,
  /// какой цикл выбился, а какой лёг в норму.
  Widget _lengthsChart(List<int> lengths, int avg) {
    final maxY = (lengths.reduce((a, b) => a > b ? a : b) + 4).toDouble();
    final minY = (lengths.reduce((a, b) => a < b ? a : b) - 4)
        .clamp(0, 100)
        .toDouble();

    return BarChart(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      BarChartData(
        maxY: maxY,
        minY: minY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 7,
          getDrawingHorizontalLine: (_) => FlLine(
            color: _cs.outlineVariant,
            strokeWidth: 1,
            dashArray: [5, 6],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 7,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 10,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  // Нумеруем от конца: −5 … 0, где 0 — последний цикл.
                  '${value.toInt() - lengths.length + 1}',
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 10,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: avg.toDouble(),
              color: _cs.primary.withValues(alpha: 0.6),
              strokeWidth: 2,
              dashArray: [6, 5],
            ),
          ],
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _cs.inverseSurface,
            getTooltipItem: (_, __, rod, ___) => BarTooltipItem(
              _s.cycleDaysValue(rod.toY.round()),
              TextStyle(
                fontFamily: 'Onest',
                fontSize: 12,
                color: _cs.onInverseSurface,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < lengths.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: lengths[i].toDouble(),
                  width: 18,
                  borderRadius: BorderRadius.circular(9),
                  color: _cs.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Длительность самих месячных — вторая серия, своим цветом.
  Widget _durationsChart(List<int> durations) {
    return LineChart(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      LineChartData(
        minY: 0,
        maxY: (durations.reduce((a, b) => a > b ? a : b) + 2).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (_) => FlLine(
            color: _cs.outlineVariant,
            strokeWidth: 1,
            dashArray: [5, 6],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 2,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 10,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < durations.length; i++)
                FlSpot(i.toDouble(), durations[i].toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            barWidth: 3,
            color: widget.periodColor,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: widget.periodColor,
                strokeWidth: 2,
                strokeColor: _cs.surfaceContainerHigh,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: widget.periodColor.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
