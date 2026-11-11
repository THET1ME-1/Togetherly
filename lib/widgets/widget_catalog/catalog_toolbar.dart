import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/widget_catalog_query.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../app_sheet.dart';
import '../common/filter_tag.dart';

/// Поиск, фильтры и порядок над каталогом виджетов.
///
/// Строка поиска того же вида, что в ленте воспоминаний, под ней лента
/// чипов: цена, «На столе» и порядок. Порядок выбирается листом снизу.
class CatalogToolbar extends StatefulWidget {
  const CatalogToolbar({
    super.key,
    required this.theme,
    required this.query,
    required this.onChanged,
    required this.showPlus,
    required this.onScreenCount,
  });

  final AppTheme theme;
  final CatalogQuery query;
  final ValueChanged<CatalogQuery> onChanged;

  /// Показывать ли чип «С Togetherly+»: на iPhone у некупившего платных
  /// карточек нет вовсе (App Store 3.1.1), и делить там нечего.
  final bool showPlus;

  /// Сколько виджетов каталога стоит на столе; 0 — чипа «На столе» нет.
  final int onScreenCount;

  @override
  State<CatalogToolbar> createState() => _CatalogToolbarState();
}

class _CatalogToolbarState extends State<CatalogToolbar> {
  late final TextEditingController _text =
      TextEditingController(text: widget.query.text);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(CatalogToolbar old) {
    super.didUpdateWidget(old);
    // Сброс снаружи («Сбросить» в пустой выдаче) чистит и поле.
    if (widget.query.text != _text.text) {
      _text.value = TextEditingValue(
        text: widget.query.text,
        selection: TextSelection.collapsed(offset: widget.query.text.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(CatalogQuery next) => widget.onChanged(next);

  String _sortLabel(CatalogSort sort) => switch (sort) {
        CatalogSort.sections => trKey('catalog.sortSections'),
        CatalogSort.name => trKey('catalog.sortName'),
        CatalogSort.newest => trKey('catalog.sortNewest'),
      };

  IconData _sortIcon(CatalogSort sort) => switch (sort) {
        CatalogSort.sections => Icons.view_agenda_rounded,
        CatalogSort.name => Icons.sort_by_alpha_rounded,
        // Не new_releases: звезда с восклицательным знаком читалась как
        // предупреждение (эмулятор, 11.11.2026).
        CatalogSort.newest => Icons.auto_awesome_rounded,
      };

  Future<void> _pickSort() async {
    _focus.unfocus();
    final picked = await showAppSheet<CatalogSort>(
      context,
      builder: (sheet) => SheetScaffold(
        title: trKey('catalog.sortTitle'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in CatalogSort.values)
              _SortOption(
                theme: widget.theme,
                label: _sortLabel(sort),
                icon: _sortIcon(sort),
                selected: widget.query.sort == sort,
                onTap: () => Navigator.of(sheet).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _set(widget.query.copyWith(sort: picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final query = widget.query;
    final hasText = _text.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('catalog-search'),
          height: 52,
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 21, color: t.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => _set(query.copyWith(text: value)),
                  onSubmitted: (_) => _focus.unfocus(),
                  onTapOutside: (_) => _focus.unfocus(),
                  style: AppFonts.onest(size: 15, weight: 500, color: t.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: trKey('catalog.search'),
                    hintStyle: AppFonts.onest(size: 15, weight: 500, color: t.textSecondary),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  padding: EdgeInsets.zero,
                  tooltip: trKey('catalog.reset'),
                  onPressed: () {
                    _text.clear();
                    _set(query.copyWith(text: ''));
                  },
                  icon: Icon(Icons.close_rounded, size: 20, color: t.textSecondary),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Чипов пять, строятся все сразу. Порядок стоит первым: в конце ленты
        // на узком экране его не видно, а он меняет всю выдачу.
        SingleChildScrollView(
          key: const ValueKey('catalog-filters'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              FilterTag(
                key: const ValueKey('catalog-sort'),
                theme: t,
                label: _sortLabel(query.sort),
                icon: Icons.swap_vert_rounded,
                trailingIcon: Icons.arrow_drop_down_rounded,
                selected: query.sort != CatalogSort.sections,
                onTap: _pickSort,
              ),
              const SizedBox(width: 6),
              FilterTag(
                theme: t,
                label: trKey('catalog.all'),
                icon: Icons.apps_rounded,
                selected: query.price == CatalogPrice.all && !query.onlyOnScreen,
                onTap: () => _set(query.copyWith(price: CatalogPrice.all, onlyOnScreen: false)),
              ),
              const SizedBox(width: 6),
              FilterTag(
                theme: t,
                label: trKey('catalog.free'),
                icon: Icons.lock_open_rounded,
                selected: query.price == CatalogPrice.free,
                onTap: () => _set(query.copyWith(
                  price: query.price == CatalogPrice.free ? CatalogPrice.all : CatalogPrice.free,
                )),
              ),
              if (widget.showPlus) ...[
                const SizedBox(width: 6),
                FilterTag(
                  theme: t,
                  label: trKey('catalog.plus'),
                  icon: Icons.workspace_premium_rounded,
                  selected: query.price == CatalogPrice.plus,
                  onTap: () => _set(query.copyWith(
                    price: query.price == CatalogPrice.plus ? CatalogPrice.all : CatalogPrice.plus,
                  )),
                ),
              ],
              if (widget.onScreenCount > 0 || query.onlyOnScreen) ...[
                const SizedBox(width: 6),
                FilterTag(
                  theme: t,
                  label: trKey('catalog.onScreen').replaceAll('{n}', '${widget.onScreenCount}'),
                  icon: Icons.smartphone_rounded,
                  selected: query.onlyOnScreen,
                  onTap: () => _set(query.copyWith(onlyOnScreen: !query.onlyOnScreen)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Строка листа порядка: значок, подпись и галочка у выбранного.
class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.theme,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: AppFonts.onest(
                    size: 16,
                    weight: selected ? 700 : 500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 22, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
