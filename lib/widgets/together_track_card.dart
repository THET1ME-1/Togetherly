import 'package:flutter/material.dart';

import '../models/together_track_spec.dart';

/// Превью виджета «Вместе» для каталога: тот же растр и та же дорожка, что
/// рисует натив на рабочем столе.
///
/// Раскладка описана числами в [TogetherTrackSpec], и сторож
/// `test/models/together_track_spec_test.dart` следит, чтобы Kotlin со Swift
/// не разъехались с ними: иначе в приложении одно, а на столе другое.
enum TogetherCardSize { small, medium, large }

class TogetherTrackCard extends StatelessWidget {
  const TogetherTrackCard({
    super.key,
    required this.size,
    required this.days,
    required this.daysLabel,
    required this.percent,
    required this.roles,
    this.startDate = '',
    this.names = '',
    this.previousTitle = '',
    this.previousSub = '',
    this.todayTitle = '',
    this.todaySub = '',
    this.nextTitle = '',
    this.nextSub = '',
    this.anniversaryTitle = '',
    this.anniversarySub = '',
    this.myAvatar,
    this.partnerAvatar,
  });

  final TogetherCardSize size;
  final int days;
  final String daysLabel;
  final int percent;

  /// Цвета виджета по ролям темы — те же, что уходят в натив
  /// (`WidgetThemeSync.rolesOf`).
  final Map<String, Color> roles;

  final String startDate;
  final String names;
  final String previousTitle;
  final String previousSub;
  final String todayTitle;
  final String todaySub;
  final String nextTitle;
  final String nextSub;
  final String anniversaryTitle;
  final String anniversarySub;
  final Widget? myAvatar;
  final Widget? partnerAvatar;

  Color _c(String role, Color fallback) => roles[role] ?? fallback;

  bool get _hasPrevious => previousTitle.isNotEmpty;

