import 'package:flutter/material.dart';

import '../../models/mood_entry.dart';
import '../../theme/fonts.dart';
import '../avatar_widget.dart';
import '../mood_image.dart';

/// Как менялось настроение за день: две дорожки, время посередине, вы слева,
/// партнёр справа. Макет — вариант А
/// (https://claude.ai/artifact/48RQNpqSdabA61pLew7qTS).
///
/// Просьба из отзыва в Play 14.08.2026: видеть, когда партнёр сменил
/// настроение и на какое, как в личном дневнике. До этого свою историю было
/// видно только по долгому нажатию на день, а партнёрскую — в его календаре.
class DayMoodLanes extends StatelessWidget {
  const DayMoodLanes({
    super.key,
    required this.mine,
    required this.theirs,
    required this.myName,
    required this.partnerName,
    this.myUid = '',
    this.partnerUid = '',
    this.myAvatarUrl,
    this.partnerAvatarUrl,
    this.myGender = '',
    this.partnerGender = '',
  });

  final List<MoodEntry> mine;
  final List<MoodEntry> theirs;
  final String myName;
  final String partnerName;
  final String myUid;
  final String partnerUid;
  final String? myAvatarUrl;
  final String? partnerAvatarUrl;

  /// Пол для подписи: «Устал» парню, «Устала» девушке.
  final String myGender;
  final String partnerGender;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = [
      for (final e in mine) (true, e),
      for (final e in theirs) (false, e),
    ]..sort((a, b) => a.$2.timestamp.compareTo(b.$2.timestamp));
    if (rows.isEmpty) return const SizedBox.shrink();

    Widget who(String name, String uid, String? url, {required bool left}) {
      final avatar = AvatarWidget(
        uid: uid,
        liveUrl: url,
        name: name,
        size: 30,
        primary: cs.primary,
        showFrame: false,
      );
      final label = Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.onest(size: 14, weight: 700, color: cs.onSurface),
        ),
      );
      return Expanded(
        child: Row(
          mainAxisAlignment:
              left ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: left
              ? [avatar, const SizedBox(width: 8), label]
              : [label, const SizedBox(width: 8), avatar],
        ),
      );
    }

    // Половине может не хватить места на картинку и подпись в строку:
    // «Тревожность» резалась до «Тревожно…» уже на 393 точках. Меряем
    // подписи дня, и если хоть одна не влезает, картинка встаёт над подписью
    // у всех — вид дня остаётся одинаковым.
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        double width(String text, double size, double weight) {
          final p = TextPainter(
            text: TextSpan(
                text: text, style: AppFonts.onest(size: size, weight: weight)),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          return p.width;
        }

        final pill = width('00:00', 12.5, 700) + 20;
        final side = (box.maxWidth - pill - 12) / 2;
        final compact = rows.any((r) {
          final label = r.$2.labelFor(r.$1 ? myGender : partnerGender);
          return 6 + 40 + 8 + width(label, 13.5, 700) + 12 > side;
        });
        return _lanes(cs, rows, who, compact: compact);
      },
    );
  }

  Widget _lanes(
    ColorScheme cs,
    List<(bool, MoodEntry)> rows,
    Widget Function(String, String, String?, {required bool left}) who, {
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            who(myName, myUid, myAvatarUrl, left: true),
            const SizedBox(width: 12),
            who(partnerName, partnerUid, partnerAvatarUrl, left: false),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            // Ось времени: тонкая линия ровно под пилюлями со временем.
            Positioned.fill(
              child: Center(
                child: Container(width: 2, color: cs.surfaceContainerHighest),
              ),
            ),
            Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _row(cs, rows[i].$1, rows[i].$2, compact: compact),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(ColorScheme cs, bool isMine, MoodEntry e,
      {required bool compact}) {
    final entry = _entry(cs, isMine, e, compact: compact);
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: isMine ? entry : null,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _hhmm(e.timestamp),
            style: AppFonts.onest(size: 12.5, weight: 700, color: cs.onSurface)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: isMine ? null : entry,
          ),
        ),
      ],
    );
  }

  Widget _entry(ColorScheme cs, bool isMine, MoodEntry e,
      {required bool compact}) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: e.imagePath.isNotEmpty
          ? MoodImage(e.imagePath, width: 40, height: 40, fit: BoxFit.cover)
          : Container(width: 40, height: 40, color: e.color),
    );
    final fg = isMine ? cs.onSurface : cs.onPrimaryContainer;
    final text = Text(
      e.labelFor(isMine ? myGender : partnerGender),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppFonts.onest(size: compact ? 12.5 : 13.5, weight: 700, color: fg),
    );
    final background = isMine ? cs.surfaceContainerHigh : cs.primaryContainer;
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [image, const SizedBox(height: 4), text],
        ),
      );
    }
    final label = Flexible(child: text);
    return Container(
      padding: isMine
          ? const EdgeInsets.fromLTRB(6, 6, 12, 6)
          : const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isMine
            ? [image, const SizedBox(width: 8), label]
            : [label, const SizedBox(width: 8), image],
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
