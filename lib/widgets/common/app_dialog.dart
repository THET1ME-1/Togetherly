import 'package:flutter/material.dart';

import '../../theme/fonts.dart';

import '../../services/locale_service.dart';
import '../app_sheet.dart';

/// Единый стиль для всех меню приложения: подтверждения, сообщения, ввод строки
/// и снэкбары.
///
/// **Всё это — нижние листы, а не диалоги по центру.** Диалог посреди экрана
/// требует тянуться большим пальцем к середине, а на телефонах с кнопочной
/// навигацией ещё и жил впритык к панели: лист через [showAppSheet] выезжает
/// снизу, держит отступ под системные кнопки и закрывается смахиванием.
///
/// Форма и цвета берутся из активной темы (`colorScheme`), поэтому всё
/// перекрашивается при смене темы само.
abstract final class AppDialog {
  /// Лист-подтверждение с заголовком, текстом и двумя кнопками.
  ///
  /// Возвращает `true`, если пользователь подтвердил действие.
  /// Для деструктивных действий (удаление/сброс) передай [destructive] = true —
  /// кнопка подтверждения станет красной.
  static Future<bool> confirm(
    BuildContext context, {
    String? title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
    IconData? icon,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    // Деструктивное действие — тональная кнопка на errorContainer, а не красный
    // текст: видно, что опасное, но кнопка остаётся кнопкой.
    final confirmBg = destructive ? cs.errorContainer : cs.primary;
    final confirmFg = destructive ? cs.onErrorContainer : cs.onPrimary;

    final result = await showAppSheet<bool>(
      context,
      builder: (ctx) => SheetScaffold(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                _iconChip(icon, destructive ? cs.error : cs.primary, cs),
                const SizedBox(height: 14),
              ],
              if (title != null) ...[
                Text(title, style: _titleStyle(cs)),
                const SizedBox(height: 8),
              ],
              Text(
                message,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 15,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _flatButton(
                      cs,
                      label: cancelLabel ?? s.cancel,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _filledButton(
                      label: confirmLabel ?? s.confirm,
                      background: confirmBg,
                      foreground: confirmFg,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  /// Лист-сообщение с одной кнопкой «ОК».
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    String? buttonLabel,
    IconData? icon,
  }) {
    final s = LocaleService.current;
    return showAppSheet<void>(
      context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SheetScaffold(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  _iconChip(icon, cs.primary, cs),
                  const SizedBox(height: 14),
                ],
                Text(title, style: _titleStyle(cs)),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 15,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: _filledButton(
                    label: buttonLabel ?? s.ok,
                    background: cs.primary,
                    foreground: cs.onPrimary,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Лист с одним полем ввода: имя холста, название рисунка, свой текст.
  ///
  /// Возвращает введённую строку или null, если отменили. Пустую строку не
  /// отдаёт — кнопка подтверждения на ней просто не срабатывает.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? label,
    String? hint,
    String initial = '',
    String? confirmLabel,
    String? cancelLabel,
    int maxLength = 60,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.sentences,
  }) {
    final s = LocaleService.current;
    return showAppSheet<String>(
      context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final controller = TextEditingController(text: initial)
          ..selection = TextSelection(
            baseOffset: 0,
            extentOffset: initial.length,
          );

        void submit() {
          final value = controller.text.trim();
          if (value.isEmpty) return;
          Navigator.pop(ctx, value);
        }

        return SheetScaffold(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(cs)),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: maxLength,
                  maxLines: maxLines,
                  minLines: 1,
                  textCapitalization: capitalization,
                  textInputAction: maxLines > 1
                      ? TextInputAction.newline
                      : TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    counterText: '',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _flatButton(
                        cs,
                        label: cancelLabel ?? s.cancel,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _filledButton(
                        label: confirmLabel ?? s.done,
                        background: cs.primary,
                        foreground: cs.onPrimary,
                        onPressed: submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── общие кусочки оформления ─────────────────────────────────────────────

  static TextStyle _titleStyle(ColorScheme cs) => AppFonts.unbounded(
        size: 21,
        weight: 700,
        letterSpacing: -0.4,
        color: cs.onSurface,
      );

  static Widget _iconChip(IconData icon, Color color, ColorScheme cs) =>
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 26),
      );

  static Widget _flatButton(
    ColorScheme cs, {
    required String label,
    required VoidCallback onPressed,
  }) =>
      TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );

  static Widget _filledButton({
    required String label,
    required Color background,
    required Color foreground,
    required VoidCallback onPressed,
  }) =>
      FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      );
}

/// Снэкбары в едином стиле (форма/поведение — из `snackBarTheme`).
///
/// Слева — иконка-статус, справа от текста — опциональное действие.
abstract final class AppSnack {
  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color iconColor,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  /// Успех (зелёная галочка).
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF4CAF50),
        actionLabel: actionLabel,
        onAction: onAction,
      );

  /// Ошибка (красный крест).
  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.error_rounded,
        iconColor: const Color(0xFFE5484D),
        actionLabel: actionLabel,
        onAction: onAction,
      );

  /// Нейтральное сообщение (иконка в цвете активной темы).
  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.info_rounded,
        iconColor: Theme.of(context).colorScheme.primary,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}
