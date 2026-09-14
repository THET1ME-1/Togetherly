import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/year_ring_spec.dart';

/// Цвета «Кольца года» — три роли темы, те же, что уходят в нативные виджеты.
class YearRingColors {
  const YearRingColors({
    required this.primary,
    required this.onPrimary,
    required this.tertiaryContainer,
  });

  final Color primary;
  final Color onPrimary;
  final Color tertiaryContainer;

  Color get soft => onPrimary.withValues(alpha: YearRingSpec.softAlpha);
}

/// Готовые подписи: карточка не знает про языки и склонения.
class YearRingTexts {
  const YearRingTexts({
    required this.daysCaption,
    required this.untilAnniversary,
    required this.daysLeftUnit,
    required this.anniversaryLine,
    required this.monthsShort,
    required this.memoriesUnit,
    required this.smallLine,
  });

  /// Под числом в кольце: «Дней вместе».
  final String daysCaption;
  final String untilAnniversary;
  final String daysLeftUnit;
  final String anniversaryLine;
  final String monthsShort;
  final String memoriesUnit;

  /// Строка под кольцом 2×2: «Ещё 240 дней».
  final String smallLine;
}

/// «Кольцо года» в том виде, в каком его рисуют виджеты рабочего стола:
/// кольцо с числом дней и меткой сегодняшнего дня, справа обратный отсчёт до
/// годовщины, под чертой месяцы и воспоминания.
///
/// Рисуется в точках среднего виджета iPhone (338×158 и 158×158), а в каталог
/// попадает через `FittedBox` — так превью совпадает с виджетом по пропорциям
/// при любой ширине карточки, и ничего не вылезает за её край.
class YearRingCard extends StatelessWidget {
  const YearRingCard({
    super.key,
    required this.small,
    required this.colors,
    required this.texts,
    required this.daysTotal,
    required this.daysLeft,
    required this.months,
    required this.memories,
    required this.progress,
  });

  final bool small;
  final YearRingColors colors;
  final YearRingTexts texts;
  final int daysTotal;
  final int daysLeft;
  final int months;
  final int memories;
  final double progress;

  static const _font = 'Onest';

  @override
  Widget build(BuildContext context) {
    final w = small ? YearRingSpec.smallSide : YearRingSpec.mediumWidth;
    final h = small ? YearRingSpec.smallSide : YearRingSpec.mediumHeight;
    // Занимает всю отведённую ширину в пропорциях виджета, а содержимое
    // масштабируется целиком: так карточка каталога и картинка для лончера
    // показывают ровно ту раскладку, что стоит на рабочем столе.
    return AspectRatio(
      aspectRatio: w / h,
      child: FittedBox(
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            width: w,
            height: h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: small ? _small(w, h) : _medium(w, h),
            ),
          ),
        ),
      ),
    );
  }

  Widget _medium(double w, double h) {
    const ring = YearRingSpec.ring;
    const stroke = YearRingSpec.stroke;
    final center = Offset(YearRingSpec.padLeft + ring / 2, h / 2);
    final glow = YearRingSpec.arcEnd(center, (ring - stroke) / 2, progress);
    final right =
        w -
        YearRingSpec.padLeft -
        ring -
        YearRingSpec.gap -
        YearRingSpec.padRight;

    final leftNum = '$daysLeft';
    final stats =
        '$months ${texts.monthsShort}    $memories ${texts.memoriesUnit}';
    final statsSize = YearRingSpec.fitText(
      base: 12.5,
      chars: stats.length,
      width: right,
    );
    final dateSize = YearRingSpec.fitText(
      base: 12,
      chars: texts.anniversaryLine.length,
      width: right,
    );
    // Число отсчёта и слово после него делят одну строку: слово набрано в
    // 0.375 кегля числа, между ними 6 точек.
    final countSize = math.min(
      40.0,
      (right - 6) /
          (leftNum.length * YearRingSpec.digitEm +
              texts.daysLeftUnit.length * YearRingSpec.letterEm * 0.375),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: YearRingBackdropPainter(
              colors: colors,
              glow: glow,
              arcs: true,
            ),
          ),
        ),
        Positioned(
          left: YearRingSpec.padLeft,
          top: (h - ring) / 2,
          child: _ring(ring, stroke, 36, texts.daysCaption, 11.5),
        ),
        Positioned(
          left: YearRingSpec.padLeft + ring + YearRingSpec.gap,
          width: right,
          top: 0,
          bottom: 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _text(texts.untilAnniversary, 11, FontWeight.w600, colors.soft),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  _text(
                    leftNum,
                    countSize,
                    FontWeight.w800,
                    colors.onPrimary,
                    height: 1,
                    spacing: -countSize * 0.03,
                  ),
                  const SizedBox(width: 6),
                  _text(
                    texts.daysLeftUnit,
                    countSize * 0.375,
                    FontWeight.w700,
                    colors.onPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              _text(
                texts.anniversaryLine,
                dateSize,
                FontWeight.w500,
                colors.soft,
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                color: colors.onPrimary.withValues(
                  alpha: YearRingSpec.hairlineAlpha,
                ),
              ),
              Row(
                children: [
                  _stat('$months', texts.monthsShort, statsSize),
                  const SizedBox(width: 16),
                  _stat('$memories', texts.memoriesUnit, statsSize),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _small(double w, double h) {
    const ring = YearRingSpec.smallRing;
    const stroke = YearRingSpec.smallStroke;
    const top = 10.0;
    final center = Offset(w / 2, top + ring / 2);
    final glow = YearRingSpec.arcEnd(center, (ring - stroke) / 2, progress);
    final lineSize = YearRingSpec.fitText(
      base: 11.5,
      chars: texts.smallLine.length,
      width: w - 24,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: YearRingBackdropPainter(
              colors: colors,
              glow: glow,
              arcs: false,
            ),
          ),
        ),
        Positioned(
          left: (w - ring) / 2,
          top: top,
          child: _ring(ring, stroke, 34, texts.daysCaption, 11),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: top + ring + 9,
          child: Center(
            child: _text(
              texts.smallLine,
              lineSize,
              FontWeight.w700,
              colors.onPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ring(
    double side,
    double stroke,
    double maxNum,
    String caption,
    double captionSize,
  ) {
    final inner = side - stroke * 2;
    final number = '$daysTotal';
    final numSize = YearRingSpec.numberSize(
      inner: inner,
      digits: number.length,
      max: maxNum,
    );
    final capSize = YearRingSpec.fitText(
      base: captionSize,
      chars: caption.length,
      width: inner * 0.86,
    );
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(side),
            painter: YearRingArcPainter(
              progress: progress,
              stroke: stroke,
              track: colors.onPrimary.withValues(
                alpha: YearRingSpec.trackAlpha,
              ),
              fill: colors.onPrimary,
              dot: colors.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _text(
                number,
                numSize,
                FontWeight.w800,
                colors.onPrimary,
                height: 1,
                spacing: -numSize * 0.03,
              ),
              const SizedBox(height: 3),
              _text(caption, capSize, FontWeight.w600, colors.soft),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String unit, double size) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: colors.onPrimary,
          ),
        ),
        TextSpan(
          text: ' $unit',
          style: TextStyle(fontWeight: FontWeight.w500, color: colors.soft),
        ),
      ],
    ),
    maxLines: 1,
    softWrap: false,
    style: TextStyle(fontFamily: _font, fontSize: size),
  );

  Widget _text(
    String text,
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double spacing = 0,
  }) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    style: TextStyle(
      fontFamily: _font,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    ),
  );
}

