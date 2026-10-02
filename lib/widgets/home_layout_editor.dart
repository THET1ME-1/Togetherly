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

/// Раскладка главной с Togetherly+: два входа к одной модели [HomeLayout].
///
///   * [HomeLayoutSettingsSection] — секция «Главный экран» в настройках.
///     Тумблеры вкладок и кнопок ряда под таймером, а ниже блоки главной
///     одним списком: строку зажимают
///     и перетаскивают (или тянут за ручку), тумблер в строке прячет блок.
///     Отдельного листа и кнопок «Выше/Ниже» нет — владелец 02.10.2026:
///     «в настройках тоже можно менять местами и скрывать, не кнопками»;
///   * долгое нажатие на блок главной поднимает его для перетаскивания
///     (`_buildHomeBlocks` в `home_screen.dart`), без Плюса открывает
///     [showHomeLayoutPlusPitch].
///
/// Без Плюса всё видно, но тумблеры выключены, перетаскивания нет, а первой
/// строкой стоит вход в Togetherly+. Там, где Плюса не существует
/// ([PlusService.visible] false и не куплен), секции нет вовсе.

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
      HomeTab.home => LocaleService.current.home,
      HomeTab.widgets => LocaleService.current.widgets,
      HomeTab.watch => LocaleService.current.watchTogether,
      HomeTab.connect => LocaleService.current.connect,
      HomeTab.profile => LocaleService.current.profile,
    };

IconData homeTabIcon(HomeTab t) => switch (t) {
      HomeTab.home => Icons.home_rounded,
      HomeTab.widgets => Icons.widgets_rounded,
      HomeTab.watch => Icons.live_tv_rounded,
      HomeTab.connect => Icons.forum_rounded,
      HomeTab.profile => Icons.person_rounded,
    };

String homeActionName(HomeAction a) => trKey(switch (a) {
      HomeAction.draw => 'homeActionDraw',
      HomeAction.mood => 'homeActionMood',
      HomeAction.wallet => 'homeActionWallet',
      HomeAction.calendar => 'homeActionCalendar',
      HomeAction.post => 'homeActionPost',
    });

IconData homeActionIcon(HomeAction a) => switch (a) {
      HomeAction.draw => Icons.edit_square,
      HomeAction.mood => Icons.sentiment_satisfied_alt_rounded,
      HomeAction.wallet => Icons.payments_rounded,
      HomeAction.calendar => Icons.calendar_month_rounded,
      HomeAction.post => Icons.photo_camera_rounded,
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
        return SettingsCollapsible(
          prefsKey: 'home_layout',
          title: trKey('homeLayoutTitle'),
          icon: Icons.dashboard_customize_rounded,
          body: const _HomeLayoutEditor(),
        );
      },
    );
  }
}

class _HomeLayoutEditor extends StatelessWidget {
  const _HomeLayoutEditor();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _layoutAndPlus,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!plus) ...[
          Material(
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
              onTap: () => _openPlus(context),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _caption(cs, trKey('homeLayoutTabsHint'), top: 0),
        _reorderRows<HomeTab>(
          cs: cs,
          plus: plus,
          items: layout.tabOrder,
          name: homeTabName,
          icon: homeTabIcon,
          canHide: (t) => t.canHide,
          shown: layout.showsTab,
          setShown: (t, v) => svc.update(layout.withTab(t, shown: v)),
          onReorder: (from, to) => svc.update(layout.tabMoved(from, to)),
        ),
        // Кнопки ряда под таймером: только спрятать, порядок задан дугой.
        const SizedBox(height: 16),
        for (var i = 0; i < HomeAction.values.length; i++) ...[
          if (i > 0) const SizedBox(height: SettingsGroup.gap),
          Material(
            color: cs.surfaceContainerHigh,
            borderRadius: shape(i, HomeAction.values.length),
            clipBehavior: Clip.antiAlias,
            child: Builder(builder: (context) {
              final a = HomeAction.values[i];
              return SettingsRow(
                icon: homeActionIcon(a),
                title: homeActionName(a),
                subtitle: trKey('homeLayoutActionsSub'),
                trailing: Switch(
                  value: layout.showsAction(a),
                  onChanged: plus
                      ? (v) => svc.update(layout.withAction(a, shown: v))
                      : null,
                ),
                onTap: plus
                    ? () => svc.update(
                        layout.withAction(a, shown: !layout.showsAction(a)))
                    : null,
              );
            }),
          ),
        ],
        _caption(cs, trKey('homeLayoutBlocksHint')),
        _reorderRows<HomeBlock>(
          cs: cs,
          plus: plus,
          items: layout.order,
          name: homeBlockName,
          icon: homeBlockIcon,
          canHide: (_) => true,
          shown: layout.showsBlock,
          setShown: (b, v) => svc.update(layout.withBlock(b, shown: v)),
          // ReorderableListView отдаёт [to] до удаления элемента.
          onReorder: (from, to) =>
              svc.update(layout.moved(from, to > from ? to - 1 : to)),
        ),
        if (plus && !layout.isDefault) ...[
          const SizedBox(height: 12),
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
  }

  Widget _caption(ColorScheme cs, String text, {double top = 16}) => Padding(
        padding: EdgeInsets.fromLTRB(8, top, 8, 10),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 13,
            height: 1.35,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

  /// Строки, которые переставляют пальцем: строку зажимают и тащат, ручка
  /// справа берёт сразу, без ожидания; тумблер (где прятать можно) прячет.
  /// Список лежит внутри прокрутки настроек, поэтому своей прокрутки нет.
  Widget _reorderRows<T extends Object>({
    required ColorScheme cs,
    required bool plus,
    required List<T> items,
    required String Function(T) name,
    required IconData Function(T) icon,
    required bool Function(T) canHide,
    required bool Function(T) shown,
    required void Function(T, bool) setShown,
    required void Function(int from, int to) onReorder,
  }) {
    const outer = Radius.circular(SettingsGroup.outerRadius);
    const inner = Radius.circular(SettingsGroup.innerRadius);
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorder: (from, to) {
        if (plus) onReorder(from, to);
      },
      proxyDecorator: (child, _, anim) => AnimatedBuilder(
        animation: anim,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.03 * Curves.easeOut.transform(anim.value),
          child: child,
        ),
        child: Material(color: Colors.transparent, child: child),
      ),
      itemBuilder: (context, i) {
        final it = items[i];
        final on = shown(it);
        final hideable = canHide(it);
        final row = Padding(
          padding: EdgeInsets.only(top: i > 0 ? SettingsGroup.gap : 0),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? outer : inner,
              bottom: i == items.length - 1 ? outer : inner,
            ),
            clipBehavior: Clip.antiAlias,
            child: SettingsRow(
              icon: icon(it),
              title: name(it),
              titleColor: on ? null : cs.onSurfaceVariant,
              iconBg: on ? null : cs.surfaceContainerHighest,
              iconFg: on ? null : cs.onSurfaceVariant,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hideable)
                    Switch(
                      value: on,
                      onChanged: plus ? (v) => setShown(it, v) : null,
                    ),
                  if (plus)
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: plus && hideable ? () => setShown(it, !on) : null,
            ),
          ),
        );
        return plus
            ? ReorderableDelayedDragStartListener(
                key: ValueKey(it),
                index: i,
                child: row,
              )
            : KeyedSubtree(key: ValueKey(it), child: row);
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
