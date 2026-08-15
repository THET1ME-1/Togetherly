import 'package:flutter/material.dart';

import '../../models/symbol_catalog.dart';
import '../../models/wish.dart';
import '../../screens/wishes_screen.dart';
import '../../services/locale_service.dart';
import '../../services/wish_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../common/stable_stream_builder.dart';

/// Вход в «Хочу с тобой» с главной: два ближайших желания и строка архива.
///
/// Карточка того же вида, что остальные блоки главной — контейнер выше фона,
/// радиус 28, без тени. Пустой список тоже показываем: иначе о разделе узнают
/// только те, кто случайно нашёл его в другом месте.
class WishesCard extends StatelessWidget {
  const WishesCard({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    required this.myName,
    required this.partnerUid,
    required this.partnerName,
    this.myAvatarUrl,
    this.partnerAvatarUrl,
  });

  final AppTheme theme;
  final String groupId;
  final String myUid;
  final String myName;
  final String partnerUid;
  final String partnerName;
  final String? myAvatarUrl;
  final String? partnerAvatarUrl;

  @override
  Widget build(BuildContext context) {
    if (groupId.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final ru = LocaleService.instance.isRussian;

    return StableStreamBuilder<List<Wish>>(
      create: () => WishRepository.instance.watch(groupId),
      keys: [groupId],
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Wish>[];
        final dreaming = Wish.dreaming(all);
        final doneCount = all.where((w) => w.done).length;

        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _open(context),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ru ? 'Хочу с тобой' : 'Want with you',
                        style: AppFonts.unbounded(
                            size: 17, weight: 600, color: cs.onSurface),
                      ),
                    ),
                    Text(
                      ru ? 'Все →' : 'All →',
                      style: AppFonts.onest(
                          size: 14, weight: 700, color: cs.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (dreaming.isEmpty)
                _EmptyRow(scheme: cs, ru: ru, onTap: () => _open(context))
              else
                for (final wish in dreaming.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _Row(
                      wish: wish,
                      scheme: cs,
                      author: _nameOf(wish.authorUid),
                      onTap: () => _open(context),
                    ),
                  ),
              if (doneCount > 0) ...[
                Divider(color: cs.outlineVariant, height: 13),
                InkWell(
                  onTap: () => _open(context, fulfilled: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      ru
                          ? '$doneCount уже сбылось — посмотреть'
                          : '$doneCount already came true — see them',
                      style:
                          AppFonts.onest(size: 12.5, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _nameOf(String uid) {
    if (uid == myUid) return myName;
    if (uid == partnerUid) return partnerName;
    return '';
  }

  void _open(BuildContext context, {bool fulfilled = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WishesScreen(
          theme: theme,
          groupId: groupId,
          myUid: myUid,
          myName: myName,
          partnerUid: partnerUid,
          partnerName: partnerName,
          myAvatarUrl: myAvatarUrl,
          partnerAvatarUrl: partnerAvatarUrl,
          openFulfilled: fulfilled,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.wish,
    required this.scheme,
    required this.author,
    required this.onTap,
  });

  final Wish wish;
  final ColorScheme scheme;
  final String author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (author.isNotEmpty) author,
      if (wish.note.isNotEmpty) wish.note,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: SymbolIcon(wish.iconName,
                size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wish.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.unbounded(
                      size: 15, weight: 600, color: scheme.onSurface),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.onest(
                        size: 12.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({
    required this.scheme,
    required this.ru,
    required this.onTap,
  });

  final ColorScheme scheme;
  final bool ru;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: SymbolIcon('auto_awesome',
                size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ru
                  ? 'Что посмотреть, куда съездить, где поесть — соберите список на двоих.'
                  : 'What to watch, where to go, where to eat — start a list for two.',
              style: AppFonts.onest(
                  size: 13, height: 1.4, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
