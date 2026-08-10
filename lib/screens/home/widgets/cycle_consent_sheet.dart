import 'package:flutter/material.dart';
import '../../../utils/safe_launch.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/locale_service.dart';
import '../../../theme/fonts.dart';
import '../../../widgets/app_sheet.dart';

/// Согласие на обработку данных цикла — перед первой отметкой.
///
/// Даты цикла и самочувствия относятся к особой категории персональных
/// данных: закон Республики Молдова № 133/2011 и GDPR требуют на них
/// отдельного явного согласия. Общая галочка «принимаю политику» при
/// регистрации это требование не закрывает, поэтому спрашиваем здесь и один
/// раз — дальше решение живёт в настройках, где его можно отозвать.
///
/// Возвращает `true`, только если человек нажал согласие. Закрытие свайпом
/// или «Не сейчас» — это отказ, и отметка не ставится.
Future<bool?> showCycleConsentSheet(
  BuildContext context, {
  required ColorScheme scheme,
}) {
  final s = LocaleService.current;

  return showAppSheet<bool>(
    context,
    background: scheme.surfaceContainer,
    builder: (sheetContext) => SheetScaffold(
      title: s.cycleConsentTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                s.cycleConsentBody,
                style: AppFonts.onest(
                  size: 14.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => safeLaunchUrl(
                Uri.parse('https://togetherly.day/privacy-policy'),
                mode: LaunchMode.externalApplication,
              ),
              icon: Icon(Icons.open_in_new_rounded,
                  size: 17, color: scheme.onSurfaceVariant),
              label: Text(
                s.privacyPolicyLink,
                style: AppFonts.onest(
                    size: 13.5, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  s.cycleConsentAgree,
                  style: AppFonts.onest(size: 15.5, weight: 600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(
                  s.cycleConsentLater,
                  style: AppFonts.onest(
                      size: 14.5, weight: 600, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
