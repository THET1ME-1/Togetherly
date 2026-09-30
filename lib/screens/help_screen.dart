import 'package:flutter/material.dart';

import '../dict_strings.dart';
import '../models/help_items.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/settings_scaffold.dart';

/// Справка «Как сделать»: поиск, фильтры по темам, два самых частых вопроса
/// крупно и остальные по темам. Ответ открывается листом снизу: путь, шаги и
/// кнопка, которая ведёт прямо на нужный экран. Макет — вариант А
/// (https://claude.ai/artifact/48RQNpqSdabA61pLew7qTS).
class HelpScreen extends StatefulWidget {
  const HelpScreen({
    super.key,
    required this.scheme,
    required this.plusInStore,
    required this.onAction,
    required this.onWriteUs,
  });

  final ColorScheme scheme;

  /// Плюс покупается через магазин (Google Play, iPhone): тогда ни слова о
  /// внешней оплате. См. [helpItems].
  final bool plusInStore;

  /// Куда ведёт «Открыть». Экран справки к этому моменту уже закрыт листом.
  final void Function(HelpAction action) onAction;

  /// «Не помогло, написать нам» — приёмная.
  final VoidCallback onWriteUs;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _query = TextEditingController();
  HelpTopic? _topic;

  late final List<HelpItem> _items =
      helpItems(plusInStore: widget.plusInStore);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _browsing => _query.text.trim().isEmpty && _topic == null;

  List<HelpItem> get _shown => [
        for (final i in _items)
          if ((_topic == null || i.topic == _topic) &&
              helpMatches(i, _query.text))
            i,
      ];

  void _open(HelpItem item) => showHelpAnswer(
        context,
        item: item,
        scheme: widget.scheme,
        onAction: widget.onAction,
        onWriteUs: widget.onWriteUs,
      );

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final shown = _shown;
    final topics = [
      for (final t in HelpTopic.values)
        if (_items.any((i) => i.topic == t)) t,
    ];

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            trKey('help.title'),
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
              color: cs.onSurface,
            ),
          ),
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.of(context).padding.bottom + 32),
          children: [
            _search(cs),
            const SizedBox(height: 12),
            _chips(cs, topics),
            if (_browsing) ...[
              SettingsSection(trKey('help.popular')),
              _popular(cs),
            ],
            if (shown.isEmpty) _nothing(cs),
            for (final t in topics)
              if (shown.any((i) => i.topic == t)) ...[
                SettingsSection(helpTopicLabel(t)),
                SettingsGroup([
                  for (final i in shown.where((i) => i.topic == t))
                    SettingsRow(
                      icon: i.icon,
                      title: i.question,
                      trailing: const SettingsChevron(),
                      onTap: () => _open(i),
                    ),
                ]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _search(ColorScheme cs) {
    return TextField(
      key: const Key('help-search'),
      controller: _query,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      style: AppFonts.onest(size: 16, weight: 500, color: cs.onSurface),
      decoration: InputDecoration(
        hintText: trKey('help.search'),
        hintStyle:
            AppFonts.onest(size: 16, weight: 500, color: cs.onSurfaceVariant),
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
        suffixIcon: _query.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                color: cs.onSurfaceVariant,
                onPressed: () => setState(_query.clear),
              ),
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _chips(ColorScheme cs, List<HelpTopic> topics) {
    Widget pill(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: selected ? cs.primary : cs.surfaceContainerHigh,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  label,
                  style: AppFonts.onest(
                    size: 14,
                    weight: 700,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          pill(trKey('help.all'), _topic == null,
              () => setState(() => _topic = null)),
          for (final t in topics)
            pill(helpTopicLabel(t), _topic == t,
                () => setState(() => _topic = _topic == t ? null : t)),
        ],
      ),
    );
  }

  /// Два самых частых вопроса крупными тональными плитками.
  Widget _popular(ColorScheme cs) {
    final top = helpPopular(_items);
    final colors = [
      (cs.primaryContainer, cs.onPrimaryContainer),
      (cs.tertiaryContainer, cs.onTertiaryContainer),
    ];
    // На 320 точках «Togetherly+» шире плитки целиком и рвался посреди слова,
    // поэтому узким плиткам кегль поменьше. Меряем снаружи: IntrinsicHeight
    // не уживается с LayoutBuilder внутри.
    return LayoutBuilder(
      builder: (_, box) => _popularRow(
          cs, top, colors, box.maxWidth < 340 ? 12.5 : 15),
    );
  }

  Widget _popularRow(ColorScheme cs, List<HelpItem> top,
      List<(Color, Color)> colors, double titleSize) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var n = 0; n < top.length; n++) ...[
            if (n > 0) const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: colors[n].$1,
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(top[n]),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 132),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(top[n].icon, size: 28, color: colors[n].$2),
                          const SizedBox(height: 16),
                          Text(
                            _keepPlus(top[n].question),
                            style: AppFonts.unbounded(
                                size: titleSize,
                                weight: 700,
                                color: colors[n].$2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nothing(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trKey('help.nothing'),
            style: AppFonts.onest(
                size: 15.5, weight: 500, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: widget.onWriteUs,
            style: _tonal(cs),
            child: Text(trKey('help.writeUs')),
          ),
        ],
      ),
    );
  }
}

/// Тональная кнопка. Тема профиля красит все FilledButton в `primary`, и
/// «Написать нам» без явных цветов сливалась с главной кнопкой «Открыть».
ButtonStyle _tonal(ColorScheme cs) => FilledButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      minimumSize: const Size.fromHeight(56),
    );

/// Знак «+» не отрывается от слова: на узком экране «Togetherly+» переносился
/// плюсом на отдельную строку.
String _keepPlus(String s) => s.replaceAll('+', '⁠+');

/// Лист ответа: путь пилюлей, три шага с номерами, «Открыть» и «Написать
/// нам». «Открыть» сперва закрывает лист, потом зовёт [onAction].
Future<void> showHelpAnswer(
  BuildContext context, {
  required HelpItem item,
  required ColorScheme scheme,
  required void Function(HelpAction action) onAction,
  required VoidCallback onWriteUs,
}) {
  final action = item.action;
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(scheme),
      child: SheetScaffold(
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action != null)
              FilledButton.icon(
                key: const Key('help-open'),
                onPressed: () {
                  Navigator.pop(ctx);
                  onAction(action);
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: Text(trKey('help.open')),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
              ),
            if (action != null) const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('help-write-us'),
              onPressed: () {
                Navigator.pop(ctx);
                onWriteUs();
              },
              style: _tonal(scheme),
              child: Text(trKey('help.writeUs')),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.path,
                  style: AppFonts.onest(
                      size: 12.5,
                      weight: 700,
                      color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _keepPlus(item.question),
                style: AppFonts.unbounded(
                    size: 21, weight: 800, color: scheme.onSurface),
              ),
              const SizedBox(height: 16),
              for (var n = 0; n < item.steps.length; n++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${n + 1}',
                          style: AppFonts.unbounded(
                              size: 15,
                              weight: 700,
                              color: scheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            item.steps[n],
                            style: AppFonts.onest(
                                size: 15,
                                height: 1.4,
                                color: scheme.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
