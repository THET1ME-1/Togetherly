import 'package:flutter/material.dart';

import 'dart:async';

import '../dict_strings.dart' show ruEn;
import '../models/tu_wear.dart';
import '../services/catalog_service.dart';
import '../services/locale_service.dart';
import '../services/plus_service.dart';
import '../services/pocketbase_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/tu_wear_service.dart';
import '../widgets/common/ad_result.dart';
import '../widgets/common/guide_mascot.dart';
import '../widgets/mascot/cloud_mascot_view.dart';

/// Гардероб Ту (макет https://claude.ai/artifact/STQLhwignRaZiemWzbYYBF,
/// вариант Б): Ту крупно сверху в своём наряде, ниже разделы вкладками —
/// очки, лицо, шарфы, макушка, над головой. В разделе надета одна вещь,
/// разделы носятся вместе. Вещи из сундука до выпадения стоят под замком,
/// вещи магазина покупаются прямо с плитки: за монеты или за ролик.
///
/// Входы: меню Ту на главной («Гардероб») и карточка Ту в галерее маскотов.
class TuWardrobeScreen extends StatefulWidget {
  const TuWardrobeScreen({super.key});

  @override
  State<TuWardrobeScreen> createState() => _TuWardrobeScreenState();
}

class _TuWardrobeScreenState extends State<TuWardrobeScreen> {
  bool get _ru => LocaleService.instance.language == AppLanguage.ru;

  /// Ролик для вещей «за ролик». С Togetherly+ вещь отдаётся без ролика.
  final RewardedAdService _ad = RewardedAdService();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!PlusService.instance.active) unawaited(_ad.load());
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([CatalogService.instance, TuWearService.instance]),
      builder: (context, _) {
        final items = wardrobeItems(CatalogService.instance.wearItems, owned: TuWearService.instance.owned);
        final cats = [for (final c in kTuWearCats) if (items.any((w) => w.cat == c)) c];
        return DefaultTabController(
          length: cats.isEmpty ? 1 : cats.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(ruEn('Гардероб Ту', 'Tu’s wardrobe')),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Chip(
                    avatar: Icon(Icons.toll_rounded, size: 18, color: cs.onSecondaryContainer),
                    label: Text('${TuWearService.instance.coins}'),
                    backgroundColor: cs.secondaryContainer,
                    labelStyle: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
                    side: BorderSide.none,
                  ),
                ),
              ],
              bottom: cats.isEmpty
                  ? null
                  : TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [for (final c in cats) Tab(text: tuWearCatName(c, ru: _ru))],
                    ),
            ),
            body: Column(
              children: [
                _stage(cs),
                Expanded(
                  child: cats.isEmpty
                      ? _empty(cs)
                      : TabBarView(children: [for (final c in cats) _grid(cs, [for (final w in items) if (w.cat == c) w])]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Ту крупно в том, что надето прямо сейчас.
  Widget _stage(ColorScheme cs) {
    return Container(
      width: double.infinity,
      height: 200,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      alignment: Alignment.center,
      child: const CloudMascotView(size: 120),
    );
  }

  Widget _empty(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            ruEn('Вещи для Ту появятся здесь, как только загрузится каталог.', 'Tu’s items will appear here once the catalog loads.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );

  Widget _grid(ColorScheme cs, List<TuWear> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
      itemCount: items.length,
      itemBuilder: (context, i) => _tile(cs, items[i]),
    );
  }

  Widget _tile(ColorScheme cs, TuWear item) {
    final service = TuWearService.instance;
    final owned = service.owns(item.key);
    final worn = service.outfit[item.cat] == item.key && owned;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final iconUrl = item.iconKey.isEmpty ? null : catalogArtUrl(item.iconKey, artDecodeBucket(64 * dpr));
    final bg = worn ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = worn ? cs.onPrimaryContainer : cs.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _tap(item, owned),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Column(
            children: [
              Expanded(
                child: Opacity(
                  opacity: owned || !item.fromChest ? 1 : 0.45,
                  child: iconUrl == null ? Icon(Icons.checkroom, color: fg) : catalogArtImage(iconUrl, side: 64, decode: artDecodeBucket(64 * dpr)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _ru ? item.nameRu : item.nameEn,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg, height: 1.2),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!owned) Icon(_sourceIcon(item), size: 14, color: cs.onSurfaceVariant),
                  if (!owned) const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      worn ? ruEn('Надето', 'Wearing') : owned ? ruEn('Надеть', 'Wear') : _sourceLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: worn ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _sourceIcon(TuWear item) => switch (item.src) {
        'coins' => Icons.toll_rounded,
        'ad' => Icons.play_circle_outline_rounded,
        _ => Icons.lock_outline,
      };

  String _sourceLabel(TuWear item) => switch (item.src) {
        'coins' => ruEn('${item.price} монет', '${item.price} coins'),
        'ad' => PlusService.instance.active ? ruEn('Забрать', 'Get') : ruEn('За ролик', 'Watch ad'),
        _ => ruEn('Из сундука', 'From chest'),
      };

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
  }

  Future<void> _tap(TuWear item, bool owned) async {
    if (owned) {
      await TuWearService.instance.toggle(item);
      return;
    }
    if (item.fromChest || (item.src != 'coins' && item.src != 'ad')) {
      _say(ruEn('Выпадает из сундука «Уютная осень»', 'Drops from the “Cozy autumn” chest'));
      return;
    }
    if (_busy) return;
    final name = _ru ? item.nameRu : item.nameEn;
    final service = TuWearService.instance;
    if (item.src == 'coins' && service.coins < item.price) {
      _say(ruEn('Не хватает монет: нужно ${item.price}, у вас ${service.coins}',
          'Not enough coins: ${item.price} needed, you have ${service.coins}'));
      return;
    }
    setState(() => _busy = true);
    try {
      final byAd = item.src == 'ad';
      if (byAd && !PlusService.instance.active) {
        if (!_ad.isReady) {
          unawaited(_ad.load());
          _say(ruEn('Ролик ещё грузится, попробуйте через пару секунд', 'The ad is still loading, try again in a moment'));
          return;
        }
        final earned = await _ad.show(uid: PocketBaseService().userId ?? '');
        unawaited(_ad.load());
        if (!earned) {
          if (mounted) await showAdNotEarned(context);
          return;
        }
      }
      final error = await service.buy(item, ad: byAd);
      if (!mounted) return;
      _say(switch (error) {
        null => ruEn('«$name» теперь ваше и уже надето', '“$name” is yours and already on'),
        'insufficient' => ruEn('Не хватает монет: нужно ${item.price}, у вас ${service.coins}',
            'Not enough coins: ${item.price} needed, you have ${service.coins}'),
        _ => ruEn('Не получилось, попробуйте ещё раз', 'Something went wrong, try again'),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
