import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/gift.dart';
import '../../services/chest_service.dart';
import '../../theme/profile_theme.dart';
import '../common/gift_image.dart';
import '../gifts/gift_note_sheet.dart';
import 'chest_stash_sheet.dart';

/// Лента «Из сундука» над полками магазина подарков (макет «Подарок из
/// сундука», вариант 5Б): выпавшие подарки, которые человек ещё не подарил и
/// не оставил себе. У повторов счётчик, у каждой карточки своя «Подарить» —
/// подарок уходит партнёру бесплатно. Касание по карточке открывает лист
/// запаса на этом подарке: там его можно и оставить себе. Пустой запас —
/// ленты нет вовсе.
class ChestStashLane extends StatefulWidget {
  const ChestStashLane({super.key, required this.groupId, this.debugItems});

  final String groupId;

  /// Превью: готовый запас вместо похода на сервер.
  @visibleForTesting
  final List<ChestStashItem>? debugItems;

  @override
  State<ChestStashLane> createState() => _ChestStashLaneState();
}

class _ChestStashLaneState extends State<ChestStashLane> {
  List<ChestStashItem> _items = const [];
  String? _giving;

  List<(String, List<String>)> get _groups => groupChestStash(_items);

  @override
  void initState() {
    super.initState();
    final items = widget.debugItems;
    if (items != null) {
      _items = items;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final items = await ChestService.instance.stash();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _open(String key) async {
    if (_giving != null) return;
    await showChestStashSheet(
      context,
      cs: Theme.of(context).colorScheme,
      groupId: widget.groupId,
      items: _items,
      selected: key,
    );
    if (mounted && widget.debugItems == null) await _load();
  }

  Future<void> _give(String key, String openId) async {
    if (_giving != null) return;
    final note = await showGiftNoteSheet(
      context,
      cs: Theme.of(context).colorScheme,
      giftKey: key,
      title: GiftCatalog.byKey(key)?.title ?? key,
    );
    if (note == null || !mounted) return;
    setState(() => _giving = key);
    final ok = await ChestService.instance.give(openId, widget.groupId, note: note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trKey(ok ? 'chestGiven' : 'chestChoiceFailed'))));
    setState(() => _giving = null);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            trKey('chestStashTitle'),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (key, ids) = groups[i];
              return _StashCard(
                giftKey: key,
                count: ids.length,
                busy: _giving == key,
                onGive: _giving == null ? () => _give(key, ids.first) : null,
                onOpen: () => _open(key),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StashCard extends StatelessWidget {
  const _StashCard({
    required this.giftKey,
    required this.count,
    required this.busy,
    required this.onGive,
    required this.onOpen,
  });

  final String giftKey;
  final int count;
  final bool busy;
  final VoidCallback? onGive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 118,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Material(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  children: [
                    GiftImage(giftKey, side: 64),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        GiftCatalog.byKey(giftKey)?.title ?? giftKey,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy ? null : onGive,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          disabledBackgroundColor: cs.primary.withValues(alpha: 0.6),
                          disabledForegroundColor: cs.onPrimary,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(trKey('chestGive'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  '×$count',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
