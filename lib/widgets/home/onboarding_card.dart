import 'package:flutter/material.dart';

import '../../models/onboarding_progress.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';

/// Карточка первых действий на главной.
///
/// Пока пары нет — развёрнутый список: главная в этом состоянии короткая
/// (маскот, карта, достижения и лента приходят только с партнёром), и карточка
/// занимает место прежней «подключите партнёра». Как только пара появилась,
/// сворачивается в строку и пропускает вперёд всё, что появилось.
///
/// Правила показа и порядок шагов живут в [OnboardingProgress] — здесь только
/// внешний вид.
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    required this.scheme,
    required this.done,
    required this.hasPartner,
    required this.onStep,
    required this.onHide,
  });

  final ColorScheme scheme;
  final Set<OnboardingStep> done;
  final bool hasPartner;

  /// Тап по шагу — ведём туда, где его выполняют.
  final void Function(OnboardingStep step) onStep;

  /// Скрыть карточку насовсем.
  final VoidCallback onHide;

  AppStrings get _s => LocaleService.current;

  int get _left => OnboardingProgress.order.length - done.length;

  @override
  Widget build(BuildContext context) {
    final collapsed = OnboardingProgress.collapsed(
      hasPartner: hasPartner,
      done: done,
    );
    return collapsed ? _collapsed(context) : _expanded(context);
  }

  // ── Свёрнутая строка: с парой на главной уже есть что показывать ──
  Widget _collapsed(BuildContext context) {
    final next = OnboardingProgress.nextStep(done);
    if (next == null) return const SizedBox.shrink();
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => onStep(next),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              _ring(size: 38, fontSize: 11),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _s.onboardingNext(_label(next).toLowerCase()),
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Развёрнутый список: без пары это главное, что есть на экране ──
  Widget _expanded(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ring(size: 52, fontSize: 13),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s.onboardingTitle,
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _left == 0 ? _s.onboardingDone : _s.onboardingLeft(_left),
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onHide,
                tooltip: _s.onboardingHide,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final step in OnboardingProgress.order) _row(step),
        ],
      ),
    );
  }

  Widget _row(OnboardingStep step) {
    final isDone = done.contains(step);
    final dim = OnboardingProgress.dimmed(step, hasPartner: hasPartner);
    final index = OnboardingProgress.order.indexOf(step) + 1;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isDone ? scheme.primary : scheme.surfaceContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isDone
                ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _label(step),
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 14,
                fontWeight: isDone ? FontWeight.w500 : FontWeight.w600,
                color: isDone ? scheme.onSurfaceVariant : scheme.onSurface,
                decoration: isDone ? TextDecoration.lineThrough : null,
                decorationColor: scheme.onSurfaceVariant,
                decorationThickness: 1,
              ),
            ),
          ),
          if (!isDone && !dim)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    // Приглушённый шаг не кликается: без пары его всё равно не сделать, а
    // ведущий в никуда тап читается как поломка.
    if (isDone || dim) {
      return Opacity(opacity: dim ? 0.45 : 1, child: row);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onStep(step),
      child: row,
    );
  }

  /// Кольцо прогресса. Дуг у Flutter-виджетов достаточно, рисовать нечего:
  /// хватает CircularProgressIndicator с подписью внутри.
  Widget _ring({required double size, required double fontSize}) {
    final total = OnboardingProgress.order.length;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: done.length / total,
              strokeWidth: 4,
              backgroundColor: scheme.surfaceContainer,
              color: scheme.primary,
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '${done.length}/$total',
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _label(OnboardingStep step) => switch (step) {
        OnboardingStep.photo => _s.onboardingStepPhoto,
        OnboardingStep.partner => _s.onboardingStepPartner,
        OnboardingStep.mood => _s.onboardingStepMood,
        OnboardingStep.widget => _s.onboardingStepWidget,
      };
}
