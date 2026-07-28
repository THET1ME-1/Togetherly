import 'package:flutter/material.dart';

import '../../models/onboarding_progress.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';

/// Карточка первых действий пары на главной.
///
/// Показывается только когда пара собралась: в одиночку эти шаги не закрыть.
/// Сразу после подключения список развёрнут — это и есть обучение; как только
/// сделан первый шаг, сворачивается в строку и пропускает вперёд маскота,
/// карту, достижения и ленту.
///
/// Правила показа и порядок шагов живут в [OnboardingProgress] — здесь только
/// внешний вид.
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    required this.scheme,
    required this.done,
    required this.onStep,
    required this.onHide,
  });

  final ColorScheme scheme;
  final Set<OnboardingStep> done;

  /// Тап по шагу — ведём туда, где его выполняют.
  final void Function(OnboardingStep step) onStep;

  /// Скрыть карточку насовсем.
  final VoidCallback onHide;

  AppStrings get _s => LocaleService.current;

  List<OnboardingStep> get _steps => OnboardingProgress.order;

  int get _doneCount => _steps.where(done.contains).length;

  int get _left => _steps.length - _doneCount;

  @override
  Widget build(BuildContext context) {
    return OnboardingProgress.collapsed(done: done)
        ? _collapsed(context)
        : _expanded(context);
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
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
              // Закрыть можно и отсюда: свёрнутая строка живёт неделями, и
              // человеку не должно приходиться разворачивать её ради крестика.
              IconButton(
                onPressed: onHide,
                tooltip: _s.onboardingSkip,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Развёрнутый список: первый заход после подключения ──
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
            ],
          ),
          const SizedBox(height: 6),
          for (final step in _steps) _row(step),
          const SizedBox(height: 2),
          // «Пропустить» словом, а не одним крестиком: обучение должно быть
          // предложением, и отказаться от него нужно уметь с первого взгляда.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onHide,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _s.onboardingSkip,
                style: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(OnboardingStep step) {
    final isDone = done.contains(step);
    final index = _steps.indexOf(step) + 1;

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
          if (!isDone)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    // Пройденный шаг не кликается: вести некуда, всё уже сделано.
    if (isDone) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onStep(step),
      child: row,
    );
  }

  /// Кольцо прогресса. Дуг у Flutter-виджетов достаточно, рисовать нечего:
  /// хватает CircularProgressIndicator с подписью внутри.
  Widget _ring({required double size, required double fontSize}) {
    final total = _steps.length;
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
              value: _doneCount / total,
              strokeWidth: 4,
              backgroundColor: scheme.surfaceContainer,
              color: scheme.primary,
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$_doneCount/$total',
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
        OnboardingStep.mood => _s.onboardingStepMood,
        OnboardingStep.widget => _s.onboardingStepWidget,
      };
}
