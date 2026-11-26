import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/xmas_text.dart';
import '../../models/xmas_tree.dart';
import '../../services/catalog_service.dart';
import '../../services/xmas_tree_service.dart';
import '../../theme/profile_theme.dart';
import 'home_half_tile.dart';
import 'tree_stage.dart';

/// Плитка ёлки на главной (декабрь): правая половина блока маскота. Крупно —
/// сколько игрушек, у пустой — круглая «+», после новой игрушки партнёра —
/// «Дима +N». Касание открывает экран наряжения.
class TreeHomeTile extends StatefulWidget {
  const TreeHomeTile({
    super.key,
    required this.groupId,
    required this.season,
    required this.myUid,
    required this.partnerName,
    required this.onOpen,
    this.height = 116,
  });

  final String groupId;
  final int season;
  final String myUid;
  final String partnerName;
  final VoidCallback onOpen;
  final double height;

  @override
  State<TreeHomeTile> createState() => _TreeHomeTileState();
}

class _TreeHomeTileState extends State<TreeHomeTile> {

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(TreeHomeTile old) {
    super.didUpdateWidget(old);
    if (old.groupId != widget.groupId || old.season != widget.season) _bind();
  }

  void _bind() {
    unawaited(CatalogService.instance.ensureXmasArt());
    unawaited(XmasTreeService.instance.bind(widget.groupId, widget.season, widget.myUid));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = XmasTreeService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final bound = svc.groupId == widget.groupId && svc.season == widget.season;
        final s = bound ? svc.state : null;
        final toys = s?.toys ?? const <TreeToy>[];
        final n = toys.length;
        final fresh = bound ? svc.newFromPartner : 0;
        final empty = s != null && n == 0;
        final fg = cs.onTertiaryContainer;
        // подписи слева, на 62% ширины: справа стоит ёлка
        Widget left(Widget child) => LayoutBuilder(
              builder: (context, c) => ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth * 0.62), child: child),
            );
        return Semantics(
          button: true,
          label: xt('xt.tree'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: cs.tertiaryContainer)),
                Positioned(
                  right: -20,
                  bottom: -4,
                  child: IgnorePointer(
                    child: TreeStage(side: 100, tree: s?.tree ?? const PairTree(), toys: toys, still: true),
                  ),
                ),
                HomeHalfTile(
                  color: Colors.transparent,
                  height: widget.height,
                  onTap: widget.onOpen,
                  top: left(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(xt('xt.tree'), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                      if (empty)
                        Text(xt('xt.empty'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75)))
                      else if (fresh > 0)
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text('${widget.partnerName} +$fresh', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8))),
                            ),
                          ],
                        ),
                    ],
                  )),
                  bottom: empty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                            child: Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s != null) ...[
                              Text('$n', style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 24, fontWeight: FontWeight.w800, height: 1, color: fg)),
                              Text(xtWord(n, 'xt.toys'), style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
