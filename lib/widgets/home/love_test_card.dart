import 'package:flutter/material.dart';

import '../../dict_strings.dart';

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
    final who =
        partnerName.isEmpty ? trKey('love_partner') : partnerName;

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
                  trKey('love_partner_took').replaceAll('{who}', who),
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
                tooltip: trKey('love_hide'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              trKey('love_card_hint'),
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
              child: Text(trKey('love_take')),
            ),
          ),
        ],
      ),
    );
  }
}
