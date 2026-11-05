import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Название звания на языке интерфейса.
String hourRankName(int rank) => trKey('hrank_$rank');

/// Часы коротко: «40 мин», «3 ч 20 мин», «130 ч».
String hourRankHours(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  String hh(int v) => trKey('hrankH').replaceAll('{0}', '$v');
  String mm(int v) => trKey('hrankMin').replaceAll('{0}', '$v');
  if (h == 0) return mm(m);
  return h < 10 && m > 0 ? '${hh(h)} ${mm(m)}' : hh(h);
}

/// Эмблема звания из каталога (`rank_<номер>`): анимированный WebP, холст
/// как у значков — 176 точек, рисунок 144 в центре. Закрытое звание рисуется
/// неподвижным и серым.
class RankEmblem extends StatelessWidget {
  const RankEmblem(
    this.rank, {
    super.key,
    required this.side,
    this.locked = false,
  });

  final int rank;
  final double side;
  final bool locked;

  static const double _canvas = 176 / 144;

  // Серый по яркости, чуть светлее и наполовину прозрачный.
  // dart format off
  static const ColorFilter _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0,    30,
    0.2126, 0.7152, 0.0722, 0,    30,
    0.2126, 0.7152, 0.0722, 0,    30,
    0,      0,      0,      0.55, 0,
  ]);
  // dart format on

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final url = CatalogService.instance
            .rankArt(rank)
            ?.urlFor(side, animated: !locked);
        if (url == null) return SizedBox.square(dimension: side);
        final full = side * _canvas;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final decode = (full * dpr).round();
        Widget img = CachedNetworkImage(
          cacheManager: OfflineImageCacheManager.instance,
          imageUrl: url,
          width: full,
          height: full,
          memCacheWidth: decode,
          memCacheHeight: decode,
          fadeInDuration: Duration.zero,
          placeholder: (_, _) => SizedBox.square(dimension: full),
          errorWidget: (_, _, _) => SizedBox.square(dimension: full),
        );
        if (locked) img = ColorFiltered(colorFilter: _grey, child: img);
        return Semantics(
          label: hourRankName(rank),
          image: true,
          child: SizedBox.square(
            dimension: side,
            child: OverflowBox(maxWidth: full, maxHeight: full, child: img),
          ),
        );
      },
    );
  }
}
