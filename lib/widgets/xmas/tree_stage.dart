import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/xmas_tree.dart';
import '../../models/xmas_tree_geometry.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';
import '../common/guide_mascot.dart' show CatalogArtAnim;

/// Холст ёлки: −8…108 единиц на сторону картинки (116).
const double kXtSpan = 116;

/// Подмена картинок каталога — только для превью в тестах: ключ `art` → файл
/// из мастерской. В приложении всегда null.
ImageProvider Function(String artKey)? xtDebugArt;

/// Картинка ёлки из каталога (игрушка, стиль, слой) квадратом [side].
class XtArt extends StatelessWidget {
  const XtArt(this.artKey, {super.key, required this.side});
  final String artKey;
  final double side;

  @override
  Widget build(BuildContext context) {
    final debug = xtDebugArt;
    if (debug != null) return Image(image: debug(artKey), width: side, height: side, fit: BoxFit.contain);
    return CatalogArtAnim(artKey, side: side);
  }
}

/// Перевод между единицами холста ёлки и точками на экране квадрата [side].
class XtFrame {
  const XtFrame(this.side);
  final double side;

  double px(double u) => (u + 8) / kXtSpan * side;
  Offset toPx(Offset u) => Offset(px(u.dx), px(u.dy));
  Offset toUnits(Offset p) => Offset(p.dx / side * kXtSpan - 8, p.dy / side * kXtSpan - 8);
}

/// Игрушка, которую сейчас тащат: бледная там, где её не повесить.
class XtGhost {
  const XtGhost(this.toy, this.at);
  final String toy;
  final Offset at; // точка подвеса в единицах ёлки
}

/// Ёлка пары: слои из каталога стопкой (основа, ярусы снизу вверх, звезда), а
/// игрушки каждого яруса — между его слоем и верхним, как на рисунке: крючок
/// прячется под лапы яруса выше. Игрушка висит на хвое (`xtAnchor`), поэтому
/// место считается от точки, куда её повесили.
class TreeStage extends StatelessWidget {
  const TreeStage({
    super.key,
    required this.side,
    required this.tree,
    required this.toys,
    this.ghost,
    this.hidden,
  });

  final double side;
  final PairTree tree;
  final List<TreeToy> toys;
  final XtGhost? ghost;

  /// Игрушка, которую сейчас двигают: на месте её не рисуем.
  final String? hidden;

  @override
  Widget build(BuildContext context) {
    final f = XtFrame(side);
    final kind = tree.kind;
    final byTier = <int, List<(TreeToy, XtHang)>>{};
    for (final t in toys) {
      if (t.id == hidden) continue;
      final a = xtAnchor(kind, t.x, t.y);
      if (a == null) continue;
      final h = xtHangPoint(kind, a);
      if (h.visible < -0.05) continue;
      (byTier[h.tier] ??= []).add((t, h));
    }
    // на ярусе верхние игрушки раньше, нижние висят поверх
    for (final l in byTier.values) {
      l.sort((a, b) => a.$2.screen.dy.compareTo(b.$2.screen.dy));
    }
    String layer(String part) {
      final g = (part == 't1' || part == 't2' || part == 't3') ? (tree.garland ? '_g1' : '_g0') : '';
      return 'xt3_${kind}_$part$g';
    }

    final tiers = xtTiers(kind).length;
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) => SizedBox.square(
        dimension: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _Layer(layer('base'), side),
            for (var i = tiers - 1; i >= 0; i--) ...[
              _Layer(layer('t$i'), side),
              for (final (t, h) in byTier[i] ?? const <(TreeToy, XtHang)>[])
                _toy(f, t.toy, h.screen, h.scale, key: ValueKey(t.id)),
            ],
            if (tree.star) _Layer(layer('star'), side),
            if (ghost != null)
              Opacity(
                opacity: xtCanHang(kind, ghost!.at.dx, ghost!.at.dy) ? 1 : 0.4,
                child: _toy(f, ghost!.toy, ghost!.at, 0.15),
              ),
          ],
        ),
      ),
    );
  }

  /// Игрушка на ёлке: картинка без наклейки на холсте −4…104 её единиц,
  /// подвес в (50, 3).
  Widget _toy(XtFrame f, String toyKey, Offset hang, double k, {Key? key}) {
    final toy = CatalogService.instance.xmasToy(toyKey);
    final art = toy?.treeArt.isNotEmpty == true ? toy!.treeArt : 'xt3toy_$toyKey';
    final box = f.px(-8 + 108 * k);
    return Positioned(
      key: key,
      left: f.px(hang.dx - 54 * k),
      top: f.px(hang.dy - 7 * k),
      width: box,
      height: box,
      child: IgnorePointer(child: XtArt(art, side: box)),
    );
  }
}

/// Слой ёлки: неподвижная картинка 1200 точек из каталога.
class _Layer extends StatelessWidget {
  const _Layer(this.artKey, this.side);
  final String artKey;
  final double side;

  @override
  Widget build(BuildContext context) {
    final debug = xtDebugArt;
    if (debug != null) return Positioned.fill(child: Image(image: debug(artKey), fit: BoxFit.contain));
    final art = CatalogService.instance.giftArt(artKey);
    final url = art?.stillUrl ?? art?.lgUrl;
    if (url == null) return const SizedBox.shrink();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (side * dpr).clamp(240, 1200).round();
    return Positioned.fill(
      child: IgnorePointer(
        child: Image(
          image: ResizeImage(CachedNetworkImageProvider(url, cacheManager: OfflineImageCacheManager.instance), width: decode, height: decode),
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Какая игрушка под пальцем: точка касания попала в тело игрушки (подвес и
/// чуть ниже). Верхние по рисунку проверяются первыми.
TreeToy? xtToyAt(String kind, List<TreeToy> toys, Offset units) {
  TreeToy? best;
  var bd = 1e9;
  for (final t in toys) {
    final a = xtAnchor(kind, t.x, t.y);
    if (a == null) continue;
    final h = xtHangPoint(kind, a);
    if (h.visible < -0.05) continue;
    final c = h.screen + Offset(0, 7 * h.scale / 0.15);
    final d = (c - units).distanceSquared;
    if (d < 48 && d < bd) {
      bd = d;
      best = t;
    }
  }
  return best;
}
