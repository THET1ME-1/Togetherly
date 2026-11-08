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
import '../widgets/common/coin_image.dart';
import '../widgets/common/guide_mascot.dart';
import '../widgets/mascot/cloud_mascot_view.dart';

/// Гардероб Ту (макет https://claude.ai/artifact/STQLhwignRaZiemWzbYYBF,
/// вариант Б): Ту крупно сверху в своём наряде, ниже разделы вкладками —
/// одежда, очки, лицо, шарфы, макушка, над головой. В разделе надета одна
/// вещь, разделы носятся вместе.
///
/// С 09.11.2026 — примерка (макет https://claude.ai/artifact/VAPbaGHZRu2nxWKP7PWUu8,
/// вариант «Б. Примерка»): нажатие на чужую вещь надевает её на Ту на сцене,
/// а купить её или забрать роликами можно из панели снизу. Над сеткой чипы
/// «Все / Мои / За монеты / За ролики», порядок — [wardrobeOrder]: что можно
/// взять сейчас, стоит первым. Вещь за монеты можно забрать и роликами
/// ([wearAdsNeeded]): сервер засчитывает их по одному и выдаёт вещь на
/// последнем.
///
/// Входы: меню Ту на главной («Гардероб») и карточка Ту в галерее маскотов.
class TuWardrobeScreen extends StatefulWidget {
  const TuWardrobeScreen({super.key});

  @override
  State<TuWardrobeScreen> createState() => _TuWardrobeScreenState();
}

class _TuWardrobeScreenState extends State<TuWardrobeScreen> {
  bool get _ru => LocaleService.instance.language == AppLanguage.ru;

  /// Ролик для вещей «за ролик» и вещей за монеты, взятых роликами; блок РСЯ
  /// свой. С Togetherly+ вещь «за ролик» отдаётся без ролика, а вещь за
  /// монеты роликами не берётся: у Плюса рекламы нет.
  final RewardedAdService _ad = RewardedAdService(wardrobe: true);
  bool _busy = false;

  /// Вещь, которую Ту примеряет на сцене; null — Ту в своём наряде.
  TuWear? _trying;
  WearFilter _filter = WearFilter.all;

  bool get _plus => PlusService.instance.active;

