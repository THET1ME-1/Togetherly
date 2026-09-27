import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/gift.dart';
import '../../services/chest_service.dart';
import '../../theme/profile_theme.dart';
import '../common/gift_image.dart';

/// Лента «Из сундука» над полками магазина подарков (макет «Подарок из
/// сундука», вариант 5Б): выпавшие подарки, которые человек ещё не подарил и
/// не оставил себе. У повторов счётчик, у каждой карточки своя «Подарить» —
/// подарок уходит партнёру бесплатно. Пустой запас — ленты нет вовсе.
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
  List<(String, List<String>)> _groups = const [];
  String? _giving;

  @override
  void initState() {
    super.initState();
    final items = widget.debugItems;
    if (items != null) {
      _groups = groupChestStash(items);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final items = await ChestService.instance.stash();
    if (mounted) setState(() => _groups = groupChestStash(items));
  }

  Future<void> _give(String key, String openId) async {
    if (_giving != null) return;
    setState(() => _giving = key);
    final ok = await ChestService.instance.give(openId, widget.groupId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trKey(ok ? 'chestGiven' : 'chestChoiceFailed'))));
    setState(() => _giving = null);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) return const SizedBox.shrink();
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
            itemCount: _groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (key, ids) = _groups[i];
              return _StashCard(
                giftKey: key,
                count: ids.length,
                busy: _giving == key,
                onGive: _giving == null ? () => _give(key, ids.first) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StashCard extends StatelessWidget {
  const _StashCard({required this.giftKey, required this.count, required this.busy, required this.onGive});

  final String giftKey;
  final int count;
  final bool busy;
  final VoidCallback? onGive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 118,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(22)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
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