  /// Большой размер живёт на светлой поверхности: лента из четырёх строк на
  /// сплошной заливке читалась бы тяжело.
  bool get _onFill => size != TogetherCardSize.large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _onFill ? _c('primary', cs.primary) : _c('surface', cs.surface);
    final dots = _onFill
        ? _c('blockOnPrimary', cs.primaryContainer)
        : _c('trackOnSurface', cs.surfaceContainerHighest);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: CustomPaint(
        painter: _HalftonePainter(background: bg, dots: dots),
        child: Padding(
          padding: EdgeInsets.all(size == TogetherCardSize.small ? 14 : 16),
          child: switch (size) {
            TogetherCardSize.small => _small(cs),
            TogetherCardSize.medium => _medium(cs),
            TogetherCardSize.large => _large(cs),
          },
        ),
      ),
    );
  }

  TextStyle _num(double px, Color color) => TextStyle(
        fontFamily: 'Unbounded',
        fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
        fontSize: px,
        height: 0.95,
        letterSpacing: -px * 0.04,
        color: color,
      );

  TextStyle _text(double px, Color color, {FontWeight w = FontWeight.w600}) =>
      TextStyle(
        fontFamily: 'Onest',
        fontWeight: w,
        fontVariations: [FontVariation('wght', w.value.toDouble())],
        fontSize: px,
        height: 1.15,
        color: color,
      );

  Widget _faces(double side) {
    if (myAvatar == null && partnerAvatar == null) return const SizedBox.shrink();
    return SizedBox(
      width: side * 1.7,
      height: side,
      child: Stack(
        children: [
          if (myAvatar != null)
            SizedBox(width: side, height: side, child: myAvatar),
          if (partnerAvatar != null)
            Positioned(
              left: side * 0.7,
              child: SizedBox(width: side, height: side, child: partnerAvatar),
            ),
        ],
      ),
    );
  }

  Widget _line(Color track, Color fill, Color ring,
          {required bool midStop, double height = 24}) =>
      SizedBox(
        height: height,
        child: CustomPaint(
          painter: _TrackLinePainter(
            percent: percent,
            hasPrevious: _hasPrevious,
            midStop: midStop,
            track: track,
            fill: fill,
            ring: ring,
          ),
          size: Size.infinite,
        ),
      );

  Widget _small(ColorScheme cs) {
    final ink = _c('onPrimary', cs.onPrimary);
    final soft = _c('onPrimarySoft', cs.onPrimary.withValues(alpha: 0.82));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _faces(28),
        const SizedBox(height: 6),
        Text('$days', style: _num(40, ink), maxLines: 1),
        const SizedBox(height: 2),
        Text(daysLabel, style: _text(11.5, soft), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const Spacer(),
        // Подписи вех сюда не помещаются: 160 dp съедают лица, число и
        // подпись, а обрезанная строка читается поломкой. Что впереди,
        // человек смотрит на 4×2 — тут важнее сама дорожка.
        Text(nextSub.isEmpty ? nextTitle : '$nextTitle · $nextSub',
            style: _text(10.5, soft, w: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        _line(_c('blockOnPrimary', cs.primaryContainer), ink,
            _c('primary', cs.primary), midStop: false, height: 20),
      ],
    );
  }

  Widget _medium(ColorScheme cs) {
    final ink = _c('onPrimary', cs.onPrimary);
    final soft = _c('onPrimarySoft', cs.onPrimary.withValues(alpha: 0.82));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$days', style: _num(42, ink), maxLines: 1),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(daysLabel,
                    style: _text(14, soft), maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            _faces(30),
          ],
        ),
        if (startDate.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(startDate, style: _text(11, soft), maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
        const Spacer(),
        _line(_c('blockOnPrimary', cs.primaryContainer), ink,
            _c('primary', cs.primary), midStop: true),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(previousTitle,
                  style: _text(11, soft, w: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 2,
              child: Text(
                [nextTitle, nextSub].where((s) => s.isNotEmpty).join(' · '),
                textAlign: TextAlign.center,
                style: _text(11, ink, w: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(anniversaryTitle,
                  textAlign: TextAlign.end,
                  style: _text(11, soft, w: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ],
    );
  }

  Widget _large(ColorScheme cs) {
    final ink = _c('onSurface', cs.onSurface);
    final soft = _c('onSurfaceVariant', cs.onSurfaceVariant);
    final rows = <({String title, String sub, Color subColor})>[
      if (_hasPrevious)
        (title: previousTitle, sub: previousSub, subColor: soft),
      (title: todayTitle, sub: todaySub, subColor: soft),
      (title: nextTitle, sub: nextSub, subColor: soft),
      (
        title: anniversaryTitle,
        sub: anniversarySub,
        subColor: _c('tertiary', cs.tertiary)
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(names,
                  style: _text(12, soft, w: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            _faces(28),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$days', style: _num(56, ink), maxLines: 1),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(daysLabel, style: _text(14, soft), maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (startDate.isNotEmpty)
                      Text(startDate,
                          style: _text(11, _c('outline', cs.outline)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: TogetherTrackSpec.columnWidth,
                child: CustomPaint(
                  painter: _TrackColumnPainter(
                    rows: rows.length,
                    current: _hasPrevious ? 1 : 0,
                    track: _c('trackOnSurface', cs.surfaceContainerHighest),
                    fill: _c('primary', cs.primary),
                    ring: _c('surface', cs.surface),
                    last: _c('tertiaryContainer', cs.tertiaryContainer),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    for (final r in rows)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  style: _text(14, ink, w: FontWeight.w700),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (r.sub.isNotEmpty)
                                Text(r.sub,
                                    style: _text(11, r.subColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HalftonePainter extends CustomPainter {
  const _HalftonePainter({required this.background, required this.dots});

  final Color background;
  final Color dots;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = dots.withValues(alpha: TogetherTrackSpec.dotOpacity)
      ..isAntiAlias = true;
    for (final d in togetherHalftoneDots(size)) {
      canvas.drawCircle(d.center, d.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) =>
      old.background != background || old.dots != dots;
}

class _TrackLinePainter extends CustomPainter {
  const _TrackLinePainter({
    required this.percent,
    required this.hasPrevious,
    required this.midStop,
    required this.track,
    required this.fill,
    required this.ring,
  });

  final int percent;
  final bool hasPrevious;
  final bool midStop;
  final Color track;
  final Color fill;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = TogetherTrackSpec.trackPad;
    final left = pad;
    final right = size.width - pad;
    final cy = size.height / 2;
    final line = Paint()
      ..strokeWidth = TogetherTrackSpec.trackStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = track;
    canvas.drawLine(Offset(left, cy), Offset(right, cy), line);

    final here = left + (right - left) * percent.clamp(0, 100) / 100;
    canvas.drawLine(Offset(left, cy), Offset(here, cy), line..color = fill);

    final dot = Paint()..isAntiAlias = true;
    canvas.drawCircle(Offset(left, cy), TogetherTrackSpec.stopRadius,
        dot..color = hasPrevious ? fill : track);
    if (midStop) {
      canvas.drawCircle(Offset((left + right) / 2, cy),
          TogetherTrackSpec.stopRadius, dot..color = track);
    }
    canvas.drawCircle(
        Offset(right, cy), TogetherTrackSpec.stopRadius, dot..color = track);
    canvas.drawCircle(
        Offset(here, cy), TogetherTrackSpec.todayRing, dot..color = ring);
    canvas.drawCircle(
        Offset(here, cy), TogetherTrackSpec.todayRadius, dot..color = fill);
  }

  @override
  bool shouldRepaint(_TrackLinePainter old) =>
      old.percent != percent ||
      old.hasPrevious != hasPrevious ||
      old.midStop != midStop ||
      old.track != track ||
      old.fill != fill ||
      old.ring != ring;
}

class _TrackColumnPainter extends CustomPainter {
  const _TrackColumnPainter({
    required this.rows,
    required this.current,
    required this.track,
    required this.fill,
    required this.ring,
    required this.last,
  });

  final int rows;
  final int current;
  final Color track;
  final Color fill;
  final Color ring;
  final Color last;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows <= 0) return;
    final stops = togetherColumnStops(rows);
    final cx = size.width / 2;
    double y(int i) => size.height * stops[i];

    final line = Paint()
      ..strokeWidth = TogetherTrackSpec.columnStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = track;
    canvas.drawLine(Offset(cx, y(0)), Offset(cx, y(rows - 1)), line);
    if (current < rows) {
      canvas.drawLine(
          Offset(cx, y(0)), Offset(cx, y(current)), line..color = fill);
    }

    final dot = Paint()..isAntiAlias = true;
    for (var i = 0; i < rows; i++) {
      if (i == current) {
        canvas.drawCircle(
            Offset(cx, y(i)), TogetherTrackSpec.todayRing, dot..color = ring);
        canvas.drawCircle(
            Offset(cx, y(i)), TogetherTrackSpec.todayRadius, dot..color = fill);
      } else if (i == rows - 1) {
        canvas.drawCircle(
            Offset(cx, y(i)), TogetherTrackSpec.todayRadius, dot..color = last);
      } else {
        canvas.drawCircle(Offset(cx, y(i)), TogetherTrackSpec.todayRadius,
            dot..color = i < current ? fill : track);
      }
    }
  }

  @override
  bool shouldRepaint(_TrackColumnPainter old) =>
      old.rows != rows ||
      old.current != current ||
      old.track != track ||
      old.fill != fill ||
      old.ring != ring ||
      old.last != last;
}
