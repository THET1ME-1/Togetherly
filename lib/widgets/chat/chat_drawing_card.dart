import 'package:flutter/material.dart';

import '../storage_image.dart';

/// Рисунок в пузыре чата: снимок холста крупно и его название под ним.
///
/// Пин воспоминания в чате — чип с миниатюрой в 36 точек. Рисунок в таком
/// размере не разглядеть, поэтому у него своя карточка на всю ширину пузыря.
class ChatDrawingCard extends StatelessWidget {
  const ChatDrawingCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.foreground,
    required this.onTap,
  });

  final String imageUrl;
  final String title;

  /// Цвет подписи: берётся у пузыря, чтобы читаться и на своём, и на чужом.
  final Color foreground;
  final VoidCallback onTap;

  static const double _side = 220;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.brush_rounded, size: 40, color: cs.onSurfaceVariant),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: _side,
                height: _side,
                child: imageUrl.isEmpty
                    ? fallback
                    : StorageImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 660,
                        errorWidget: (_, _, _) => fallback,
                      ),
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: SizedBox(
                  width: _side - 8,
                  child: Row(
                    children: [
                      Icon(Icons.brush_rounded, size: 15, color: foreground),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
