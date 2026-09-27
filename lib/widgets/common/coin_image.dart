import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Монета TY, живая везде: два объёмных оборота на месте и блик. Анимация
/// приезжает серверным каталогом (запись `art_coin`); пока её нет или нет
/// сети, стоит неподвижный кадр из сборки. [animated] = false — только кадр.
///
/// [side] — размер всей картинки, как у прежнего `ScaledAsset`: поля у
/// файла те же, раскладка вокруг не меняется.
class CoinImage extends StatelessWidget {
  const CoinImage({super.key, required this.side, this.animated = true});

  static const String asset = 'assets/images/icons/coin.webp';

  final double side;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (side * dpr).round();
    // fit: без него картинка не растёт больше своего файла, и на крупном
    // показе монета оставалась маленькой.
    final still = Image.asset(
      asset,
      width: side,
      height: side,
      cacheWidth: decode,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
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
          fit: BoxFit.contain,
          fadeInDuration: Duration.zero,
          placeholder: (_, _) => still,
          errorWidget: (_, _, _) => still,
        );
      },
    );
  }
}
