import 'package:flutter/material.dart';

import '../../l10n/xmas_text.dart';
import '../../models/xmas_tree.dart';
import '../../services/catalog_service.dart';
import '../../services/locale_service.dart';
import '../../services/xmas_tree_service.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import 'tree_stage.dart' show XtArt;

/// Что выбрали в листе «Игрушки»: игрушку в руку или поход к сундуку.
sealed class ToyPick {
  const ToyPick();
}

class ToyPickHang extends ToyPick {
  const ToyPickHang(this.toy);
  final String toy;
}

class ToyPickChest extends ToyPick {
  const ToyPickChest();
}

const _cats = ['all', 'balls', 'tu', 'figs', 'tree'];

/// Лист «Игрушки»: «Мои» — что лежит в коробке (со счётом), «Ещё» — чего нет,
/// с ценой или пометкой «из сундука». Звезда, гирлянда и стили — в разделе
/// «Для ёлки». Купленное сразу попадает в «Мои».
Future<ToyPick?> showToyPicker(BuildContext context, {String cat = 'all', void Function(int coins)? onCoins}) => showAppSheet<ToyPick>(
  context,
  expand: true,
  builder: (_) => _ToyPicker(initialCat: cat, onCoins: onCoins),
);

class _ToyPicker extends StatefulWidget {
  const _ToyPicker({required this.initialCat, this.onCoins});
  final String initialCat;
  final void Function(int coins)? onCoins;

  @override
  State<_ToyPicker> createState() => _ToyPickerState();
}

class _ToyPickerState extends State<_ToyPicker> {
  late String _cat = widget.initialCat;
  bool _more = false;
  XtToy? _detail;
  bool _busy = false;
  String? _note;

