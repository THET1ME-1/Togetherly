import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Цифровая клавиатура в облике M3 — та же, что в ScoreMaster.
///
/// Системная панель посреди светлого листа выглядит чужой: своя тема, свои
/// цвета, половина экрана под клавиши с буквами, которые для даты не нужны.
/// Здесь ровно двенадцать клавиш, они берут цвета из активной схемы и живут
/// внутри листа, а не поверх него.
///
/// Поле, которое эта панель обслуживает, должно быть `readOnly: true` с
/// `showCursor: true` — иначе система откроет свою клавиатуру поверх.
class M3NumPad extends StatelessWidget {
  const M3NumPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onDone,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  /// Нажали цифру: приходит одним символом, '0'…'9'.
  final ValueChanged<String> onDigit;

  final VoidCallback onBackspace;

  /// Свернуть панель. Без обработчика клавиша не рисуется, а место под неё
  /// остаётся — сетка не должна прыгать.
  final VoidCallback? onDone;

  /// Кнопка над клавишами («Сохранить раунд» в ScoreMaster). Рисуется, только
  /// когда заданы обе части.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Цвет клавиши «готово». По умолчанию — primary активной схемы.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = accent ?? scheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actionLabel != null && onAction != null) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () {
                HapticFeedback.selectionClick();
                onAction!();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final d in row) ...[
                  Expanded(child: _digit(scheme, d)),
                  if (d != row.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _key(
                scheme,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onBackspace();
                },
                child: Icon(Icons.backspace_outlined,
                    size: 22, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _digit(scheme, '0')),
            const SizedBox(width: 8),
            Expanded(
              child: onDone == null
                  // Пустое место вместо клавиши: сетка остаётся 3×4, и нижний
                  // ряд не разъезжается на две широкие клавиши.
                  ? const SizedBox(height: 56)
                  : _key(
                      scheme,
                      color: accentColor,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onDone!();
                      },
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 26, color: scheme.onPrimary),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _digit(ColorScheme scheme, String d) => _key(
        scheme,
        onTap: () {
          HapticFeedback.selectionClick();
          onDigit(d);
        },
        child: Text(
          d,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      );

  Widget _key(
    ColorScheme scheme, {
    required VoidCallback onTap,
    required Widget child,
    Color? color,
  }) =>
      Material(
        color: color ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(height: 56, child: Center(child: child)),
        ),
      );
}
