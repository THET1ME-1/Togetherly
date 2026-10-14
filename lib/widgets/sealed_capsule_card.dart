import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../models/capsule_schedule.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import 'connect_expressive.dart' show M3ShapeClipper;
import 'memory_save/save_options_sheet.dart' show memoryDateLabel;

/// Пин запечатанной капсулы времени в ленте: вариант 2 «Лист с печатью» из
/// макета https://claude.ai/artifact/P1TYH5PFd6RLu7R3UJi3yz (14.10.2026).
///
/// Карточка как у всех пинов: общая шапка с автором, временем и значком
/// «Капсула» ([header]), под ней лист пина-заметки, только вместо кавычки над
/// краем стоит печать с замком. На листе — дни до открытия, полоса срока от
/// запечатывания до открытия и дата. Содержимое до срока не показывается:
/// касание качает карточку и говорит «ещё рано».
class SealedCapsuleCard extends StatefulWidget {
  final AppTheme theme;

  /// Шапка карточки — та же, что у всех пинов ленты.
  final Widget header;

  /// Когда капсулу запечатали: начало полосы срока.
  final DateTime sealedAt;
  final DateTime openAt;
  final VoidCallback onTapTooEarly;

  /// Удержание карточки: автор может удалить капсулу до срока. Партнёру
  /// не передаётся — капсула не его.
  final VoidCallback? onLongPress;

  /// Часы карточки. Тесты и снимки задают свои, чтобы число дней не плыло.
  @visibleForTesting
  final DateTime Function()? now;

  const SealedCapsuleCard({
    super.key,
    required this.theme,
    required this.header,
    required this.sealedAt,
    required this.openAt,
    required this.onTapTooEarly,
    this.onLongPress,
    this.now,
  });

  @override
  State<SealedCapsuleCard> createState() => _SealedCapsuleCardState();
}

class _SealedCapsuleCardState extends State<SealedCapsuleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle;

  /// Насколько печать поднимается над листом, как кавычка у заметки.
  static const double _sealLift = 24;
  static const double _sealSize = 60;

  @override
  void initState() {
    super.initState();
    _wiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  void _onTap() {
    _wiggle.forward(from: 0);
    widget.onTapTooEarly();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final cs = ProfileTheme.schemeFor(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _wiggle,
          builder: (context, child) {
            // Затухающее покачивание ±0.05 рад.
            final angle = math.sin(_wiggle.value * math.pi * 4) *
                0.05 *
                (1 - _wiggle.value);
            return Transform.rotate(angle: angle, child: child);
          },
          child: Container(
            // Плоский стиль пинов: без тени, свечения и рамки.
            decoration: BoxDecoration(
              color: t.cardSurface,
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.header,
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _sheet(cs),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Лист пина-заметки с печатью над краем.
  Widget _sheet(ColorScheme cs) {
    final s = LocaleService.current;
    final now = (widget.now ?? DateTime.now)();
    final days = capsuleDaysLeft(widget.openAt, now);
    final share = capsuleElapsedShare(widget.sealedAt, widget.openAt, now);
    final ink = cs.onSecondaryContainer;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _sealLift),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 44, 18, 16),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Подпись не влезла рядом с числом (немецкий, крупный шрифт) —
                // уходит под него целиком, а не рвётся посреди слова.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$days',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: ProfileTheme.displayFont,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 0.86,
                          letterSpacing: -2.2,
                          color: ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '${s.tgYearDaysUnit(days)} ${s.capsuleUntilOpen}',
                        style: AppFonts.onest(size: 15, weight: 700, color: ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Сколько срока прошло: ровная полоса M3 с точкой на конце.
                // Волна в проекте — только для идущих процессов (заливка,
                // сжатие), а срок просто отмеряет время.
                LinearProgressIndicator(
                  value: share,
                  minHeight: 4,
                  color: ink,
                  backgroundColor:
                      Color.alphaBlend(ink.withValues(alpha: 0.22), cs.secondaryContainer),
                  stopIndicatorColor: ink,
                  trackGap: 4,
                  borderRadius: BorderRadius.circular(2),
                  // ignore: deprecated_member_use
                  year2023: false,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                  decoration: BoxDecoration(
                    color: cs.inverseSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: cs.onInverseSurface),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          s.capsuleOpensOn(memoryDateLabel(widget.openAt)),
                          style: AppFonts.onest(
                              size: 13, weight: 600, color: cs.onInverseSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Печать лежит поверх края листа и касаний не забирает: касание
        // по карточке целиком говорит «ещё рано».
        Positioned(
          left: 14,
          top: 0,
          child: IgnorePointer(child: _seal()),
        ),
      ],
    );
  }

  /// Печать — «печенье» M3 цвета темы с замком, как «играть» у видео-пина.
  Widget _seal() {
    final t = widget.theme;
    final onFill = AppThemes.onColor(t.fillColor, mode: t.brightness);
    return SizedBox(
      width: _sealSize,
      height: _sealSize,
      child: ClipPath(
        clipper: M3ShapeClipper(MaterialShapes.cookie9Sided),
        child: ColoredBox(
          color: t.fillColor,
          child: Icon(Icons.lock_rounded, size: 26, color: onFill),
        ),
      ),
    );
  }
}
