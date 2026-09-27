import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/avatar_frame.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Рамка поверх аватарки стороны [avatarSize].
///
/// Картинка рамки в [AvatarFrame.scale] раза больше аватарки и выступает за
/// её край; раскладку это не трогает — место занимает ровно аватарка.
/// Анимация приходит с сервера (каталог), пока она грузится или сети нет —
/// неподвижный кадр из сборки, а у рамок новее сборки — скачанный раньше
/// неподвижный кадр из дискового кэша.
class AvatarFrameImage extends StatelessWidget {
  const AvatarFrameImage(
    this.frameKey, {
    super.key,
    required this.avatarSize,
    this.animated = true,
  });

  final String frameKey;
  final double avatarSize;
  final bool animated;

  /// Мельче этого аватарка рисуется в строках и списках, где живая рамка у
  /// каждой строки только мельтешит и ест память на декодирование кадров.
  static const double _minAnimated = 32;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final side = avatarSize * AvatarFrame.scale;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final decode = (side * dpr).round();
        final frame = AvatarFrame.byKey(frameKey);
        final still = !animated ||
            avatarSize < _minAnimated ||
            (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
        final url = frame?.urlFor(side, animated: !still);

        Widget fallback() {
          final asset = AvatarFrame.assetFor(frameKey);
          if (asset != null) {
            return Image.asset(
              asset,
              width: side,
              height: side,
              cacheWidth: decode,
              gaplessPlayback: true,
            );
          }
          final stillUrl = frame?.stillUrl;
          if (stillUrl == null || stillUrl == url) {
            return SizedBox.square(dimension: side);
          }
          return CachedNetworkImage(
            cacheManager: OfflineImageCacheManager.instance,
            imageUrl: stillUrl,
            width: side,
            height: side,
            memCacheWidth: decode,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) => SizedBox.square(dimension: side),
            errorWidget: (_, _, _) => SizedBox.square(dimension: side),
          );
        }

        final child = url == null
            ? fallback()
            : CachedNetworkImage(
                cacheManager: OfflineImageCacheManager.instance,
                imageUrl: url,
                width: side,
                height: side,
                memCacheWidth: decode,
                memCacheHeight: decode,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => fallback(),
                errorWidget: (_, _, _) => fallback(),
              );

        return IgnorePointer(
          child: SizedBox.square(
            dimension: avatarSize,
            child: OverflowBox(maxWidth: side, maxHeight: side, child: child),
          ),
        );
      },
    );
  }
}
