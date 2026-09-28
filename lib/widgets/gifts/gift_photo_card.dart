import 'package:flutter/material.dart';

import '../storage_image.dart';
import '../widget_content_view.dart';

/// Снимок, который даритель приложил к подарку («Кадр»).
///
/// Показывается при вручении и потом на полке, рядом с запиской. Касание
/// открывает кадр во весь экран: в карточке он обрезан по высоте.
class GiftPhotoCard extends StatelessWidget {
  const GiftPhotoCard({
    super.key,
    required this.photo,
    required this.scheme,
    this.authorName,
    this.maxHeight = 260,
  });

  /// Ссылка `pb://media/…` или обычный адрес.
  final String photo;
  final ColorScheme scheme;
  final String? authorName;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          openWidgetPhotoView(context, imageUrl: photo, authorName: authorName),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SizedBox(
            width: double.infinity,
            height: maxHeight,
            child: StorageImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  ColoredBox(color: scheme.surfaceContainerHighest),
              errorWidget: (_, _, _) => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
