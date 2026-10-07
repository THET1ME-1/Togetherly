import 'package:flutter/material.dart';

import '../../services/locale_service.dart';

/// Короткая заметка набирается крупно, как цитата: без заголовка, в одну
/// мысль, без переносов строк.
bool noteIsShort(String text, {required bool hasTitle}) {
  final t = text.trim();
  return !hasTitle && t.isNotEmpty && t.length <= 80 && !t.contains('\n');
}

/// Пин-заметка ленты воспоминаний: вариант «Большая кавычка» из макета
/// https://claude.ai/artifact/XzjCKcmfQgyLtwexH48i2B (07.10.2026).
///
/// Прежняя заметка была жёлтым стикером: цвет прошит в коде и не менялся с
/// темой, автор подписан курсивом внизу листка. Теперь лист тонального цвета
/// темы (`secondaryContainer`), над его краем огромная кавычка цвета темы, а
/// автора и время называет общая шапка карточки, как у всех пинов.
///
/// Текст рисует [bodyBuilder]: лента отдаёт туда свой разбор спойлеров.
class NotePin extends StatelessWidget {
  const NotePin({
    super.key,
    required this.scheme,
    required this.fill,
    required this.body,
    required this.bodyBuilder,
    this.title,
  });

  final ColorScheme scheme;

  /// Цвет кавычки — `AppTheme.fillColor`.
  final Color fill;
  final String? title;
  final String body;
  final Widget Function(String text, TextStyle style) bodyBuilder;

  /// Сколько кавычка поднимается над листом.
  /// Глиф занимает примерно 10…37 точек строки, поэтому при 22 нижняя
  /// половина кавычки лежит на листе.
  static const double _quoteLift = 22;

  @override
  Widget build(BuildContext context) {
    final head = title?.trim() ?? '';
    final text = body.trim();
    final short = noteIsShort(text, hasTitle: head.isNotEmpty);
    final ink = scheme.onSecondaryContainer;
    final bodyStyle = short
        ? TextStyle(
            fontFamily: 'Onest',
            fontSize: 21,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: ink,
          )
        : TextStyle(
            fontFamily: 'Onest',
            fontSize: 17,
            height: 1.45,
            color: ink,
          );
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _quoteLift),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (head.isNotEmpty) ...[
                  Text(
                    head,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (text.isNotEmpty)
                  bodyBuilder(text, bodyStyle)
                else
                  Text(
                    LocaleService.current.memBadgeNote,
                    style: bodyStyle.copyWith(color: ink.withValues(alpha: 0.7)),
                  ),
              ],
            ),
          ),
        ),
        // Кавычка лежит поверх края листа и касаний не забирает.
        Positioned(
          left: 14,
          top: 0,
          child: IgnorePointer(
            child: Text(
              '“',
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 88,
                fontWeight: FontWeight.w800,
                height: 1,
                color: fill,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
