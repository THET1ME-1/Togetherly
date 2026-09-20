import 'package:flutter/material.dart';

import '../models/miss_widget_spec.dart';

/// Превью виджета «Скучаю» для каталога: тот же вид, что рисует натив.
///
/// Раскладка и кегль числа описаны в [missCountSize] и [missCountText], а
/// сторож `test/models/miss_widget_spec_test.dart` следит, чтобы Kotlin со
/// Swift держали те же правила.
enum MissCardSize { small, medium, strip }

class MissWidgetCard extends StatelessWidget {
  const MissWidgetCard({
    super.key,
    required this.size,
    required this.myCount,
    required this.partnerCount,
    required this.roles,
    this.meLabel = '',
    this.partnerName = '',
    this.sendLabel = '',
    this.whenLabel = '',
    this.sentToday = false,
    this.myFace,
    this.partnerFace,
  });

  final MissCardSize size;
  final int myCount;
  final int partnerCount;

  /// Цвета виджета по ролям темы — те же, что уходят в натив.
  final Map<String, Color> roles;

  final String meLabel;
  final String partnerName;
  final String sendLabel;
  final String whenLabel;
  final bool sentToday;
  final Widget? myFace;
  final Widget? partnerFace;

  Color _c(String role, Color fallback) => roles[role] ?? fallback;

  TextStyle _num(double px, Color color) => TextStyle(
        fontFamily: 'Unbounded',
        fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
        fontSize: px,
        height: 1,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onFill = size == MissCardSize.strip;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size == MissCardSize.strip ? 26 : 28),
      child: Container(
        color: onFill ? _c('primary', cs.primary) : _c('surface', cs.surface),
        padding: EdgeInsets.all(size == MissCardSize.small ? 14 : 16),
        child: switch (size) {
          MissCardSize.small => _small(cs),
          MissCardSize.medium => _medium(cs),
          MissCardSize.strip => _strip(cs),
        },
      ),
    );
  }

  /// Кнопка во всю ширину: действие тут одно и оно главное. До 20.09.2026 на
  /// её месте был квадрат в углу, который не читался как кнопка.
  Widget _button(ColorScheme cs, {double height = 44}) {
    final ink = _c('onPrimary', cs.onPrimary);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _c('primary', cs.primary),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sentToday ? Icons.check_rounded : Icons.favorite_rounded,
              size: height * 0.4, color: ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(sendLabel,
                style: _text(height * 0.34, ink, w: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    ColorScheme cs, {
    required Widget? face,
    required String name,
    required String count,
    required double numSize,
    required Color background,
    required Color ink,
  }) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (face != null)
                    SizedBox(width: 22, height: 22, child: face),
                  if (face != null) const SizedBox(width: 7),
                  Expanded(
                    child: Text(name,
                        style: _text(11.5, ink, w: FontWeight.w700),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(count, style: _num(numSize, ink), maxLines: 1),
            ],
          ),
        ),
      );

  Widget _small(ColorScheme cs) {
    final ink = _c('onSurface', cs.onSurface);
    final soft = _c('outline', cs.outline);
    final my = missCountText(myCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (partnerFace != null)
              SizedBox(width: 26, height: 26, child: partnerFace),
            if (partnerFace != null) const SizedBox(width: 8),
            Expanded(
              child: Text(partnerName,
                  style: _text(12, _c('onSurfaceVariant', cs.onSurfaceVariant)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(my, style: _num(missCountSize(myCount, base: 30), ink),
                maxLines: 1),
            const SizedBox(width: 8),
            Flexible(
              child: Text('/ ${missCountText(partnerCount)}',
                  style: _text(13, soft, w: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(whenLabel, style: _text(10.5, soft), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        _button(cs, height: 40),
      ],
    );
  }

  Widget _medium(ColorScheme cs) {
    final my = missCountText(myCount);
    final partner = missCountText(partnerCount);
    // Кегль по длиннейшему из двух: плитки одной ширины, и числа в них должны
    // быть одного роста.
    final longest = my.length >= partner.length ? myCount : partnerCount;
    final numSize = missCountSize(longest, base: 30);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tile(cs,
                  face: myFace,
                  name: meLabel,
                  count: my,
                  numSize: numSize,
                  background: _c('primaryContainer', cs.primaryContainer),
                  ink: _c('onPrimaryContainer', cs.onPrimaryContainer)),
              const SizedBox(width: 10),
              _tile(cs,
                  face: partnerFace,
                  name: partnerName,
                  count: partner,
                  numSize: numSize,
                  background: _c('tertiaryContainer', cs.tertiaryContainer),
                  ink: _c('onTertiaryContainer', cs.onTertiaryContainer)),
            ],
          ),
        ),
        if (whenLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(whenLabel,
                style: _text(11, _c('outline', cs.outline)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
        const SizedBox(height: 8),
        _button(cs),
      ],
    );
  }

  Widget _strip(ColorScheme cs) {
    final ink = _c('onPrimary', cs.onPrimary);
    final soft = _c('onPrimarySoft', cs.onPrimary.withValues(alpha: 0.82));
    return Row(
      children: [
        if (partnerFace != null)
          SizedBox(width: 34, height: 34, child: partnerFace),
        if (partnerFace != null) const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sendLabel, style: _text(14, ink, w: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [
                  '${missCountText(myCount)} · ${missCountText(partnerCount)}',
                  whenLabel,
                ].where((s) => s.isNotEmpty).join(' · '),
                style: _text(11.5, soft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _c('onPrimary', cs.onPrimary),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(sentToday ? Icons.check_rounded : Icons.favorite_rounded,
              size: 20, color: _c('primary', cs.primary)),
        ),
      ],
    );
  }
}
