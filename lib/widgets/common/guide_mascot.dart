import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Облачко-гид: анимированный WebP из серверного каталога (вид `art`, ключ
/// `guide_<имя>`). Анимации запекает мастерская значков (`bake_guide.py`),
/// поэтому облачко меняется без новой версии приложения.
///
/// Холст файла с запасом под полёт и предметы вокруг: рисунок облачка
/// занимает около 70% стороны. Пока каталог не загружен или файла нет, место
/// остаётся пустым — раскладка экрана от этого не прыгает.
class GuideMascot extends StatelessWidget {
  const GuideMascot(this.name, {super.key, required this.side});

  /// Имя анимации без приставки: `welcome`, `album`, `girl`, `hint_down`…
  final String name;

  /// Сторона холста на экране, в логических точках.
  final double side;

  @override
  Widget build(BuildContext context) => CatalogArtAnim('guide_$name', side: side);
}

/// Анимация из каталога (вид `art`) по полному ключу. Общая для гида и для
/// облачка-маскота на главной.
class CatalogArtAnim extends StatelessWidget {
  const CatalogArtAnim(this.artKey, {super.key, required this.side, this.fallbackKey});

  final String artKey;
  final double side;

  /// Что показать, пока нужной анимации в каталоге нет (старый каталог без
  /// цвета настроения): облачко обычного цвета лучше пустоты.
  final String? fallbackKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final catalog = CatalogService.instance;
        final art = catalog.giftArt(artKey) ?? (fallbackKey == null ? null : catalog.giftArt(fallbackKey!));
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final decode = (side * dpr).round();
        // Файл выбирается по пикселям экрана, а не по точкам: малый (240)
        // годится только там, где его не придётся растягивать.
        final url = decode > 260 ? (art?.lgUrl ?? art?.smUrl) : (art?.smUrl ?? art?.lgUrl);
        if (url == null) return SizedBox.square(dimension: side);
        return CachedNetworkImage(
          cacheManager: OfflineImageCacheManager.instance,
          // Смена сцены (покой → касание) не должна мигать пустотой, пока
          // новый файл разжимается: до готовности стоит прежний кадр.
          useOldImageOnUrlChange: true,
          imageUrl: url,
          width: side,
          height: side,
          memCacheWidth: decode,
          memCacheHeight: decode,
          fadeInDuration: Duration.zero,
          placeholder: (_, _) => SizedBox.square(dimension: side),
          errorWidget: (_, _, _) => SizedBox.square(dimension: side),
        );
      },
    );
  }
}
