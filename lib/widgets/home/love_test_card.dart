import 'package:flutter/material.dart';

import '../../services/locale_service.dart';

/// «Партнёр прошёл „Умение любить“» — карточка на главной.
///
/// Живёт до первого касания: прошли или закрыли, всё равно — больше она не
/// появится. Напоминаний нет намеренно, иначе карточка превращается в баннер,
/// который висит на главной месяцами.
class LoveTestCard extends StatelessWidget {
  const LoveTestCard({
    super.key,
    required this.scheme,
    required this.partnerName,
    required this.onOpen,
    required this.onDismiss,
  });

  final ColorScheme scheme;
  final String partnerName;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.instance.isRussian;
    final who = partnerName.isEmpty ? (ru ? 'Партнёр' : 'Your partner') : partnerName;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 20),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  ru
                      ? '$who прошёл «Умение любить»'
                      : '$who took “How you love”',
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: scheme.onTertiaryContainer.withValues(alpha: .7),
                tooltip: ru ? 'Скрыть' : 'Hide',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              ru
                  ? 'Его фигура откроется, когда ответите сами. Две минуты.'
                  : 'Their shape opens once you answer too. Two minutes.',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onTertiaryContainer.withValues(alpha: .8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton(
              onPressed: onOpen,
              child: Text(ru ? 'Пройти' : 'Take it'),
            ),
          ),
        ],
      ),
    );
  }
}
