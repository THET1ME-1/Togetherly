import 'package:flutter/material.dart';

import '../../theme/fonts.dart';

import '../../services/locale_service.dart';

/// Единый стиль для всех меню приложения: диалоги, подтверждения и снэкбары.
///
/// Форма/скругления/цвета наследуются от глобальной темы (`dialogTheme`,
/// `snackBarTheme` в [main]), а акцент по умолчанию берётся из активной темы
/// через `Theme.of(context).colorScheme.primary`. Поэтому все меню выглядят
/// одинаково и автоматически перекрашиваются при смене темы.
abstract final class AppDialog {
  /// Диалог-подтверждение с заголовком, текстом и двумя кнопками.
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
    // M3: заголовок Unbounded, крупные скругления, кнопки-таблетки. Деструктивное
    // действие — тональная кнопка на errorContainer, а не красный текст: так
    // видно, что оно опасное, но кнопка остаётся кнопкой.
    final confirmBg = destructive ? cs.errorContainer : cs.primary;
    final confirmFg = destructive ? cs.onErrorContainer : cs.onPrimary;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: icon != null
            ? Icon(icon, color: destructive ? cs.error : cs.primary, size: 30)
            : null,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: title != null
            ? Text(
                title,
                style: AppFonts.unbounded(
                  size: 21,
                  weight: 700,
                  letterSpacing: -0.4,
                  color: cs.onSurface,
                ),
              )
            : null,
        content: Text(
          message,
          style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              shape: const StadiumBorder(),
              foregroundColor: cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
            child: Text(cancelLabel ?? s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: confirmBg,
              foregroundColor: confirmFg,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            ),
            child: Text(
              confirmLabel ?? s.confirm,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Информационный диалог с одной кнопкой «ОК».
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    String? buttonLabel,
    IconData? icon,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final s = LocaleService.current;
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          icon: icon != null ? Icon(icon, color: accent, size: 30) : null,
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          title: Text(
            title,
            style: AppFonts.unbounded(
              size: 21,
              weight: 700,
              letterSpacing: -0.4,
              color: cs.onSurface,
            ),
          ),
          content: Text(
            message,
            style:
                TextStyle(fontSize: 15, height: 1.4, color: cs.onSurfaceVariant),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              ),
              child: Text(
                buttonLabel ?? s.ok,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
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
