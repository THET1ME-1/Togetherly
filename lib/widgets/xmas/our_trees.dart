import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/xmas_text.dart';
import '../../models/user_data.dart';
import '../../models/xmas_tree.dart';
import '../../screens/xmas/xmas_tree_screen.dart';
import '../../services/catalog_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/xmas_tree_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import 'tree_stage.dart';
import 'tree_sway.dart';

/// Строка «Наши ёлки» в профиле, раздел «Отношения»: видна в декабре и потом,
/// когда у пары уже есть хоть одна ёлка.
class OurTreesRow extends StatefulWidget {
  const OurTreesRow({super.key, required this.theme, required this.groupId, required this.partnerName, required this.userData});

  final AppTheme theme;
  final String groupId;
  final String partnerName;
  final UserData userData;

  @override
  State<OurTreesRow> createState() => _OurTreesRowState();
}

class _OurTreesRowState extends State<OurTreesRow> {
  @override
  void initState() {
    super.initState();
    final svc = XmasTreeService.instance;
    // На главной в декабре сервис уже привязан к этой паре — не дёргаем зря.
    if (svc.groupId != widget.groupId) {
      unawaited(svc.bind(widget.groupId, xtLatestSeason(xtNow()), widget.userData.uid));
    }
    unawaited(CatalogService.instance.ensureXmasArt());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: XmasTreeService.instance,
      builder: (context, _) {
        final svc = XmasTreeService.instance;
        final seasons = svc.groupId == widget.groupId ? (svc.state?.seasons ?? const <int>[]) : const <int>[];
        final active = xtActiveSeason(xtNow());
        if (active == null && seasons.isEmpty) return const SizedBox.shrink();
        final latest = active ?? seasons.reduce((a, b) => a > b ? a : b);
        final s = svc.season == latest ? svc.state : null;
        final n = s?.toys.length ?? 0;
        final sub = '${xt('xt.title', {'s': xtSeasonLabel(latest)})} · $n ${xtWord(n, 'xt.toys')}';
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OurTreesScreen(theme: widget.theme, groupId: widget.groupId, partnerName: widget.partnerName, userData: widget.userData),
                settings: const RouteSettings(name: '/our_trees'),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: OverflowBox(
                        maxWidth: 56,
                        maxHeight: 56,
                        alignment: const Alignment(0, -0.2),
                        child: TreeStage(side: 56, tree: s?.tree ?? const PairTree(), toys: s?.toys ?? const [], still: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(xt('xt.ourTrees'), style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// «Наши ёлки»: ёлки пары по годам. Любая открывается тем же экраном
/// наряжения, прошлогодние — с плашкой архива.
class OurTreesScreen extends StatefulWidget {
  const OurTreesScreen({super.key, required this.theme, required this.groupId, required this.partnerName, required this.userData});

  final AppTheme theme;
  final String groupId;
  final String partnerName;
  final UserData userData;

  @override
  State<OurTreesScreen> createState() => _OurTreesScreenState();
}

class _OurTreesScreenState extends State<OurTreesScreen> {
  final Map<int, TreeState> _states = {};

  List<int> get _seasons {
    final svc = XmasTreeService.instance;
    final set = <int>{...?(svc.groupId == widget.groupId ? svc.state?.seasons : null)};
    final a = xtActiveSeason(xtNow());
    if (a != null) set.add(a);
    return set.toList()..sort((x, y) => y.compareTo(x));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    for (final s in _seasons) {
      try {
        final res = await PocketBaseService().pb.send('/api/tree/state', query: {'group': widget.groupId, 'season': '$s'});
        if (!mounted) return;
        setState(() => _states[s] = TreeState.fromJson((res as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ProfileTheme.themeFor(widget.theme);
    final cs = theme.colorScheme;
    final active = xtActiveSeason(xtNow());
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(xt('xt.ourTrees'), style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text(xt('xt.ourTreesHint'), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24),
          children: [
            for (final s in _seasons) ...[
              _card(context, cs, s, s == active),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ColorScheme cs, int season, bool now) {
    final st = _states[season];
    final toys = st?.toys ?? const <TreeToy>[];
    final mine = toys.where((t) => t.author == widget.userData.uid).length;
    final line = '${toys.length} ${xtWord(toys.length, 'xt.toys')} · ${xt('xt.byWhom', {'me': mine, 'name': widget.partnerName, 'him': toys.length - mine})}';
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => XmasTreeScreen(theme: widget.theme, groupId: widget.groupId, season: season, partnerName: widget.partnerName, userData: widget.userData),
            settings: const RouteSettings(name: '/xmas_tree'),
          ));
          unawaited(_load());
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 236,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(22)),
                child: XtSway(
                  builder: (context, yaw) =>
                      TreeStage(side: 230, tree: st?.tree ?? const PairTree(), toys: toys, still: true, yaw: yaw),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(xtSeasonLabel(season), style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 19, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(line, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: now ? cs.primary : cs.secondaryContainer, borderRadius: BorderRadius.circular(99)),
                      child: Text(now ? xt('xt.decoratingNow') : xt('xt.inArchive'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: now ? cs.onPrimary : cs.onSecondaryContainer)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
