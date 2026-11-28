import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';

/// Мелкие детали листов повтора и напоминаний «Наших дат»: счётчик, сегменты,
/// радиостроки, пилюля, кружок дня недели. Цвета — роли схемы темы.

/// «− N +» на пилюле.
class DateStepper extends StatelessWidget {
  const DateStepper({
    super.key,
    required this.scheme,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.compact = false,
  });

  final ColorScheme scheme;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final h = compact ? 40.0 : 48.0;
    Widget btn(IconData icon, int next, String key) => SizedBox(
          width: compact ? 40 : 44,
          height: h,
          child: IconButton(
            key: ValueKey(key),
            padding: EdgeInsets.zero,
            onPressed: next < min || next > max
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onChanged(next);
                  },
            icon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
        );
    return Container(
      height: h,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, value - 1, 'stepper-minus'),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28),
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: AppFonts.unbounded(size: compact ? 15 : 18, weight: 700, color: cs.onSurface),
            ),
          ),
          btn(Icons.add_rounded, value + 1, 'stepper-plus'),
        ],
      ),
    );
  }
}

/// Сегменты на пилюле — по ширине; длинная подпись ужимается, а не режется.
class DateSegmented<T> extends StatelessWidget {
  const DateSegmented({super.key, required this.scheme, required this.value, required this.items, required this.onChanged});

  final ColorScheme scheme;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          for (final (v, label) in items)
            Expanded(
              child: Semantics(
                selected: v == value,
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: AppFonts.onest(
                          size: 13,
                          weight: 700,
                          color: v == value ? cs.onPrimary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Радиостроки в карточке; у строки может быть своё поле справа.
class DateChoices<T> extends StatelessWidget {
  const DateChoices({
    super.key,
    required this.scheme,
    required this.value,
    required this.items,
    required this.onChanged,
    this.trailing = const {},
  });

  final ColorScheme scheme;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final Map<T, Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          for (final (v, label) in items)
            Semantics(
              selected: v == value,
              inMutuallyExclusiveGroup: true,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    // Поле справа (дата «до», число раз) не шире трёх пятых
                    // строки и ужимается: на 320 точках с крупным шрифтом оно
                    // выталкивало строку за край.
                    child: LayoutBuilder(
                      builder: (context, box) => Row(
                        children: [
                          Icon(
                            v == value ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                            size: 24,
                            color: v == value ? cs.primary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(label, style: AppFonts.onest(size: 16, weight: 600, color: cs.onSurface)),
                          ),
                          if (trailing[v] != null) ...[
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: trailing[v],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Пилюля-значение справа от строки: дата «до», время напоминания.
class DatePill extends StatelessWidget {
  const DatePill({super.key, required this.scheme, required this.active, required this.text, required this.onTap});

  final ColorScheme scheme;
  final bool active;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final bg = active ? cs.primaryContainer : cs.surfaceContainerHighest;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            text,
            style: AppFonts.onest(
              size: 14,
              weight: 700,
              // Текст — читаемый по самой заливке: у розовой темы
              // onPrimaryContainer тоже розовый.
              color: active ? AppThemes.onColor(bg) : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Кружок дня недели в своём повторе.
class DayCircle extends StatelessWidget {
  const DayCircle({super.key, required this.scheme, required this.label, required this.selected, required this.onTap});

  final ColorScheme scheme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? cs.primary : cs.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: AppFonts.onest(size: 13, weight: 700, color: selected ? cs.onPrimary : cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Подпись раздела листа.
class DateSectionLabel extends StatelessWidget {
  const DateSectionLabel(this.text, {super.key, required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: AppFonts.onest(size: 13, weight: 700, color: scheme.onSurfaceVariant)),
      );
}

/// Кнопки «Отмена» и главное действие внизу листа.
class DateSheetButtons extends StatelessWidget {
  const DateSheetButtons({
    super.key,
    required this.cancel,
    required this.confirm,
    required this.onConfirm,
    this.confirmKey,
  });

  final String cancel;
  final String confirm;
  final VoidCallback? onConfirm;
  final Key? confirmKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          // Отмена — нейтральная: тема заливает акцентом все FilledButton, и
          // две одинаковые кнопки рядом не различались.
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurface,
            ),
            child: Text(cancel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            key: confirmKey,
            onPressed: onConfirm,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(confirm),
          ),
        ),
      ],
    );
  }
}