  XmasTreeService get _svc => XmasTreeService.instance;
  String get _lang => LocaleService.instance.language.code;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([_svc, CatalogService.instance]),
      builder: (context, _) {
        final d = _detail;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: d != null ? _buildDetail(context, cs, d) : _buildList(context, cs),
        );
      },
    );
  }

  Widget _buildList(BuildContext context, ColorScheme cs) {
    final state = _svc.state;
    final owned = state?.owned ?? const <String, int>{};
    final free = _svc.freeToys;
    final all = [
      for (final t in CatalogService.instance.xmasToys)
        if (!t.isStyle) t,
    ];
    final mine = [
      for (final t in all)
        if ((owned[t.key] ?? 0) > 0) t,
    ];
    final more = [
      for (final t in all)
        if ((owned[t.key] ?? 0) == 0) t,
    ];
    final list = [
      for (final t in _more ? more : mine)
        if (_cat == 'all' || t.cat == _cat) t,
    ];
    return SheetScaffold(
      key: const ValueKey('list'),
      title: xt('xt.toys'),
      action: IconButton.filledTonal(
        tooltip: xt('xt.close'),
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(xt('xt.mine', {'n': mine.length}))),
                ButtonSegment(value: true, label: Text(xt('xt.more', {'n': more.length}))),
              ],
              selected: {_more},
              onSelectionChanged: (s) => setState(() => _more = s.first),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in _cats)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(xt('xt.cat.$c')),
                        selected: _cat == c,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _cat = c),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
                children: _cat == 'tree' ? _treeCards(cs, owned) : [for (final t in list) _toyCard(cs, t, free[t.key] ?? 0)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _treeCards(ColorScheme cs, Map<String, int> owned) {
    final tree = _svc.state?.tree ?? const PairTree();
    final styles = [
      for (final k in const ['fir', 'snowy'])
        if (xtStyleOwned(k, owned) != _more) k,
    ];
    return [
      if (!_more) ...[
        _card(
          cs,
          art: null,
          icon: Icons.star_rounded,
          name: xt('xt.star'),
          sub: tree.star ? xt('xt.on') : xt('xt.off'),
          selected: tree.star,
          onTap: () => _svc.setTree(star: !tree.star),
        ),
        _card(
          cs,
          art: null,
          icon: Icons.lightbulb_rounded,
          name: xt('xt.garland'),
          sub: tree.garland ? xt('xt.on') : xt('xt.off'),
          selected: tree.garland,
          onTap: () => _svc.setTree(garland: !tree.garland),
        ),
      ],
      for (final k in styles)
        _card(
          cs,
          art: 'xt_pick_style_$k',
          name: k == 'fir' ? xt('xt.styleFir') : (CatalogService.instance.xmasToy('style_$k')?.name(_lang) ?? k),
          sub: _more ? xt('xt.fromChest') : (tree.kind == k ? xt('xt.styleNow') : xt('xt.styleSet')),
          lock: _more,
          selected: !_more && tree.kind == k,
          onTap: () {
            if (_more) {
              final t = CatalogService.instance.xmasToy('style_$k');
              if (t != null) setState(() => _detail = t);
            } else if (tree.kind != k) {
              _svc.setTree(kind: k);
            }
          },
        ),
    ];
  }

  Widget _toyCard(ColorScheme cs, XtToy t, int free) {
    if (_more) {
      return _card(
        cs,
        art: t.pickArt,
        name: t.name(_lang),
        sub: t.forSale ? null : xt('xt.fromChest'),
        price: t.forSale ? t.price : null,
        onTap: () => setState(() => _detail = t),
      );
    }
    return _card(
      cs,
      art: t.pickArt,
      name: t.name(_lang),
      count: free,
      sub: free == 0 ? xt('xt.allOnTree') : null,
      dim: free == 0,
      onTap: free == 0 ? null : () => Navigator.pop(context, ToyPickHang(t.key)),
    );
  }

  Widget _card(
    ColorScheme cs, {
    required String? art,
    IconData? icon,
    required String name,
    String? sub,
    int? count,
    int? price,
    bool lock = false,
    bool dim = false,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: Column(
                children: [
                  Expanded(
                    child: Opacity(
                      opacity: dim ? 0.45 : 1,
                      child: Center(
                        child: art != null
                            ? XtArt(art, side: 64)
                            : Icon(icon, size: 40, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2, color: cs.onSurface),
                  ),
                  if (sub != null || price != null) ...[
                    const SizedBox(height: 4),
                    if (price != null)
                      _pill(
                        cs,
                        cs.primaryContainer,
                        cs.onPrimaryContainer,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.toll_rounded, size: 13, color: cs.onPrimaryContainer),
                            const SizedBox(width: 3),
                            Text('$price'),
                          ],
                        ),
                      )
                    else if (lock)
                      _pill(
                        cs,
                        cs.tertiaryContainer,
                        cs.onTertiaryContainer,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 12, color: cs.onTertiaryContainer),
                            const SizedBox(width: 3),
                            Flexible(child: Text(sub!, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      )
                    else if (_more)
                      _pill(cs, cs.tertiaryContainer, cs.onTertiaryContainer, Text(sub!, overflow: TextOverflow.ellipsis))
                    else
                      Text(sub!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (count != null && count > 0)
              Positioned(top: 7, right: 7, child: _pill(cs, cs.secondaryContainer, cs.onSecondaryContainer, Text('×$count'))),
          ],
        ),
      ),
    );
  }

  Widget _pill(ColorScheme cs, Color bg, Color fg, Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: DefaultTextStyle.merge(
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      child: child,
    ),
  );

  Widget _buildDetail(BuildContext context, ColorScheme cs, XtToy t) {
    final chest = !t.forSale;
    final about = t.isStyle ? xt('xt.aboutSnowy') : (chest ? xt('xt.aboutChest') : xt('xt.aboutShop'));
    return SheetScaffold(
      key: ValueKey('detail_${t.key}'),
      action: IconButton.filledTonal(
        tooltip: xt('xt.back'),
        onPressed: () => setState(() => _detail = null),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      bottom: Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => setState(() => _detail = null),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(xt('xt.back')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => chest ? Navigator.pop(context, const ToyPickChest()) : _buy(t),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(chest ? xt('xt.toChest') : xt('xt.buy', {'n': t.price})),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            XtArt(t.pickArt, side: 140),
            const SizedBox(height: 10),
            Text(
              t.name(_lang),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              about,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.35, color: cs.onSurfaceVariant),
            ),
            if (_note != null) ...[
              const SizedBox(height: 10),
              Text(
                _note!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _buy(XtToy t) async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final r = await _svc.buy(t.key);
    if (!mounted) return;
    if (r.coins != null) widget.onCoins?.call(r.coins!);
    setState(() {
      _busy = false;
      if (r.error == null) {
        _detail = null;
        _more = false;
      } else {
        _note = r.error == 'insufficient' ? xt('xt.noCoins') : xt('xt.failed');
      }
    });
  }
}

/// Лист повешенной игрушки: кто и когда повесил, «Снять» и «Готово».
Future<bool?> showToyInfo(BuildContext context, {required TreeToy toy, required String who}) {
  final lang = LocaleService.instance.language.code;
  final t = CatalogService.instance.xmasToy(toy.toy);
  final date = toy.created == null ? '' : LocaleService.current.dayLogDate(toy.created!.toLocal());
  return showAppSheet<bool>(
    context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SheetScaffold(
        bottom: Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: Text(xt('xt.takeOff')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: Text(xt('xt.done')),
              ),
            ),
          ],
        ),
        child: Column(
          children: [
            XtArt(t?.pickArt ?? 'xt_pick_${toy.toy}', side: 132),
            const SizedBox(height: 8),
            Text(
              t?.name(lang) ?? toy.toy,
              style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              xt('xt.who', {'name': who, 'date': date}).replaceAll(RegExp(r' · $'), ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    },
  );
}