/// Фон «Кольца года»: градиент от светлого тона заливки к глубокому, пятно
/// третьего цвета темы в правом верхнем углу, свечение у конца дуги и две
/// полупрозрачные дуги в углу. Повторяют его `WidgetImages.ringBackdrop` и
/// `YearRingBackdrop` в расширении iPhone.
class YearRingBackdropPainter extends CustomPainter {
  const YearRingBackdropPainter({
    required this.colors,
    required this.glow,
    required this.arcs,
  });

  final YearRingColors colors;
  final Offset glow;
  final bool arcs;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Направление градиента 140°, как в макете: сверху слева вниз направо.
    const dx = 0.6428, dy = 0.7660;
    final len = (size.width * dx).abs() + (size.height * dy).abs();
    final c = rect.center;
    final from = c - Offset(dx, dy) * (len / 2);
    final to = c + Offset(dx, dy) * (len / 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            YearRingSpec.lightOf(colors.primary),
            colors.primary,
            YearRingSpec.deepOf(colors.primary),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromPoints(from, to)),
    );

    // Пятно третьего цвета: эллипс 180×140 в правом верхнем углу.
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.scale(1, 140 / 180);
    canvas.drawCircle(
      Offset.zero,
      180,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors.tertiaryContainer.withValues(alpha: 0.38),
            colors.tertiaryContainer.withValues(alpha: 0),
          ],
          stops: const [0, 0.7],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 180)),
    );
    canvas.restore();

    canvas.drawCircle(
      glow,
      120,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors.onPrimary.withValues(alpha: 0.26),
            colors.onPrimary.withValues(alpha: 0),
          ],
          stops: const [0, 0.7],
        ).createShader(Rect.fromCircle(center: glow, radius: 120)),
    );

    if (arcs) {
      final arcCenter = Offset(size.width - 38, -10);
      final paint = Paint()..style = PaintingStyle.stroke;
      canvas.drawCircle(
        arcCenter,
        90,
        paint
          ..strokeWidth = 18
          ..color = colors.onPrimary.withValues(alpha: 0.10),
      );
      canvas.drawCircle(
        arcCenter,
        130,
        paint
          ..strokeWidth = 10
          ..color = colors.onPrimary.withValues(alpha: 0.06),
      );
    }
  }

  @override
  bool shouldRepaint(YearRingBackdropPainter old) =>
      old.glow != glow ||
      old.arcs != arcs ||
      old.colors.primary != colors.primary ||
      old.colors.onPrimary != colors.onPrimary ||
      old.colors.tertiaryContainer != colors.tertiaryContainer;
}

/// Кольцо: дорожка, дуга от двенадцати часов по часовой и метка сегодняшнего
/// дня на её конце.
class YearRingArcPainter extends CustomPainter {
  const YearRingArcPainter({
    required this.progress,
    required this.stroke,
    required this.track,
    required this.fill,
    required this.dot,
  });

  final double progress;
  final double stroke;
  final Color track;
  final Color fill;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true
      ..color = track;
    canvas.drawCircle(c, r, paint);

    final p = progress.clamp(0.0, 1.0);
    // На нулевой дуге круглый конец рисует точку на двенадцати часах — в
    // первый день года это читается как сбой.
    if (p > 0.002) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -1.5707963267948966,
        p * 6.283185307179586,
        false,
        paint
          ..color = fill
          ..strokeCap = StrokeCap.round,
      );
    }
    final end = YearRingSpec.arcEnd(c, r, p);
    canvas.drawCircle(end, stroke * 0.95, Paint()..color = dot);
    canvas.drawCircle(
      end,
      stroke * 0.95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.55
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(YearRingArcPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.track != track ||
      old.fill != fill ||
      old.dot != dot;
}
