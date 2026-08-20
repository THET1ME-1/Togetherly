import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/mood_year_grid.dart';
import '../../services/locale_service.dart';

/// Год настроений клетками: строка — неделя, клетка — день, тон — оценка.
///
/// Год идёт сверху вниз, а не слева направо. Пятьдесят три колонки на телефоне
/// ужимались до клетки в пять точек: ни цвет различить, ни попасть пальцем. По
/// вертикали клетке достаётся седьмая часть ширины экрана.
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
    // Показываем только недели с отметками: у пары, отмечавшейся три месяца,
    // сорок пустых строк не сообщают ничего и выталкивают сетку за экран.
    final weeks = visibleWeeks(cells);
    final rows = weeks.length;

    return LayoutBuilder(
      builder: (context, box) {
        const labelWidth = 32.0;
        const gap = 3.0;
        final free = box.maxWidth - labelWidth;
        final side = (free - gap * 6) / 7;
        // Высота подбирается так, чтобы год помещался в экран без прокрутки:
        // делим отведённое место на число видимых недель. Потолок — ширина
        // клетки (крупнее квадрата ей быть незачем), пол — шесть точек, ниже
        // которых тон уже не различить.
        const available = 360.0;
        final fit = rows == 0
            ? side
            : (available - gap * (rows - 1)) / rows;
        final cellH = fit.clamp(6.0, side);
        final height = rows * cellH + gap * (rows - 1);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _weekdayHeader(labelWidth: labelWidth, side: side, gap: gap),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    height: height,
                    child: _monthLabels(weeks, cellH: cellH, gap: gap),
                  ),
                  SizedBox(
                    width: free,
                    height: height,
                    child: _Grid(
                      weeks: weeks,
                      ramp: ramp,
                      side: side,
                      cellH: cellH,
                      gap: gap,
                      empty: scheme.surfaceContainerHighest,
                      onTapDay: onTapDay,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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

  /// Дни недели над столбцами.
  Widget _weekdayHeader({
    required double labelWidth,
    required double side,
    required double gap,
  }) {
    final names = LocaleService.current.shortWeekdays;
    return Row(
      children: [
        SizedBox(width: labelWidth),
        for (var i = 0; i < 7; i++) ...[
          SizedBox(
            width: side,
            child: Text(
              names[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (i < 6) SizedBox(width: gap),
        ],
      ],
    );
  }

  /// Месяц подписан у той недели, с которой начался.
  Widget _monthLabels(
    List<List<MoodCell>> weeks, {
    required double cellH,
    required double gap,
  }) {
    final short = LocaleService.current.shortMonths;
    // Месяц подписан у первой ВИДИМОЙ недели, в которой он встретился:
    // пустые недели свёрнуты, и считать по номеру недели года уже нельзя.
    final firstRow = <int, int>{};
    for (var row = 0; row < weeks.length; row++) {
      for (final c in weeks[row]) {
        if (c.score == null) continue;
        firstRow.putIfAbsent(c.date.month, () => row);
      }
    }
    return Stack(
      children: [
        for (final e in firstRow.entries)
          Positioned(
            top: e.value * (cellH + gap) + cellH / 2 - 8,
            left: 0,
            child: Text(
              short[e.key - 1],
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
      ],
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
    required this.weeks,
    required this.ramp,
    required this.side,
    required this.cellH,
    required this.gap,
    required this.empty,
    this.onTapDay,
  });

  final List<List<MoodCell>> weeks;
  final List<Color> ramp;
  final double side;
  final double cellH;
  final double gap;
  final Color empty;
  final void Function(DateTime day)? onTapDay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: onTapDay == null
          ? null
          : (details) {
              final weekday = (details.localPosition.dx / (side + gap)).floor();
              final week = (details.localPosition.dy / (cellH + gap)).floor();
              if (weekday < 0 || weekday > 6) return;
              if (week < 0 || week >= weeks.length) return;
              final cell = weeks[week][weekday];
              if (cell.score == null) return;
              HapticFeedback.selectionClick();
              onTapDay!(cell.date);
            },
      child: CustomPaint(
        painter: _GridPainter(
          weeks: weeks,
          ramp: ramp,
          side: side,
          cellH: cellH,
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
    required this.weeks,
    required this.ramp,
    required this.side,
    required this.cellH,
    required this.gap,
    required this.empty,
  });

  final List<List<MoodCell>> weeks;
  final List<Color> ramp;
  final double side;
  final double cellH;
  final double gap;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final radius = Radius.circular(cellH / 2);

    for (var row = 0; row < weeks.length; row++) {
      final line = weeks[row];
      final y = row * (cellH + gap);
      var i = 0;
      while (i < line.length) {
        // Серия — одна пилюля от первого дня до последнего: внутри неё ни
        // швов, ни зазоров, в этом весь приём.
        var len = 1;
        while (i + len < line.length &&
            line[i + len].score != null &&
            line[i + len].score == line[i].score) {
          len++;
        }
        final x = i * (side + gap);
        final width = side * len + gap * (len - 1);
        paint.color = line[i].score == null
            ? empty
            : ramp[(line[i].score!.clamp(1, 5)) - 1];
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, width, cellH), radius),
          paint,
        );
        i += len;
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.weeks != weeks ||
      old.side != side ||
      old.cellH != cellH ||
      old.ramp != ramp ||
      old.empty != empty;
}
