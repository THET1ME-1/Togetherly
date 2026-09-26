import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Монета TY. В мелких местах — неподвижный кадр из сборки, там, где монета
/// крупная ([animated]), — живая: подброс, объёмный оборот и блик. Живая
/// приезжает серверным каталогом (запись `art_coin`); пока её нет, стоит кадр.
///
/// [side] — размер всей картинки, как у прежнего `ScaledAsset`: поля у
/// файла те же, раскладка вокруг не меняется.
class CoinImage extends StatelessWidget {
  const CoinImage({super.key, required this.side, this.animated = false});

  static const String asset = 'assets/images/icons/coin.webp';

  final double side;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (side * dpr).round();
    final still = Image.asset(asset, width: side, height: side, cacheWidth: decode, filterQuality: FilterQuality.medium);
    if (!animated) return still;
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final url = CatalogService.instance.giftArt('coin')?.urlFor(side);
        if (url == null) return still;
        return CachedNetworkImage(
          cacheManager: OfflineImageCacheManager.instance,
          imageUrl: url,
          width: side,
          height: side,
          memCacheWidth: decode,
          memCacheHeight: decode,
          fadeInDuration: Duration.zero,
          placeholder: (_, _) => still,
          errorWidget: (_, _, _) => still,
        );
      },
    );
  }
}
