import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

/// Итог после ролика и покупки — одно правило на всё приложение.
///
/// Жалоба 28.09.2026: «посмотрел рекламу — и никакого итога, не понимаю,
/// подарил или нет». Экран рекламы закрывается не мгновенно, и снекбар,
/// показанный сразу после `show()`, ложился под него; а незасчитанный ролик
/// не говорил ничего вовсе. Поэтому:
///   * до итога ждём [untilAppVisible];
///   * незасчитанный ролик — [showAdNotEarned], а не молчание;
///   * то, что человек ПОЛУЧИЛ (подарок ушёл, значок твой), — листом
///     [showObtained] с самой вещью крупно.

/// Ждёт, пока приложение снова на экране и отрисовало кадр (после рекламы).
Future<void> untilAppVisible() async {
  final binding = WidgetsBinding.instance;
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    final back = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!back.isCompleted) back.complete();
      },
    );
    await back.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    listener.dispose();
  }
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await binding.endOfFrame;
}

/// Ролик не засчитан: награды не будет, так и говорим.
Future<void> showAdNotEarned(BuildContext context) async {
  await untilAppVisible();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(trKey('adNotEarned')), behavior: SnackBarBehavior.floating),
  );
}

/// Короткий итог после ролика, когда экран уже снова виден.
Future<void> showAfterAd(BuildContext context, String text) async {
  await untilAppVisible();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

/// Лист «что получил»: вещь крупно, заголовок, пояснение и «Готово».
Future<void> showObtained(
  BuildContext context, {
  required Widget art,
  required String title,
  String? subtitle,
  String? footnote,
  ColorScheme? scheme,
}) {
  final cs = scheme ?? Theme.of(context).colorScheme;
  return showAppSheet<void>(
    context,
    builder: (ctx) => SheetScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            art,
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Onest', fontSize: 14.5, height: 1.4, color: cs.onSurfaceVariant),
              ),
            ],
            if (footnote != null) ...[
              const SizedBox(height: 4),
              Text(
                footnote,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Onest', fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: Text(trKey('giftSentOk')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
