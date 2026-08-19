import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/mood_year_grid.dart';
import '../../services/locale_service.dart';

/// Год настроений клетками: колонка — неделя, клетка — день, тон — оценка.
///
/// Плитки по месяцам показывали, часто ли человек отмечался. Здесь видно
/// другое: какими были дни. Год целиком помещается в один экран, хорошая
/// неделя читается сплошной полосой, провал — прорехой в столбце.
class MoodYearGridView extends StatelessWidget {
  const MoodYearGridView({
    super.key,
    required this.year,
    required this.scores,
    required this.scheme,
    this.onTapDay,
    this.today,
  });

  final int year;

  /// День → оценка 1…5. Дни без отметки в карте отсутствуют.
  final Map<DateTime, int> scores;
  final ColorScheme scheme;
  final void Function(DateTime day)? onTapDay;
  final DateTime? today;

  /// Пять ступеней тона: от «хуже» к «лучше».
  ///
  /// Тон, а не разные цвета: оценка — величина по одной шкале, и радуга из
  /// пяти красок читалась бы как пять разных вещей. Светлота ступеней разведена
  /// достаточно, чтобы порядок был виден и на чёрно-белом снимке экрана.
  List<Color> _ramp() {
    final base = scheme.primary;
    return [
      Color.alphaBlend(base.withValues(alpha: 0.22), scheme.surfaceContainerHigh),
      Color.alphaBlend(base.withValues(alpha: 0.40), scheme.surfaceContainerHigh),
      Color.alphaBlend(base.withValues(alpha: 0.58), scheme.surfaceContainerHigh),
      Color.alphaBlend(base.withValues(alpha: 0.78), scheme.surfaceContainerHigh),
      base,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cells = moodYearCells(year: year, scores: scores);
    final summary = moodYearSummary(year: year, scores: scores, today: today);
    final ramp = _ramp();
    final columns = (cells.isEmpty ? 0 : cells.last.column) + 1;

    return LayoutBuilder(
      builder: (context, box) {
        // Ширину клетки считаем от места: год — это 53 колонки, и на узком
        // телефоне они обязаны поместиться без прокрутки.
        const labelWidth = 26.0;
        const gap = 2.0;
        final free = box.maxWidth - labelWidth;
        final side = math.max(4.0, (free - gap * (columns - 1)) / columns);
        final height = side * 7 + gap * 6;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  height: height,
                  child: _weekdayLabels(side: side, gap: gap),
                ),
                SizedBox(
                  width: free,
                  height: height,
                  child: _Grid(
                    cells: cells,
                    ramp: ramp,
                    side: side,
                    gap: gap,
                    empty: scheme.surfaceContainerHighest,
                    onTapDay: onTapDay,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: labelWidth),
              child: _monthRuler(cells, columns, side, gap),
            ),
            const SizedBox(height: 12),
            _legend(ramp),
            const SizedBox(height: 10),
            Text(
              _summaryLine(summary),
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  String _summaryLine(MoodYearSummary s) {
    final l = LocaleService.current;
    if (s.average == null) return l.moodYearEmpty;
    // Запятая как разделитель дробной части — русская норма; в остальных
    // языках строка приходит из словаря со своей точкой.
    final avg = s.average!.toStringAsFixed(1);
    final shown = LocaleService.instance.isRussian ? avg.replaceAll('.', ',') : avg;
    return '${l.moodYearAverage(shown)} · ${l.moodYearMissing(s.missing)}';
  }

  /// Подписаны три дня из семи: пн, ср, пт. Все семь на клетке в шесть точек
  /// не читаются, а по трём порядок восстанавливается сам.
  Widget _weekdayLabels({required double side, required double gap}) {
    // Подписаны три дня из семи: имена берутся из словаря, порядок — от
    // понедельника, как во всём приложении.
    final short = LocaleService.current.shortWeekdays;
    final names = {1: short[0], 3: short[2], 5: short[4]};
    return Stack(
      children: [
        for (final e in names.entries)
          Positioned(
            // Подпись прижата к середине своей строки: клетка бывает в шесть
            // точек, и текст, поставленный по её верху, наезжает на соседей.
            top: (e.key - 1) * (side + gap) + side / 2 - 6,
            left: 0,
            child: Text(
              e.value,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 10,
                height: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// Линейка месяцев под сеткой: подпись стоит там, где начался месяц.
  Widget _monthRuler(
      List<MoodCell> cells, int columns, double side, double gap) {
    final short = LocaleService.current.shortMonths;
    final firstColumnOfMonth = <int, int>{};
    for (final c in cells) {
      firstColumnOfMonth.putIfAbsent(c.date.month, () => c.column);
    }
    // Через месяц: двенадцать подписей подряд сливаются в кашу.
    final shown = firstColumnOfMonth.entries.where((e) => e.key.isOdd);
    return SizedBox(
      height: 14,
      child: Stack(
        children: [
          for (final e in shown)
            Positioned(
              left: e.value * (side + gap),
              child: Text(
                short[e.key - 1],
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 10,
                  height: 1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legend(List<Color> ramp) {
    Widget dot(Color c) => Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    final style = TextStyle(
      fontFamily: 'Onest',
      fontSize: 11,
      color: scheme.onSurfaceVariant,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(scheme.surfaceContainerHighest),
            Text(LocaleService.current.moodYearNoMark, style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${LocaleService.current.moodYearWorse} ', style: style),
            for (final c in ramp) dot(c),
            Text(LocaleService.current.moodYearBetter, style: style),
          ],
        ),
      ],
    );
  }
}

/// Сама сетка. Рисуется одним painter'ом: 365 отдельных виджетов на экране —
/// это 365 слоёв на каждый кадр прокрутки.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.cells,
    required this.ramp,
    required this.side,
    required this.gap,
    required this.empty,
    this.onTapDay,
  });

  final List<MoodCell> cells;
  final List<Color> ramp;
  final double side;
  final double gap;
  final Color empty;
  final void Function(DateTime day)? onTapDay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: onTapDay == null
          ? null
          : (details) {
              final column = (details.localPosition.dx / (side + gap)).floor();
              final row = (details.localPosition.dy / (side + gap)).floor();
              if (row < 0 || row > 6) return;
              for (final c in cells) {
                if (c.column == column && c.weekday == row + 1) {
                  HapticFeedback.selectionClick();
                  onTapDay!(c.date);
                  return;
                }
              }
            },
      child: CustomPaint(
        painter: _GridPainter(
          cells: cells,
          ramp: ramp,
          side: side,
          gap: gap,
          empty: empty,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.cells,
    required this.ramp,
    required this.side,
    required this.gap,
    required this.empty,
  });

  final List<MoodCell> cells;
  final List<Color> ramp;
  final double side;
  final double gap;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final r = Radius.circular(side / 2);
    final flat = Radius.circular(side * 0.14);

    for (final c in cells) {
      final x = c.column * (side + gap);
      final y = (c.weekday - 1) * (side + gap);
      final rect = Rect.fromLTWH(x, y, side, side);

      paint.color = c.score == null
          ? empty
          : ramp[(c.score!.clamp(1, 5)) - 1];

      // Пятно серии: скругляем только там, где она начинается и кончается.
      // Внутри серии углы прямые, и соседние клетки склеиваются в полосу.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          // Внутри серии дотягиваем клетку до соседней, чтобы зазор исчез.
          Rect.fromLTWH(
            rect.left,
            rect.top,
            rect.width,
            rect.height + (c.endsRun ? 0 : gap),
          ),
          topLeft: c.startsRun ? r : flat,
          topRight: c.startsRun ? r : flat,
          bottomLeft: c.endsRun ? r : flat,
          bottomRight: c.endsRun ? r : flat,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cells != cells ||
      old.side != side ||
      old.ramp != ramp ||
      old.empty != empty;
}
