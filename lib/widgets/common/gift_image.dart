import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Рисунок подарка: живая анимация из серверного каталога, а пока её нет
/// (каталог не пришёл, нет сети, старая запись) — неподвижный кадр из сборки
/// `assets/images/gifts/<ключ>.webp`.
///
/// Холст картинки 176 с рисунком 144 в центре — запас под пар, искры и
/// полёт. Чтобы сам рисунок занимал [side], картинка рисуется на 176/144
/// крупнее и выходит за свои границы, раскладку это не трогает.
class GiftImage extends StatelessWidget {
  const GiftImage(this.giftKey, {super.key, required this.side, this.animated = true});

  final String giftKey;

  /// Сторона рисунка на экране, в логических точках.
  final double side;
  final bool animated;

  static const double _canvas = 176 / 144;

  @override
  Widget build(BuildContext context) {
    final full = side * _canvas;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (full * dpr).round();
    final still = Image.asset(
      'assets/images/gifts/$giftKey.webp',
      width: full,
      height: full,
      cacheWidth: decode,
      errorBuilder: (_, _, _) => SizedBox.square(dimension: full),
    );
    return SizedBox.square(
      dimension: side,
      child: OverflowBox(
        maxWidth: full,
        maxHeight: full,
        child: ListenableBuilder(
          listenable: CatalogService.instance,
          builder: (context, _) {
            final url = CatalogService.instance.giftArt(giftKey)?.urlFor(side, animated: animated);
            if (url == null) return still;
            return CachedNetworkImage(
              cacheManager: OfflineImageCacheManager.instance,
              imageUrl: url,
              width: full,
              height: full,
              memCacheWidth: decode,
              memCacheHeight: decode,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => still,
              errorWidget: (_, _, _) => still,
            );
          },
        ),
      ),
    );
  }
}
