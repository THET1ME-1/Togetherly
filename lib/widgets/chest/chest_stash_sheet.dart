import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/gift.dart';
import '../../services/chest_service.dart';
import '../../theme/profile_theme.dart';
import '../../utils/readable_text.dart';
import '../app_sheet.dart';
import '../common/gift_image.dart';
import '../gifts/gift_note_sheet.dart';
import '../memory/add_memory_sheet.dart' show shelfLabelSize, shelfTint;
import '../memory_save/floating_note.dart';

/// Открывает лист «Запас» в цветах [cs]. Лист живёт выше экрана, поэтому
/// тему ему задают явно: на странице сезонного сундука он ночной, как она.
///
/// [selected] — подарок, на котором лист откроется (касание по нему в ленте
/// магазина). Возвращается, когда лист закрыт: сам, после последнего
/// решения, или человеком.
Future<void> showChestStashSheet(
  BuildContext context, {
  required ColorScheme cs,
  required String groupId,
  required List<ChestStashItem> items,
  String? selected,
}) {
  return showAppSheet<void>(
    context,
    background: cs.surfaceContainerHigh,
    builder: (_) => Theme(
      data: ProfileTheme.data(cs),
      child: ChestStashSheet(groupId: groupId, items: items, selected: selected),
    ),
  );
}

/// Лист «Запас»: подарки из сундука, отложенные на потом (TOG-38, макет
/// «Звук, запас и фото из виджета», вариант А, без продажи — её цены ждут
/// владельца).
///
/// Повторы одного подарка — одна плитка со счётчиком, решение уходит за
/// самый старый из них. Лист ничего не навязывает: после решения выбор
/// переходит на соседний подарок, а не просит разобрать его. Разбирать нечего —
/// лист закрывается сам.
class ChestStashSheet extends StatefulWidget {
  const ChestStashSheet({super.key, required this.groupId, required this.items, this.selected});

  final String groupId;
  final List<ChestStashItem> items;
  final String? selected;

  @override
  State<ChestStashSheet> createState() => _ChestStashSheetState();
}

class _ChestStashSheetState extends State<ChestStashSheet> {
  late List<ChestStashItem> _items = [...widget.items];
  String? _selected;
  bool _busy = false;

  /// Кольцо выбора и зазор до плитки, как `outline: 3px; outline-offset: 2px`
  /// макета. Место под кольцо есть и у невыбранной плитки: иначе выбор
  /// сдвигал бы сетку.
  static const double _ring = 3, _gap = 2, _radius = 22;

  List<(String, List<String>)> get _groups => groupChestStash(_items);

  @override
  void initState() {
    super.initState();
    final keys = [for (final g in _groups) g.$1];
    _selected = keys.contains(widget.selected) ? widget.selected : (keys.isEmpty ? null : keys.first);
  }

  Future<void> _decide({required bool give}) async {
    final key = _selected;
    if (key == null || _busy) return;
    final openId = _groups.firstWhere((g) => g.$1 == key).$2.first;
    var note = '';
    if (give) {
      final asked = await showGiftNoteSheet(
        context,
        cs: Theme.of(context).colorScheme,
        giftKey: key,
        title: GiftCatalog.byKey(key)?.title ?? key,
      );
      if (asked == null || !mounted) return;
      note = asked;
    }
    setState(() => _busy = true);
    final ok = give
        ? await ChestService.instance.give(openId, widget.groupId, note: note)
        : await ChestService.instance.keep(openId);
    if (!mounted) return;
    // Снекбар уехал бы под лист: плашка встаёт поверх всего.
    showFloatingNote(
      context,
      trKey(
        !ok
            ? 'chestChoiceFailed'
            : give
            ? 'chestGiven'
            : 'chestKept',
      ),
      icon: ok ? Icons.check_rounded : Icons.info_outline_rounded,
      duration: const Duration(milliseconds: 2600),
    );
    setState(() {
      _busy = false;
      if (!ok) return;
      _items = [for (final i in _items) if (i.openId != openId) i];
      final keys = [for (final g in _groups) g.$1];
      if (!keys.contains(_selected)) _selected = keys.isEmpty ? null : keys.first;
    });
    if (ok && _items.isEmpty) Navigator.of(context).pop();
  }

