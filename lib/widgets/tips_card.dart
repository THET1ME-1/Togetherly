import 'package:flutter/material.dart';

import '../utils/relationship_tips.dart';

/// Карточка советов на сегодня.
///
/// Material 3: тональная поверхность, скругление 28, круглый чип-иконка и
/// кнопка-действие. Первый совет раскрыт, остальные — свёрнутыми строками:
/// три развёрнутых блока превращают заботу в список дел.
///
/// Когда советов нет, карточки нет вовсе — пустое «всё хорошо» занимает экран
/// и обесценивает те подсказки, что появляются по делу.
class TipsCard extends StatefulWidget {
  const TipsCard({
    super.key,
    required this.tips,
    this.onAction,
    this.locked = false,
    this.onUnlock,
    this.lockedTitle = '',
    this.lockedBody = '',
    this.unlockLabel = '',
  });

  final List<RelationshipTip> tips;

  /// Куда ведёт совет: `chat`, `memory`, `gift`, `miss`, `mood`.
  final void Function(String action)? onAction;

  /// Показать заглушку вместо советов — доступ не куплен.
  final bool locked;
  final VoidCallback? onUnlock;
  final String lockedTitle;
  final String lockedBody;
  final String unlockLabel;

  @override
  State<TipsCard> createState() => _TipsCardState();
}

class _TipsCardState extends State<TipsCard> {
  int _open = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.locked) return _lockedCard(cs);
    if (widget.tips.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.tips.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 72,
                endIndent: 16,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            _tipRow(cs, widget.tips[i], i),
          ],
        ],
      ),
    );
  }

  Widget _tipRow(ColorScheme cs, RelationshipTip tip, int index) {
    final open = index == _open;

    return InkWell(
      onTap: () => setState(() => _open = open ? -1 : index),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: open ? cs.primaryContainer : cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(tip.action),
                size: 22,
                color: open ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tip.title,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontVariations: const [FontVariation('wght', 600)],
                      color: cs.onSurface,
                    ),
                  ),
                  // Развёрнут только один совет: раскрытие остальных делает
                  // карточку простынёй.
                  AnimatedSize(
                    alignment: Alignment.topLeft,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: open
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              tip.body,
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 13,
                                height: 1.35,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  if (open && tip.action != null && widget.onAction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FilledButton.tonal(
                        onPressed: () => widget.onAction!(tip.action!),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                        ),
                        child: Text(
                          _labelFor(tip.action!),
                          style: const TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockedCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lightbulb_rounded,
                size: 22, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.lockedTitle,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.lockedBody,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (widget.onUnlock != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.onUnlock,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: Text(
                      widget.unlockLabel,
                      style: const TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String? action) => switch (action) {
        'chat' => Icons.chat_bubble_rounded,
        'memory' => Icons.photo_library_rounded,
        'gift' => Icons.card_giftcard_rounded,
        'miss' => Icons.favorite_rounded,
        'mood' => Icons.mood_rounded,
        _ => Icons.lightbulb_rounded,
      };

  String _labelFor(String action) => switch (action) {
        'chat' => 'Написать',
        'memory' => 'Добавить',
        'gift' => 'Подарки',
        'miss' => 'Отправить',
        'mood' => 'Настроение',
        _ => 'Открыть',
      };
}
