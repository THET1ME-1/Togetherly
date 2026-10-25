import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart';
import '../../models/catalog_price.dart';
import '../../models/custom_mood.dart';
import '../../models/level.dart';
import '../../models/mood_entry.dart';
import '../../models/mood_pack.dart';
import '../../models/own_mood_pack.dart';
import '../../models/user_data.dart';
import '../../screens/plus_screen.dart';
import '../../services/catalog_service.dart';
import '../../services/coin_store.dart';
import '../../services/custom_mood_service.dart';
import '../../services/mood_pack_service.dart';
import '../../services/plus_access.dart';
import '../../services/plus_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';
import '../common/m3_loading.dart';
import '../mood/custom_mood_sheet.dart';
import '../mood/mood_form_parts.dart';
import '../mood/own_mood_pack_view.dart';
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
/// набор общий на пару. Первой в ряду стоит таблетка «Свои» — настроения,
/// которые пара завела сама (Togetherly+), если [groupId] есть.
Future<StickerChoice?> showStickerPicker(
  BuildContext context, {
  UserData? user,
  Set<String> pairOwned = const {},
  String groupId = '',
  CustomMoodStore? store,
  PlusGate? plusGate,
}) {
  return showAppSheet<StickerChoice>(
    context,
    builder: (_) => SheetScaffold(
      title: trKey('stickersTitle'),
      child: StickerPicker(
        user: user,
        pairOwned: pairOwned,
        groupId: groupId,
        store: store,
        plusGate: plusGate,
      ),
    ),
  );
}

class StickerPicker extends StatefulWidget {
  const StickerPicker({
    super.key,
    this.user,
    this.pairOwned = const {},
    this.groupId = '',
    this.store,
    this.plusGate,
  });

  final UserData? user;
  final Set<String> pairOwned;

  /// Пара, чьи «Свои» настроения показать. Пусто — таблетки «Свои» нет.
  final String groupId;

  /// Набор своих настроений. По умолчанию [CustomMoodService]; тесты кладут
  /// набор в памяти.
  final CustomMoodStore? store;

  /// Гейт Плюса вместо [PlusService.gate] — для тестов.
  final PlusGate? plusGate;

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  /// Набор, выбранный здесь или в прошлый раз; [kOwnMoodPackId] — «Свои».
  String? _packId;

  List<CustomMood> _custom = const [];
  bool _customLoaded = false;

  CustomMoodStore get _store => widget.store ?? CustomMoodService.instance;

  PlusGate get _gate => widget.plusGate ?? PlusService.instance.gate;

