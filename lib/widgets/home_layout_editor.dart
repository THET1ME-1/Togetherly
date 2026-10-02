import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dict_strings.dart' show trKey;
import '../models/home_layout.dart';
import '../screens/plus_screen.dart';
import '../services/home_layout_service.dart';
import '../services/locale_service.dart';
import '../services/plus_service.dart';
import '../theme/profile_theme.dart';
import 'app_sheet.dart';
import 'settings_scaffold.dart';

/// Раскладка главной с Togetherly+: три входа к одной модели [HomeLayout].
///
///   * [HomeLayoutSettingsSection] — секция «Главный экран» в настройках:
///     тумблеры вкладок и блоков и строка «Порядок блоков»;
///   * [showHomeLayoutSheet] — лист со всем сразу: вкладки, блоки с ручкой для
///     перетаскивания и «Вернуть как было». Открывается только из настроек:
///     кнопку на главной владелец убрал (02.10.2026);
///   * долгое нажатие на блок главной поднимает его для перетаскивания
///     (`_buildHomeBlocks` в `home_screen.dart`), без Плюса открывает
///     [showHomeLayoutPlusPitch].
///
/// Без Плюса всё видно, но тумблеры выключены, а первой строкой стоит вход в
/// Togetherly+. Там, где Плюса не существует ([PlusService.visible] false и
/// не куплен), секции нет вовсе.

String homeBlockName(HomeBlock b) => trKey(switch (b) {
      HomeBlock.chest => 'homeBlockChest',
      HomeBlock.mascot => 'homeBlockMascot',
      HomeBlock.map => 'homeBlockMap',
      HomeBlock.tasks => 'homeBlockTasks',
      HomeBlock.wishes => 'homeBlockWishes',
      HomeBlock.lane => 'homeBlockLane',
    });

IconData homeBlockIcon(HomeBlock b) => switch (b) {
      HomeBlock.chest => Icons.redeem_rounded,
      HomeBlock.mascot => Icons.pets_rounded,
      HomeBlock.map => Icons.map_rounded,
      HomeBlock.tasks => Icons.task_alt_rounded,
      HomeBlock.wishes => Icons.favorite_border_rounded,
      HomeBlock.lane => Icons.photo_library_rounded,
    };

String homeTabName(HomeTab t) => switch (t) {
      HomeTab.widgets => LocaleService.current.widgets,
      HomeTab.watch => LocaleService.current.watchTogether,
    };

IconData homeTabIcon(HomeTab t) => switch (t) {
      HomeTab.widgets => Icons.widgets_rounded,
      HomeTab.watch => Icons.live_tv_rounded,
    };

/// Можно ли вообще показывать раскладку на этой платформе.
bool get homeLayoutAvailable =>
    PlusService.instance.active || PlusService.instance.visible;

Future<void> _openPlus(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: cs)),
  );
}

final Listenable _layoutAndPlus = Listenable.merge([
  HomeLayoutService.instance,
  PlusService.instance,
]);

/// Секция «Главный экран» в настройках.
class HomeLayoutSettingsSection extends StatelessWidget {
  const HomeLayoutSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    HomeLayoutService.instance.ensureLoaded();
    return ListenableBuilder(
      listenable: _layoutAndPlus,
      builder: (context, _) {
        if (!homeLayoutAvailable) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final plus = PlusService.instance.active;
        final svc = HomeLayoutService.instance;
        final layout = svc.saved;
        Widget toggle(bool value, ValueChanged<bool> onChanged) => Switch(
              value: value,
              onChanged: plus ? onChanged : null,
            );
        return SettingsCollapsible(
          prefsKey: 'home_layout',
          title: trKey('homeLayoutTitle'),
          icon: Icons.dashboard_customize_rounded,
          children: [
            if (!plus)
              SettingsRow(
                icon: Icons.workspace_premium_rounded,
                title: trKey('homeLayoutPlusOpen'),
                subtitle: trKey('homeLayoutPlusLock'),
                iconBg: scheme.primary,
                iconFg: scheme.onPrimary,
                trailing: const SettingsChevron(),
                onTap: () => _openPlus(context),
              ),
            for (final t in HomeTab.values)
              SettingsRow(
                icon: homeTabIcon(t),
                title: homeTabName(t),
                subtitle: trKey('homeLayoutTabs'),
                trailing: toggle(
                  layout.showsTab(t),
                  (v) => svc.update(layout.withTab(t, shown: v)),
                ),
                onTap: plus
                    ? () => svc.update(
                        layout.withTab(t, shown: !layout.showsTab(t)))
                    : null,
              ),
            for (final b in layout.order)
              SettingsRow(
                icon: homeBlockIcon(b),
                title: homeBlockName(b),
                trailing: toggle(
                  layout.showsBlock(b),
                  (v) => svc.update(layout.withBlock(b, shown: v)),
                ),
                onTap: plus
                    ? () => svc.update(
                        layout.withBlock(b, shown: !layout.showsBlock(b)))
                    : null,
              ),
            SettingsRow(
              icon: Icons.swap_vert_rounded,
              title: trKey('homeLayoutCustomize'),
              subtitle: trKey('homeLayoutHint'),
              trailing: const SettingsChevron(),
              onTap: () => showHomeLayoutSheet(context),
            ),
          ],
        );
      },
    );
  }
}

