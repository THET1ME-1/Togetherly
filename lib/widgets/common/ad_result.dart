import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../services/rewarded_ad_service.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import '../memory_save/floating_note.dart';

/// Итог после ролика и покупки — одно правило на всё приложение.
///
/// Жалоба 28.09.2026: «посмотрел рекламу — и никакого итога, не понимаю,
/// подарил или нет». Экран рекламы закрывается не мгновенно, и снекбар,
/// показанный сразу после `show()`, ложился под него; а незасчитанный ролик
/// не говорил ничего вовсе. Поэтому:
///   * ролик, которого нет, — [ensureAdReady] и «реклама не готова», а не
///     «не засчитан»: человек ничего не смотрел;
///   * запрос награды уходит сразу, а итог ждёт [untilAppVisible];
///   * незасчитанный ролик — [showAdNotEarned], а не молчание;
///   * то, что человек ПОЛУЧИЛ (подарок ушёл, значок твой), — листом
///     [showObtained] с самой вещью крупно.

/// Ждёт, пока приложение снова на экране и отрисовало кадр (после рекламы).
/// Состояние ещё не сообщалось (null) — считаем, что экран виден.
Future<void> untilAppVisible() async {
  final binding = WidgetsBinding.instance;
  final state = binding.lifecycleState;
  if (state != null && state != AppLifecycleState.resumed) {
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

/// Ролик загружен или успел загрузиться за [wait]. false — показывать нечего,
/// и это «реклама не готова», а не «не засчитан».
Future<bool> ensureAdReady(RewardedAdService ad, {Duration wait = const Duration(seconds: 6)}) async {
  if (ad.isReady) return true;
  unawaited(ad.load());
  final until = DateTime.now().add(wait);
  while (DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (ad.isReady) return true;
  }
  return false;
}

/// Ролик не засчитан: награды не будет, так и говорим. [overSheet] — экран
/// открыт из нижнего листа: снекбар ушёл бы под него, поэтому плашка в
/// корневом `Overlay`.
Future<void> showAdNotEarned(BuildContext context, {bool overSheet = false}) async {
  await untilAppVisible();
  if (!context.mounted) return;
  showAdNote(context, trKey('adNotEarned'), overSheet: overSheet);
}

/// Короткое сообщение про ролик: снекбар экрана или, поверх листа, плашка.
void showAdNote(BuildContext context, String text, {bool overSheet = false}) {
  if (overSheet) {
    showFloatingNote(context, text, icon: Icons.info_outline_rounded, duration: const Duration(milliseconds: 2600));
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

/// Лист «что получил»: вещь крупно, заголовок, пояснение и «Готово».
/// [scheme] — тема экрана, откуда открыт лист: сам лист живёт выше экрана и
/// иначе взял бы тему приложения.
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
    background: cs.surfaceContainerHigh,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(cs),
      child: SheetScaffold(
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
    ),
  );
}
