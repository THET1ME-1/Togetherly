import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/xmas_tree.dart';
import '../../models/xmas_tree_geometry.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';
import '../common/guide_mascot.dart' show CatalogArtAnim;
import 'tree_draw.dart';

/// Холст ёлки: −8…108 единиц на сторону картинки (116).
const double kXtSpan = 116;

/// Подмена картинок каталога — только для превью в тестах: ключ `art` → файл
/// из мастерской. В приложении всегда null.
ImageProvider Function(String artKey)? xtDebugArt;

/// Картинка ёлки из каталога (игрушка, стиль, слой) квадратом [side].
class XtArt extends StatelessWidget {
  const XtArt(this.artKey, {super.key, required this.side, this.still = false});
  final String artKey;
  final double side;

  /// Неподвижный кадр вместо анимации: для миниатюр, где игрушка в 8–14 точек.
  final bool still;

  @override
  Widget build(BuildContext context) {
    final debug = xtDebugArt;
    if (debug != null) return Image(image: debug(artKey), width: side, height: side, fit: BoxFit.contain);
    if (still) {
      final url = CatalogService.instance.giftArt(artKey)?.stillUrl;
      if (url == null) return SizedBox.square(dimension: side);
      return Image(
        image: CachedNetworkImageProvider(url, cacheManager: OfflineImageCacheManager.instance),
        width: side,
        height: side,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => SizedBox.square(dimension: side),
      );
    }
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
    this.still = false,
    this.yaw = kXtYaw,
  });

  /// Миниатюра (главная, профиль, архив): игрушки неподвижными кадрами.
  final bool still;

  /// Поворот ёлки вокруг оси: качание (`XtSway`) или обычный.
  final double yaw;

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
      final h = xtHangPoint(kind, a, yaw: yaw);
      if (h.visible < -0.05) continue;
      (byTier[h.tier] ??= []).add((t, h));
    }
    // на ярусе верхние игрушки раньше, нижние висят поверх
    for (final l in byTier.values) {
      l.sort((a, b) => a.$2.screen.dy.compareTo(b.$2.screen.dy));
    }
    Widget layer(String part) => _Layer(kind, part, tree.garland, yaw);

    final tiers = xtTiers(kind).length;
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) => SizedBox.square(
        dimension: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            layer('base'),
            for (var i = tiers - 1; i >= 0; i--) ...[
              layer('t$i'),
              for (final (t, h) in byTier[i] ?? const <(TreeToy, XtHang)>[])
                _toy(f, t.toy, h.screen, h.scale, key: ValueKey(t.id)),
            ],
            if (tree.star) layer('star'),
            // Прозрачность — внутри Positioned: Opacity вокруг него ломала
            // постройку сцены («Incorrect use of ParentDataWidget»), и в
            // выпущенной сборке вместо ёлки вставал серый прямоугольник, как
            // только игрушку начинали тянуть (владелец, 27.11.2026).
            if (ghost != null)
              _toy(f, ghost!.toy, ghost!.at, 0.15, opacity: xtCanHang(kind, ghost!.at.dx, ghost!.at.dy) ? 1 : 0.4),
          ],
        ),
      ),
    );
  }

  /// Игрушка на ёлке: картинка без наклейки на холсте −4…104 её единиц,
  /// подвес в (50, 3).
  Widget _toy(XtFrame f, String toyKey, Offset hang, double k, {Key? key, double opacity = 1}) {
    final toy = CatalogService.instance.xmasToy(toyKey);
    final art = toy?.treeArt.isNotEmpty == true ? toy!.treeArt : 'xt3toy_$toyKey';
    final box = f.px(-8 + 108 * k);
    final Widget pic = XtArt(art, side: box, still: still);
    return Positioned(
      key: key,
      left: f.px(hang.dx - 54 * k),
      top: f.px(hang.dy - 7 * k),
      width: box,
      height: box,
      child: IgnorePointer(child: opacity < 1 ? Opacity(opacity: opacity, child: pic) : pic),
    );
  }
}

/// Слой ёлки, нарисованный кодом при повороте [yaw] (`tree_draw.dart`).
class _Layer extends StatelessWidget {
  const _Layer(this.kind, this.part, this.garland, this.yaw);
  final String kind, part;
  final bool garland;
  final double yaw;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _LayerPainter(kind, part, garland, yaw)),
      ),
    );
  }
}

class _LayerPainter extends CustomPainter {
  _LayerPainter(this.kind, this.part, this.garland, this.yaw);
  final String kind, part;
  final bool garland;
  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    final pic = xtTreePictures(kind, yaw, garland: garland).layers[part];
    if (pic == null) return;
    canvas.save();
    canvas.scale(size.width / kXtSpan);
    canvas.translate(8, 8);
    canvas.drawPicture(pic);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayerPainter old) =>
      old.yaw != yaw || old.kind != kind || old.part != part || old.garland != garland;
}

/// Какая игрушка под пальцем: точка касания попала в тело игрушки (подвес и
/// чуть ниже) на ёлке, повёрнутой на [yaw]. Верхние по рисунку проверяются
/// первыми.
TreeToy? xtToyAt(String kind, List<TreeToy> toys, Offset units, {double yaw = kXtYaw}) {
  TreeToy? best;
  var bd = 1e9;
  for (final t in toys) {
    final a = xtAnchor(kind, t.x, t.y);
    if (a == null) continue;
    final h = xtHangPoint(kind, a, yaw: yaw);
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