/// Лист со всей раскладкой: вкладки, блоки с перетаскиванием, сброс.
Future<void> showHomeLayoutSheet(BuildContext context) {
  if (!homeLayoutAvailable) return Future.value();
  final cs = Theme.of(context).colorScheme;
  HomeLayoutService.instance.ensureLoaded();
  return showAppSheet<void>(
    context,
    expand: true,
    background: cs.surface,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(cs),
      child: SheetScaffold(
        title: trKey('homeLayoutTitle'),
        child: const _HomeLayoutEditor(),
      ),
    ),
  );
}

class _HomeLayoutEditor extends StatelessWidget {
  const _HomeLayoutEditor();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _layoutAndPlus,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final plus = PlusService.instance.active;
        final svc = HomeLayoutService.instance;
        final layout = svc.saved;
        const outer = Radius.circular(SettingsGroup.outerRadius);
        const inner = Radius.circular(SettingsGroup.innerRadius);
        BorderRadius shape(int i, int n) => BorderRadius.vertical(
              top: i == 0 ? outer : inner,
              bottom: i == n - 1 ? outer : inner,
            );

        Widget label(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 10),
              child: Text(
                text.toUpperCase(),
                style: ProfileTheme.sectionLabel(cs),
              ),
            );

        final blocks = layout.order;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (!plus)
              Material(
                color: cs.primaryContainer,
                borderRadius:
                    BorderRadius.circular(SettingsGroup.outerRadius),
                clipBehavior: Clip.antiAlias,
                child: SettingsRow(
                  icon: Icons.workspace_premium_rounded,
                  title: trKey('homeLayoutPlusOpen'),
                  subtitle: trKey('homeLayoutPlusLock'),
                  iconBg: cs.primary,
                  iconFg: cs.onPrimary,
                  trailing: const SettingsChevron(),
                  onTap: () => _openPlus(context),
                ),
              ),
            label(trKey('homeLayoutTabs')),
            for (var i = 0; i < HomeTab.values.length; i++) ...[
              if (i > 0) const SizedBox(height: SettingsGroup.gap),
              Material(
                color: cs.surfaceContainerHigh,
                borderRadius: shape(i, HomeTab.values.length),
                clipBehavior: Clip.antiAlias,
                child: Builder(builder: (context) {
                  final t = HomeTab.values[i];
                  return SettingsRow(
                    icon: homeTabIcon(t),
                    title: homeTabName(t),
                    trailing: Switch(
                      value: layout.showsTab(t),
                      onChanged: plus
                          ? (v) => svc.update(layout.withTab(t, shown: v))
                          : null,
                    ),
                    onTap: plus
                        ? () => svc.update(
                            layout.withTab(t, shown: !layout.showsTab(t)))
                        : null,
                  );
                }),
              ),
            ],
            label(trKey('homeLayoutBlocks')),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(
                trKey('homeLayoutBlocksHint'),
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: blocks.length,
              onReorder: (from, to) {
                if (!plus) return;
                HapticFeedback.selectionClick();
                // ReorderableListView отдаёт [to] до удаления элемента.
                svc.update(layout.moved(from, to > from ? to - 1 : to));
              },
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                child: child,
              ),
              itemBuilder: (context, i) {
                final b = blocks[i];
                final shown = layout.showsBlock(b);
                return Padding(
                  key: ValueKey(b),
                  padding: EdgeInsets.only(
                      top: i > 0 ? SettingsGroup.gap : 0),
                  child: Material(
                    color: cs.surfaceContainerHigh,
                    borderRadius: shape(i, blocks.length),
                    clipBehavior: Clip.antiAlias,
                    child: SettingsRow(
                      icon: homeBlockIcon(b),
                      title: homeBlockName(b),
                      iconBg: shown ? null : cs.surfaceContainerHighest,
                      iconFg: shown ? null : cs.onSurfaceVariant,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: shown,
                            onChanged: plus
                                ? (v) =>
                                    svc.update(layout.withBlock(b, shown: v))
                                : null,
                          ),
                          const SizedBox(width: 4),
                          if (plus)
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: cs.outlineVariant,
                              ),
                            ),
                        ],
                      ),
                      onTap: plus
                          ? () => svc.update(
                              layout.withBlock(b, shown: !shown))
                          : null,
                    ),
                  ),
                );
              },
            ),
            if (plus && !layout.isDefault) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => svc.update(const HomeLayout()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(trKey('homeLayoutReset')),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Долгое нажатие на блок главной без Плюса: блок не поднимается, а лист
/// говорит, что двигать и прятать блоки можно с Togetherly+. С Плюсом то же
/// нажатие поднимает блок, и его перетаскивают пальцем (см. `_buildHomeBlocks`
/// в `home_screen.dart`).
Future<void> showHomeLayoutPlusPitch(BuildContext context) async {
  if (!homeLayoutAvailable || PlusService.instance.active) return;
  HapticFeedback.mediumImpact();
  final cs = Theme.of(context).colorScheme;
  final open = await showAppSheet<bool>(
    context,
    background: cs.surface,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(cs),
      child: SheetScaffold(
        title: trKey('homeLayoutTitle'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(SettingsGroup.outerRadius),
            clipBehavior: Clip.antiAlias,
            child: SettingsRow(
              icon: Icons.workspace_premium_rounded,
              title: trKey('homeLayoutPlusOpen'),
              subtitle: trKey('homeLayoutPlusLock'),
              iconBg: cs.primary,
              iconFg: cs.onPrimary,
              trailing: const SettingsChevron(),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ),
        ),
      ),
    ),
  );
  if (open == true && context.mounted) await _openPlus(context);
}
