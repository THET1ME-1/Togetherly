import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/profile_icon.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Картинка значка профиля по ключу — из серверного каталога.
///
/// Файлы — анимированный WebP (или неподвижный PNG при [animated] = false);
/// скачанное лежит в дисковом кэше и дальше показывается без сети. Пока
/// каталог не загружен или значка в нём нет, место остаётся пустым: у старого
/// или снятого значка лучше пустота, чем чужая картинка.
///
/// Холст файла 176 с рисунком 144 в центре — запас под пузырьки и полёт. Чтобы
/// сам рисунок занимал [side], картинка рисуется на 176/144 крупнее и выходит
/// за свои границы, раскладку это не трогает.
class BadgeImage extends StatelessWidget {
  const BadgeImage(this.badgeId, {super.key, required this.side, this.animated = true});

  final String? badgeId;

  /// Сторона рисунка на экране, в логических точках.
  final double side;
  final bool animated;

  static const double _canvas = 176 / 144;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final url = ProfileIcon.byId(badgeId)?.urlFor(side, animated: animated);
        if (url == null) return SizedBox.square(dimension: side);
        final full = side * _canvas;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final decode = (full * dpr).round();
        return SizedBox.square(
          dimension: side,
          child: OverflowBox(
            maxWidth: full,
            maxHeight: full,
            child: CachedNetworkImage(
              cacheManager: OfflineImageCacheManager.instance,
              imageUrl: url,
              width: full,
              height: full,
              memCacheWidth: decode,
              memCacheHeight: decode,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => SizedBox.square(dimension: full),
              errorWidget: (_, _, _) => SizedBox.square(dimension: full),
            ),
          ),
        );
      },
    );
  }
}
