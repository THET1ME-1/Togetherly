import 'package:flutter/material.dart';

import '../../theme/fonts.dart';

/// Шапка экранов создания: круглый крестик и пилюля-сводка с точкой цвета
/// темы. Названия экрана нет — и так видно, что открыто; место занимает то,
/// что правда полезно.
///
/// Общая для экрана записи и капсулы времени: у двух экранов одного рода
/// шапка не должна расходиться.
class FormTopBar extends StatelessWidget {
  const FormTopBar({
    super.key,
    required this.scheme,
    required this.dot,
    required this.label,
    required this.onClose,
  });

  final ColorScheme scheme;

  /// Цвет точки — `AppTheme.fillColor`.
  final Color dot;
  final String label;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Row(
        children: [
          Tooltip(
            message: MaterialLocalizations.of(context).closeButtonTooltip,
            child: Material(
              color: cs.surfaceContainerHigh,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onClose,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.close_rounded, size: 22, color: cs.onSurface),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.onest(size: 13.5, weight: 700, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
