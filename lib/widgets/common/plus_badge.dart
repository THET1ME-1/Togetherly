import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/readable_text.dart';

/// Значок Togetherly+ рядом с именем.
///
/// Цвет берётся из темы, поэтому значок живёт во всех двадцати палитрах и не
/// тащит своих констант.
///
/// На iPhone не показывается никогда. Togetherly+ там не существует как
/// понятие: нет ни витрины, ни замков, ни самого названия — упоминание
/// платного, которого нет в App Store, стоило бы разбора с ревью (по 2.1(b)
/// на паках монет уже прилетало). Купленное при этом работает и на iOS, просто
/// молча.
class PlusBadge extends StatelessWidget {
  const PlusBadge({
    super.key,
    required this.theme,
    this.visible = true,
    this.compact = false,
  });

  final AppTheme theme;

  /// Куплен ли Togetherly+ у того, чьё имя рядом.
  final bool visible;

  /// Уменьшенный вариант — для плотных строк вроде карусели связей.
  final bool compact;

  static bool get _allowed => !Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    if (!visible || !_allowed) return const SizedBox.shrink();
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Plus',
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: readableTextOn(theme.primary),
        ),
      ),
    );
  }
}

/// Метка Togetherly+ на аватаре: кружок со знаком «плюс».
///
/// Для мест, где ширины на пилюлю нет — шапка чата, списки. Обводка красится в
/// цвет фона под аватаром, иначе метка сливается с самой картинкой.
class PlusAvatarDot extends StatelessWidget {
  const PlusAvatarDot({
    super.key,
    required this.theme,
    required this.child,
    this.visible = true,
    this.size = 16,
    this.ringColor,
  });

  final AppTheme theme;

  /// Аватар, к которому крепится метка.
  final Widget child;

  final bool visible;

  /// Диаметр метки. Под аватар 34–40 — 16, под крупный можно больше.
  final double size;

  /// Цвет обводки: подставляйте фон, на котором лежит аватар.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    if (!visible || !PlusBadge._allowed) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: ringColor ?? theme.cardSurface,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              size: size * 0.62,
              color: readableTextOn(theme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