  OwnPackState get _ownState => ownPackState(
        hasGroup: widget.groupId.isNotEmpty,
        gate: _gate,
        loaded: _customLoaded,
        count: _custom.length,
      );

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final last = prefs.getString(kStickerLastPackKey);
      if (mounted && last != null && _packId == null) {
        setState(() => _packId = last);
      }
    });
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    final none = widget.groupId.isEmpty || _gate == PlusGate.hidden;
    final list = none ? const <CustomMood>[] : await _store.load(widget.groupId);
    if (!mounted) return;
    setState(() {
      _custom = list;
      _customLoaded = true;
    });
  }

  /// Показаны ли «Свои». Без выбора здесь — если ими человек отмечает
  /// настроение и выбрать в них есть что.
  bool _ownShown(OwnPackState own) {
    if (own == OwnPackState.hidden) return false;
    if (_packId != null) return _packId == kOwnMoodPackId;
    return MoodPackService.instance.selectedPackId == kOwnMoodPackId &&
        ownPackSelectable(own);
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

  Future<void> _pickOwn(CustomMood mood) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kStickerLastPackKey, kOwnMoodPackId);
    if (!mounted) return;
    Navigator.of(context).pop(
      StickerChoice(image: mood.imageUrl, pack: kOwnMoodPackId, mood: mood.moodId),
    );
  }

  /// Первое своё настроение пары: с Плюсом и пустым набором.
  Future<void> _createOwn() async {
    final made = await showCustomMoodSheet(context, widget.groupId, store: widget.store);
    if (made == true) await _loadCustom();
  }

  void _openPlus() {
    // Тема до перехода: лист наклеек могут закрыть, пока окно Togetherly+
    // открыто, а его перестройка читала бы пустой context (TOG-33).
    final scheme = ProfileTheme.schemeFor(context.appTheme);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlusScreen(scheme: scheme),
    ));
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
    final cs = ProfileTheme.schemeFor(t);
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
        final own = _ownState;
        final ownChip = own != OwnPackState.hidden;
        final ownShown = _ownShown(own);
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
                itemCount: packs.length + (ownChip ? 1 : 0),
                // «Свои» отделены от наборов чуть шире, как в выборе
                // настроения: это набор пары, а не пак.
                separatorBuilder: (_, i) =>
                    SizedBox(width: ownChip && i == 0 ? 12 : 8),
                itemBuilder: (_, i) {
                  if (ownChip && i == 0) {
                    return OwnMoodPackChip(
                      key: const Key('sticker-pack-own'),
                      chip: _ownChipData(cs),
                      selected: ownShown,
                      stretched: false,
                    );
                  }
                  final p = packs[i - (ownChip ? 1 : 0)];
                  return MoodPackChip(
                    key: Key('sticker-pack-${p.id}'),
                    pack: p,
                    selected: !ownShown && p.id == pack.id,
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
                child: ownShown
                    ? _ownBody(own, cs)
                    : _grid(
                        count: pack.moods.length,
                        tile: (i) {
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
            if (ownShown && own == OwnPackState.teaser) ...[
              _bottomButton(
                key: const Key('sticker-own-unlock'),
                label: trKey('customMoodUnlock'),
                onPressed: _openPlus,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  trKey('customMoodUnlockNote'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ] else if (!ownShown && !open && widget.user != null && pack.unlock.isForSale)
              _bottomButton(
                key: const Key('sticker-pack-buy'),
                label: _buyLabel(pack),
                onPressed: () => _buy(pack),
              ),
          ],
        );
      },
    );
  }

  Widget _grid({required int count, required Widget Function(int) tile}) =>
      GridView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: count,
        itemBuilder: (_, i) => tile(i),
      );

  Widget _bottomButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            key: key,
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(label),
          ),
        ),
      );

  /// Таблетка «Свои»: картинка первого своего настроения или «+».
  OwnPackChip _ownChipData(ColorScheme cs) {
    final first = _custom.isEmpty ? null : _custom.first;
    return OwnPackChip(
      preview: first?.imageUrl ?? '',
      previewTint: first != null && first.onTintedTile
          ? moodScoreTint(first.score, cs, alpha: 0.30)
          : null,
      locked: _gate == PlusGate.locked,
      onTap: () => setState(() => _packId = kOwnMoodPackId),
    );
  }

  /// «Свои»: сетка настроений пары, а пока их нет — пример без Плюса или
  /// «Создать настроение» с ним.
  Widget _ownBody(OwnPackState own, ColorScheme cs) {
    switch (own) {
      case OwnPackState.hidden:
      case OwnPackState.loading:
        return SizedBox(
          height: 180,
          child: Center(child: M3Loading(color: cs.primary)),
        );
      case OwnPackState.teaser:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OwnMoodsEmpty(
            title: trKey('customMoodTeaserTitle'),
            text: trKey('customMoodTeaserText'),
          ),
        );
      case OwnPackState.empty:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OwnMoodsEmpty(
            title: trKey('customMoodEmptyTitle'),
            text: trKey('customMoodEmptyText'),
            onCreate: _createOwn,
          ),
        );
      case OwnPackState.list:
        return _grid(
          count: _custom.length,
          tile: (i) {
            final mood = _custom[i];
            // Эмодзи прозрачный — стоит на плитке цвета своей шкалы, как в
            // выборе настроения. Фото и рисунок заполняют плитку сами.
            return _Tile(
              key: Key('sticker-own-${mood.moodId}'),
              image: mood.imageUrl,
              background: mood.onTintedTile
                  ? moodScoreTint(mood.score, cs, alpha: 0.30)
                  : context.appTheme.cardSurface,
              fill: !mood.onTintedTile,
              locked: false,
              onTap: () => _pickOwn(mood),
            );
          },
        );
    }
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
    this.fill = false,
  });

  final String image;
  final Color background;
  final bool locked;
  final VoidCallback onTap;

  /// Картинка заполняет плитку целиком: фото и рисунок своих настроений.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (_, box) => fill
              ? MoodImage(image,
                  fit: BoxFit.cover, width: box.maxWidth, height: box.maxHeight)
              : Center(
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