  /// Высота плитки: кольцо, рисунок и две строки подписи при шрифте телефона.
  double _tileHeight(TextScaler scaler) => (_ring + _gap) * 2 + 8 + 64 + 4 + scaler.scale(12.5) * 1.2 * 2 + 8;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _groups;
    final selected = _selected;
    return SheetScaffold(
      key: const ValueKey('chest-stash-sheet'),
      title: trKey('chestStashSheetTitle').replaceAll('{n}', '${_items.length}'),
      bottom: selected == null ? null : _actions(cs, selected, groups.firstWhere((g) => g.$1 == selected).$2.length),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                trKey('chestStashSheetHint'),
                style: TextStyle(fontFamily: 'Onest', fontSize: 14, height: 1.35, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                const spacing = 8.0;
                final w = (c.maxWidth - spacing * 2) / 3;
                final h = _tileHeight(MediaQuery.textScalerOf(context));
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final (key, ids) in groups)
                      SizedBox(width: w, height: h, child: _tile(cs, key, ids.length, key == selected, w)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ColorScheme cs, String key, int count, bool selected, double width) {
    final title = GiftCatalog.byKey(key)?.title ?? key;
    // На листе цвета `surfaceContainerHigh` контейнер темы бывает почти того
    // же цвета: у рисованных тем он — чуть тонированный фон.
    final bg = shelfTint(cs.primaryContainer, toward: cs.primary, on: cs.surfaceContainerHigh);
    final ink = readableTextOn(bg);
    final inner = width - (_ring + _gap) * 2 - 12;
    final size = shelfLabelSize(title, maxWidth: inner, scaler: MediaQuery.textScalerOf(context));
    return Semantics(
      button: true,
      selected: selected,
      label: count > 1 ? '$title, ×$count' : title,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              key: ValueKey('stash-tile-$key'),
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(_gap),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius + _ring + _gap),
                border: Border.all(color: selected ? cs.primary : Colors.transparent, width: _ring),
              ),
              child: Material(
                color: bg,
                borderRadius: BorderRadius.circular(_radius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _selected = key),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                    child: Column(
                      children: [
                        GiftImage(key, side: 64),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: size,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(99)),
                child: Text(
                  '×$count',
                  style: TextStyle(fontFamily: 'Onest', fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Выбранный подарок и что с ним сделать. Прижат к низу листа: сетка над
  /// ним прокручивается, кнопки всегда под пальцем.
  Widget _actions(ColorScheme cs, String key, int count) {
    final title = GiftCatalog.byKey(key)?.title ?? key;
    // Тональная кнопка не должна растворяться в плашке: у рисованных тем
    // контейнер почти совпадает с ней цветом.
    final keepBg = shelfTint(cs.primaryContainer, toward: cs.primary, on: cs.surfaceContainer);
    ButtonStyle style(Color bg, Color fg) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: bg.withValues(alpha: 0.6),
      disabledForegroundColor: fg,
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w700),
    );
    return Container(
      key: const ValueKey('stash-actions'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(28)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GiftImage(key, side: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 17,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    if (count > 1) ...[
                      const SizedBox(height: 3),
                      Text(
                        trKey('chestStashHave').replaceAll('{n}', '$count'),
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : () => _decide(give: true),
            style: style(cs.primary, cs.onPrimary),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.redeem_rounded, size: 20),
                const SizedBox(width: 8),
                Flexible(child: Text(trKey('chestGive'), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : () => _decide(give: false),
            style: style(keepBg, readableTextOn(keepBg)),
            child: Text(trKey('chestKeep'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
