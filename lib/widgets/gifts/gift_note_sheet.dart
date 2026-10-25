import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../app_sheet.dart';
import '../common/gift_image.dart';

const Cubic _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

/// Записка внутрь подарка: из магазина и из сундука (просьба из приёмной,
/// обращение 244, 13.10.2026). null — человек передумал дарить, пустая
/// строка — дарит без записки.
///
/// Тему лист берёт параметром: он живёт выше экрана, и `Theme.of` под ним
/// отдал бы тему приложения, а не экрана, откуда дарят.
Future<String?> showGiftNoteSheet(
  BuildContext context, {
  required ColorScheme cs,
  required String giftKey,
  required String title,
}) {
  final s = LocaleService.current;
  final ctrl = TextEditingController();
  return showModalSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: _emphasizedDecelerate,
      builder: (ctx, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - v) * 40), child: child),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(8),
                    child: GiftImage(giftKey, side: 36),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        letterSpacing: -0.3,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                // Длину письма не ограничиваем: счётчик на 500 символов
                // обрывал текст на полуслове, а хранится записка целиком.
                // Поле растёт до десяти строк, дальше прокручивается внутри.
                keyboardType: TextInputType.multiline,
                maxLines: 10,
                minLines: 3,
                autofocus: true,
                style: TextStyle(color: cs.onSurface, fontFamily: 'Onest'),
                decoration: InputDecoration(
                  hintText: s.giftNoteHint,
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(''),
                      child: Text(s.giftNoteSkip),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                      child: Text(s.giftNoteSend),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
