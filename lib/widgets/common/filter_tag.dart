import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';

/// Чип фильтра: иконка и подпись, выбранный залит акцентом темы.
///
/// Один вид на ленту воспоминаний и каталог виджетов: плоский, без тени и
/// обводки, высотой 40.
class FilterTag extends StatelessWidget {
  const FilterTag({
    super.key,
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingIcon,
  });

  final AppTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Значок после подписи: у чипа порядка — стрелка вниз, он открывает лист.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final background = selected ? t.fillColor : t.cardSurface;
    final foreground = selected
        ? AppThemes.onColor(t.fillColor, mode: t.brightness)
        : t.textPrimary;
    final iconColor = selected ? foreground : t.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            padding: EdgeInsets.only(
              left: icon == null ? 14 : 11,
              right: trailingIcon == null ? 14 : 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppFonts.onest(size: 14, weight: 600, color: foreground),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(trailingIcon, size: 20, color: iconColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