  @override
  void initState() {
    super.initState();
    if (!_plus) unawaited(_ad.load());
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
        final service = TuWearService.instance;
        final owned = service.owned;
        final items = wardrobeOrder(
          wardrobeFilter(wardrobeItems(CatalogService.instance.wearItems, owned: owned), _filter, owned: owned, plus: _plus),
          owned: owned,
          coins: service.coins,
        );
        final all = wardrobeItems(CatalogService.instance.wearItems, owned: owned);
        final cats = [for (final c in kTuWearCats) if (all.any((w) => w.cat == c)) c];
        final trying = _trying;
        return DefaultTabController(
          length: cats.isEmpty ? 1 : cats.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(ruEn('Гардероб Ту', 'Tu’s wardrobe')),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Chip(
                    avatar: const CoinImage(side: 22),
                    label: Text('${service.coins}'),
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
                _stage(cs, trying),
                _chips(cs),
                Expanded(
                  child: cats.isEmpty
                      ? _empty(cs, ruEn('Вещи для Ту появятся здесь, как только загрузится каталог.', 'Tu’s items will appear here once the catalog loads.'))
                      : TabBarView(children: [for (final c in cats) _grid(cs, [for (final w in items) if (w.cat == c) w])]),
                ),
              ],
            ),
            bottomNavigationBar: trying == null ? null : _bar(cs, trying),
          ),
        );
      },
    );
  }

  /// Ту крупно: в своём наряде или в примеряемой вещи.
  Widget _stage(ColorScheme cs, TuWear? trying) {
    return Container(
      width: double.infinity,
      height: 200,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CloudMascotView(
            key: ValueKey(trying?.key),
            size: 120,
            tryOn: trying == null ? null : wearTryOn(TuWearService.instance.outfit, trying),
          ),
          if (trying != null) ...[
            Positioned(
              top: 12,
              left: 12,
              right: 64,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined, size: 16, color: cs.onPrimaryContainer),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          ruEn('Примерка: ', 'Trying on: ') + (_ru ? trying.nameRu : trying.nameEn),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton.filledTonal(
                tooltip: ruEn('Снять примерку', 'Stop trying on'),
                onPressed: () => setState(() => _trying = null),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Чипы над сеткой. «За ролики» у Плюса нет: рекламы у него нет.
  Widget _chips(ColorScheme cs) {
    final chips = <(WearFilter, String)>[
      (WearFilter.all, ruEn('Все', 'All')),
      (WearFilter.mine, ruEn('Мои', 'Mine')),
      (WearFilter.coins, ruEn('За монеты', 'For coins')),
      if (!_plus) (WearFilter.ads, ruEn('За ролики', 'For ads')),
    ];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (filter, label) = chips[i];
          return FilterChip(
            label: Text(label),
            selected: _filter == filter,
            showCheckmark: true,
            onSelected: (_) => setState(() => _filter = filter),
          );
        },
      ),
    );
  }

  Widget _empty(ColorScheme cs, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );

  Widget _grid(ColorScheme cs, List<TuWear> items) {
    if (items.isEmpty) return _empty(cs, ruEn('Здесь пока пусто', 'Nothing here yet'));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
      itemCount: items.length,
      itemBuilder: (context, i) => _tile(cs, items[i]),
    );
  }

  Widget _tile(ColorScheme cs, TuWear item) {
    final service = TuWearService.instance;
    final owned = service.owns(item.key);
    final worn = service.outfit[item.cat] == item.key && owned;
    final trying = _trying?.key == item.key;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final iconUrl = item.iconKey.isEmpty ? null : catalogArtUrl(item.iconKey, artDecodeBucket(64 * dpr));
    final lit = worn || trying;
    final bg = lit ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = lit ? cs.onPrimaryContainer : cs.onSurface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: trying ? BorderSide(color: cs.primary, width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _tap(item, owned),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Column(
            children: [
              Expanded(
                child: Opacity(
                  opacity: owned || trying || !item.fromChest ? 1 : 0.45,
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
                  if (!owned && !trying && item.src == 'coins' && !_adsStarted(item)) const CoinImage(side: 16, animated: false),
                  if (!owned && !trying && (item.src != 'coins' || _adsStarted(item)))
                    Icon(_sourceIcon(item), size: 14, color: cs.onSurfaceVariant),
                  if (!owned && !trying) const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      worn
                          ? ruEn('Надето', 'Wearing')
                          : trying
                              ? ruEn('Примеряете', 'Trying on')
                              : owned
                                  ? ruEn('Надеть', 'Wear')
                                  : _sourceLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: lit ? cs.onPrimaryContainer : cs.onSurfaceVariant),
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

  /// Вещь за монеты, за которую уже начали смотреть ролики.
  bool _adsStarted(TuWear item) => item.src == 'coins' && !_plus && TuWearService.instance.adProgress(item.key) > 0;

  /// «3 ролика», «5 роликов».
  String _adsWord(int n) {
    final mod10 = n % 10, mod100 = n % 100;
    final ru = mod10 == 1 && mod100 != 11
        ? 'ролик'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'ролика'
            : 'роликов';
    return ruEn('$n $ru', n == 1 ? '1 ad' : '$n ads');
  }

  IconData _sourceIcon(TuWear item) => switch (item.src) {
        'ad' || 'coins' => Icons.play_circle_outline_rounded,
        _ => Icons.lock_outline,
      };

  String _sourceLabel(TuWear item) => switch (item.src) {
        'coins' when _adsStarted(item) =>
          ruEn('Ролики ${TuWearService.instance.adProgress(item.key)} из ${item.adsNeeded}',
              'Ads ${TuWearService.instance.adProgress(item.key)} of ${item.adsNeeded}'),
        'coins' => ruEn('${item.price} монет', '${item.price} coins'),
        'ad' => _plus ? ruEn('Забрать', 'Get') : ruEn('За ролик', 'Watch ad'),
        _ => ruEn('Из сундука', 'From chest'),
      };

  /// Панель под примеряемой вещью: купить, забрать роликами или откуда она
  /// выпадает.
  Widget _bar(ColorScheme cs, TuWear item) {
    final coins = TuWearService.instance.coins;
    final progress = TuWearService.instance.adProgress(item.key);
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    Widget label(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

    final List<Widget> actions;
    if (item.src == 'coins') {
      actions = [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy || coins < item.price ? null : () => _buyCoins(item),
            icon: const CoinImage(side: 20, animated: false),
            label: label(ruEn('Купить · ${item.price}', 'Buy · ${item.price}')),
            style: buttonStyle,
          ),
        ),
        if (!_plus && item.adsNeeded > 0) ...[
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _watchAd(item),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
              label: label(progress > 0
                  ? ruEn('Ещё ролик · $progress из ${item.adsNeeded}', 'Next ad · $progress of ${item.adsNeeded}')
                  : _adsWord(item.adsNeeded)),
              style: buttonStyle,
            ),
          ),
        ],
      ];
    } else if (item.src == 'ad') {
      actions = [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _watchAd(item),
            icon: Icon(_plus ? Icons.check_rounded : Icons.play_circle_outline_rounded, size: 20),
            label: label(_plus ? ruEn('Забрать', 'Get') : ruEn('Смотреть ролик', 'Watch ad')),
            style: buttonStyle,
          ),
        ),
      ];
    } else {
      // Пиджаки выпадают из обычного сундука, вещи набора — из своего.
      actions = [
        Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.set == 'autumn'
                ? ruEn('Выпадает из сундука «Уютная осень»', 'Drops from the “Cozy autumn” chest')
                : ruEn('Выпадает из сундука', 'Drops from the chest'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
        ),
      ];
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(height: 56, child: Row(children: actions)),
        ),
      ),
    );
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
  }

  /// Своя вещь надевается и снимается, чужая — примеряется на сцене; второе
  /// нажатие на примеряемую снимает примерку.
  Future<void> _tap(TuWear item, bool owned) async {
    if (owned) {
      setState(() => _trying = null);
      await TuWearService.instance.toggle(item);
      return;
    }
    setState(() => _trying = _trying?.key == item.key ? null : item);
  }

  Future<void> _buyCoins(TuWear item) async {
    if (_busy) return;
    final name = _ru ? item.nameRu : item.nameEn;
    final service = TuWearService.instance;
    setState(() => _busy = true);
    try {
      final error = await service.buy(item);
      if (!mounted) return;
      if (error == null) _trying = null;
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

  /// Один ролик за вещь. С Плюсом вещь «за ролик» отдаётся без ролика; вещь
  /// за монеты сюда с Плюсом не попадает (кнопки роликов у него нет). Не
  /// последний ролик — панель остаётся с «Ещё ролик · 1 из 3».
  Future<void> _watchAd(TuWear item) async {
    if (_busy) return;
    final name = _ru ? item.nameRu : item.nameEn;
    setState(() => _busy = true);
    try {
      if (!_plus) {
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
      final step = await TuWearService.instance.adStep(item);
      if (!mounted) return;
      if (step.granted) _trying = null;
      final more = step.error == null && !step.granted;
      _say(switch (step.error) {
        null when more => ruEn('Ролик засчитан: ${step.progress} из ${item.adsNeeded}', 'Ad counted: ${step.progress} of ${item.adsNeeded}'),
        null => ruEn('«$name» теперь ваше и уже надето', '“$name” is yours and already on'),
        'too_fast' => ruEn('Подождите пару секунд и смотрите следующий', 'Wait a few seconds before the next one'),
        _ => ruEn('Не получилось, попробуйте ещё раз', 'Something went wrong, try again'),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
