import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ui_prefs.dart';
import '../theme/motion.dart';
import '../theme/profile_theme.dart';

/// Каркас экрана настроек.
///
/// Заголовок секции → группа блоков → блок с круглой иконкой-чипом, крупным
/// заголовком и подписью. Каждый пункт лежит своим блоком, между ними зазор;
/// внешние углы группы скруглены сильнее внутренних.
///
/// До этого настройки жили внутри профиля и собирались из трёх разных наборов
/// плиток: где-то плоская карточка, где-то сворачивающийся блок, где-то просто
/// ListTile. Отсюда мешанина. Новый пункт добавляется как ещё один
/// [SettingsRow] в нужную [SettingsGroup] — вид остаётся единым.
///
/// ```dart
/// ListView(
///   padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
///   children: [
///     const SettingsSection('Оформление'),
///     SettingsGroup([
///       SettingsRow(
///         icon: Icons.palette_rounded,
///         title: 'Тема',
///         subtitle: 'Тёмная',
///         trailing: const Icon(Icons.chevron_right_rounded),
///         onTap: _pickTheme,
///       ),
///     ]),
///   ],
/// )
/// ```

/// Заголовок секции — крупный, шрифтом заголовков.
class SettingsSection extends StatelessWidget {
  final String title;

  /// Значок секции — тот же приём, что у `_m3Group` в профиле: кегль 18, без
  /// подложки, цвет идёт за надписью. Подложка-чип есть только у строк и
  /// плиток, у заголовков её не заводить.
  final IconData? icon;

  /// Цвет заголовка. По умолчанию — `primary`; для «опасных» секций передавать
  /// `Theme.of(context).colorScheme.error`.
  final Color? color;

  const SettingsSection(this.title, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(
      title.toUpperCase(),
      style: ProfileTheme.sectionLabel(scheme, color: color),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
      child: icon == null
          ? label
          : Row(
              children: [
                Icon(icon, size: 18, color: color ?? scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: label),
              ],
            ),
    );
  }
}

/// Секция настроек, которая сворачивается по тапу на заголовок.
///
/// Раньше настройки были одним свитком на десять экранов прокрутки: чтобы
/// дойти до «Аккаунта», приходилось пролистывать оформление, уведомления, цикл
/// и данные. Сворачивание тут ровно то же, что у секций профиля, и решение
/// человека так же переживает выход с экрана — лежит в
/// [UiPrefs.collapsedSections] под ключом `settings:<prefsKey>`.
class SettingsCollapsible extends StatefulWidget {
  const SettingsCollapsible({
    super.key,
    required this.prefsKey,
    required this.title,
    required this.children,
    this.icon,
    this.color,
  });

  /// Имя секции в хранилище — без приставки экрана, её добавляет виджет.
  final String prefsKey;
  final String title;
  final IconData? icon;

  /// Цвет заголовка и значка; для «опасных» секций — `colorScheme.error`.
  final Color? color;
  final List<Widget> children;

  @override
  State<SettingsCollapsible> createState() => _SettingsCollapsibleState();
}

class _SettingsCollapsibleState extends State<SettingsCollapsible> {
  /// Пока не подняли prefs, секция развёрнута: раскрытое — состояние по
  /// умолчанию, и мигать схлопыванием на старте экрана нечестно.
  bool _open = true;

  String get _key => 'settings:${widget.prefsKey}';

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final collapsed = await UiPrefs.collapsedSections();
    if (!mounted || !collapsed.contains(_key)) return;
    setState(() => _open = false);
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
    unawaited(UiPrefs.setSectionCollapsed(_key, !_open));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = widget.color ?? scheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: tint),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: ProfileTheme.sectionLabel(
                      scheme,
                      color: widget.color,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0.0,
                  duration: Motion.short4,
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.short4,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: _open
              ? SettingsGroup(widget.children)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Группа настроек: каждый пункт — свой блок, разделённые зазором.
///
/// Одной карточкой со строками через разделитель группа была до 10 августа
/// 2026. Форму блока задаёт его место в группе: первому большой верх,
/// последнему большой низ, средним малый радиус со всех сторон. Единственный
/// пункт скругляется целиком.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const SettingsGroup(this.children, {super.key});

  /// Внешние углы группы — те же 28, что были у прежней карточки.
  static const double outerRadius = 28;

  /// Углы внутри группы: блоки читаются одним разделом, а не россыпью.
  static const double innerRadius = 8;

  /// Зазор между блоками — он же заменил разделитель.
  static const double gap = 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Разделители остались в вызовах и молча отсеиваются: линию между блоками
    // рисовать нечем, а пустой [SettingsDivider] посреди группы сдвинул бы
    // формы соседей.
    final rows = [
      for (final c in children)
        if (c is! SettingsDivider) c,
    ];

    const outer = Radius.circular(outerRadius);
    const inner = Radius.circular(innerRadius);

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          Material(
            color: scheme.surfaceContainerHigh,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? outer : inner,
              bottom: i == rows.length - 1 ? outer : inner,
            ),
            child: rows[i],
          ),
        ],
      ],
    );
  }
}

/// Разделитель прежнего вида — внутри [SettingsGroup] больше не рисуется.
///
/// Класс оставлен намеренно: в неслитых ветках вызовы с ним ещё живут, и
/// группа их молча отсеивает. Убрать его можно, когда ветки сойдутся.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 76,
      endIndent: 16,
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

/// Круглый чип-иконка в строке настроек.
class SettingsIconChip extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  final Color? fg;

  const SettingsIconChip(this.icon, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: fg ?? scheme.onPrimaryContainer),
    );
  }
}

/// Строка настроек: чип-иконка, заголовок с подписью и трейлинг.
///
/// Трейлинг — обычно стрелка (переход) или тумблер. Для тумблеров задавать и
/// [onTap] (тап по всей строке переключает), и `onChanged` у самого тумблера.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Цвет фона и иконки чипа. По умолчанию — контейнер акцента.
  final Color? iconBg;
  final Color? iconFg;

  /// Цвет заголовка; для «опасных» строк — `error`.
  final Color? titleColor;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconBg,
    this.iconFg,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SettingsIconChip(icon, bg: iconBg, fg: iconFg),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontVariations: const [FontVariation('wght', 600)],
                      color: titleColor ?? scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Стрелка перехода — чтобы не повторять её у каждой строки.
class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: Theme.of(context).colorScheme.outline,
  );
}
