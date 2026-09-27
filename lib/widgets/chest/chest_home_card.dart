import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chest.dart';
import '../../screens/chest_screen.dart';
import '../../services/catalog_service.dart';
import '../../services/chest_service.dart';
import '../../services/plus_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import 'chest_frames.dart';
import 'chest_prize_image.dart';

/// Блок «Сундук недели» на главной, между таймером и остальными разделами
/// (макет «Сундук недели», экран 1). Живой сундук слева, справа название,
/// строка про призы и чип «осталось N из 3». Нажатие ведёт на экран сундука,
/// по возвращении остаток перечитывается.
class ChestHomeCard extends StatefulWidget {
  const ChestHomeCard({super.key, required this.theme, required this.groupId, this.onCoins});

  final AppTheme theme;
  final String groupId;
  final ValueChanged<int>? onCoins;

  @override
  State<ChestHomeCard> createState() => _ChestHomeCardState();
}

class _ChestHomeCardState extends State<ChestHomeCard> {
  ChestState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = await ChestService.instance.state();
    if (mounted && st != null) setState(() => _state = st);
  }

  Future<void> _openScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChestScreen(theme: widget.theme, groupId: widget.groupId, onCoins: widget.onCoins),
        settings: const RouteSettings(name: '/chest'),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final left = _state?.left ?? 3, perDay = _state?.perDay ?? 3;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openScreen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 16, 10),
          child: Row(
            children: [
              ListenableBuilder(
                listenable: CatalogService.instance,
                builder: (context, _) => ChestFrames(
                  key: ValueKey(CatalogService.instance.giftArt('chest_idle')?.smUrl),
                  url: CatalogService.instance.giftArt('chest_idle')?.smUrl,
                  still: kChestStill,
                  side: 112,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trKey('chestWeekTitle'),
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trKey(PlusService.instance.active ? 'chestCardTextFree' : 'chestCardText'),
                      style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        trKey('chestLeftChip').replaceAll('{n}', '$left').replaceAll('{m}', '$perDay'),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
