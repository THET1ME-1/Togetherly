import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart';
import '../../models/catalog_price.dart';
import '../../models/level.dart';
import '../../models/mood_entry.dart';
import '../../models/mood_pack.dart';
import '../../models/user_data.dart';
import '../../services/catalog_service.dart';
import '../../services/coin_store.dart';
import '../../services/mood_pack_service.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';
import '../mood_image.dart';
import '../mood_pack_selector.dart';

/// Выбранная в листе наклейка: картинка и откуда она.
class StickerChoice {
  const StickerChoice({required this.image, required this.pack, required this.mood});

  final String image;
  final String pack;
  final String mood;
}

/// Ключ prefs: из какого набора клеили в прошлый раз.
const String kStickerLastPackKey = 'sticker_last_pack';

/// Лист «Наклейки»: ряд наборов как в выборе настроения и сетка картинок.
///
/// Открытые наборы выбираются сразу, закрытые видны с замком: сетка
/// показывает, что внутри, а внизу кнопка покупки — та же, что у настроений,
/// набор общий на пару.
Future<StickerChoice?> showStickerPicker(
  BuildContext context, {
  UserData? user,
  Set<String> pairOwned = const {},
}) {
  return showAppSheet<StickerChoice>(
    context,
    builder: (_) => SheetScaffold(
      title: trKey('stickersTitle'),
      child: StickerPicker(user: user, pairOwned: pairOwned),
    ),
  );
}

class StickerPicker extends StatefulWidget {
  const StickerPicker({super.key, this.user, this.pairOwned = const {}});

  final UserData? user;
  final Set<String> pairOwned;

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  String? _packId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final last = prefs.getString(kStickerLastPackKey);
      if (mounted && last != null && _packId == null) {
        setState(() => _packId = last);
      }
    });
  }

  bool _open(MoodPack p) =>
      moodPackOpenFor(p, user: widget.user, pairOwned: widget.pairOwned);

  Future<void> _pick(MoodPack pack, MoodOption mood) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kStickerLastPackKey, pack.id);
    if (!mounted) return;
    Navigator.of(context).pop(
      StickerChoice(image: mood.imagePath, pack: pack.id, mood: mood.id),
    );
  }

  Future<void> _buy(MoodPack pack) async {
    final user = widget.user;
    if (user == null) return;
    await buyMoodPack(context, pack, user: user, onBought: () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return AnimatedBuilder(
      animation: CatalogService.instance,
      builder: (context, _) {
        final packs = CatalogService.instance.allPacks
            .where((p) => moodPackVisible(
                  isIOS: Platform.isIOS,
                  isMoney: p.unlock.isMoney,
                  isOpen: _open(p),
                  buysInStore: kCatalogBuysInStore,
                ))
            .where((p) => p.moods.isNotEmpty)
            .toList();
        if (packs.isEmpty) return const SizedBox(height: 120);
        final pack = _shownPack(packs);
        final open = _open(pack);
        final screen = MediaQuery.sizeOf(context).height;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: packs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = packs[i];
                  return MoodPackChip(
                    key: Key('sticker-pack-${p.id}'),
                    pack: p,
                    selected: p.id == pack.id,
                    locked: !_open(p),
                    primary: t.primary,
                    stretched: false,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _packId = p.id);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: math.max(180, screen * 0.46)),
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: pack.moods.length,
                  itemBuilder: (_, i) {
                    final mood = pack.moods[i];
                    return _Tile(
                      key: Key('sticker-${pack.id}-${mood.id}'),
                      image: mood.imagePath,
                      background: t.cardSurface,
                      locked: !open,
                      onTap: open ? () => _pick(pack, mood) : () => _buy(pack),
                    );
                  },
                ),
              ),
            ),
            if (!open && widget.user != null && pack.unlock.isForSale)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    key: const Key('sticker-pack-buy'),
                    onPressed: () => _buy(pack),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(_buyLabel(pack)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Какой набор показан: выбранный здесь, иначе прошлый, иначе тот, которым
  /// человек отмечает настроение, иначе первый открытый.
  MoodPack _shownPack(List<MoodPack> packs) {
    for (final id in [_packId, MoodPackService.instance.selectedPackId]) {
      if (id == null) continue;
      for (final p in packs) {
        if (p.id == id) return p;
      }
    }
    return packs.firstWhere(_open, orElse: () => packs.first);
  }

  String _buyLabel(MoodPack pack) {
    // Цену называет магазин, каталог — запасной ответ (как в выборе
    // настроения: число из манифеста рядом с ценой магазина читалось бы
    // второй ценой).
    final price = catalogPriceLabel(
      storePrice: kCatalogBuysInStore
          ? sharedCoinStore.priceLabel(catalogProductId(
              Unlock.featureKey(kMoodPackFeatureKind, pack.id)))
          : null,
      catalogPrice: pack.unlock.priceLabel,
    );
    return ruEn('Открыть за $price', 'Unlock for $price');
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.image,
    required this.background,
    required this.locked,
    required this.onTap,
  });

  final String image;
  final Color background;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (_, box) => Center(
            child: Opacity(
              opacity: locked ? 0.45 : 1,
              child: MoodImage(image, width: box.maxWidth * 0.78),
            ),
          ),
        ),
      ),
    );
  }
}
