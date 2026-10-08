import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chest.dart';
import '../../services/locale_service.dart';
import '../../models/user_data.dart';
import '../../screens/chest_screen.dart';
import '../../services/catalog_service.dart';
import '../../services/chest_service.dart';
import '../../services/pair_jar_service.dart';
import '../../services/pb_data_service.dart';
import '../../services/plus_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../utils/readable_text.dart';
import 'chest_frames.dart';
import 'chest_prize_image.dart';
import 'jar_drops.dart';

/// Блок сундука на главной, между таймером и остальными разделами (макет
/// «Сундук недели», экран 1). Живой сундук слева, справа название, строка про
/// призы и чип «N из 3». Нажатие ведёт на экран сундука, по возвращении
/// остаток перечитывается.
///
/// Стоит на главной постоянно, а не первую неделю (решение заказчика
/// 27.09.2026). Убрать его можно без релиза: поле `app_config.chest_enabled`
/// в false — блок пропадает, а сервер перестаёт открывать сундук.
///
/// Фон — яркий цвет темы (`primaryContainer`), а не приглушённая поверхность:
/// блок должен выделяться на главной. Цвет из палитры, а не свой, чтобы блок
/// жил во всех двадцати пяти палитрах (решение заказчика 27.09.2026).
class ChestHomeCard extends StatefulWidget {
  const ChestHomeCard({
    super.key,
    required this.theme,
    required this.groupId,
    this.partnerName,
    this.onCoins,
    this.userData,
  });

  final AppTheme theme;
  final String groupId;
  final String? partnerName;
  final ValueChanged<int>? onCoins;

  /// Профиль — сундук кладёт туда выпавшую рамку и надевает её.
  final UserData? userData;

  @override
  State<ChestHomeCard> createState() => _ChestHomeCardState();
}

class _ChestHomeCardState extends State<ChestHomeCard> {
  ChestState? _state;
  bool _enabled = true;

  /// Сезонный сундук, который сервер поставил на главную (`home`), и его
  /// остаток открытий. null — на главной обычный.
  SeasonChest? _season;
  ChestState? _seasonState;

  @override
  void initState() {
    super.initState();
    PairJarService.instance.bindGroup(widget.groupId);
    PairJarService.instance.addListener(_onJar);
    _load();
  }

  @override
  void didUpdateWidget(ChestHomeCard old) {
    super.didUpdateWidget(old);
    if (old.groupId != widget.groupId) {
      PairJarService.instance.bindGroup(widget.groupId);
      _load();
    }
  }

  @override
  void dispose() {
    PairJarService.instance.removeListener(_onJar);
    super.dispose();
  }

  // Капля упала на другом экране (ролик за монеты, подарок) — блок обновляется
  // без перечитывания сервера.
  void _onJar() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ChestService.instance.state(groupId: widget.groupId),
      PbDataService().fetchChestEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _state = (results[0] as ChestState?) ?? _state;
      _enabled = results[1] as bool;
    });
    // Сезонный сундук на главной вместо обычного — решает сервер флагом
    // `home`. Кончился сезон или флаг снят — на главной снова обычный.
    final home = _state?.homeSeason;
    if (home == null) {
      if (_season != null) setState(() => _season = _seasonState = null);
      return;
    }
    ChestFrames.prefetch(home.file('idle'));
    final st = await ChestService.instance.state(groupId: widget.groupId, chest: home.key);
    if (!mounted) return;
    setState(() {
      _season = home;
      _seasonState = st ?? _seasonState;
    });
  }

  Future<void> _openScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChestScreen(
          theme: widget.theme,
          groupId: widget.groupId,
          partnerName: widget.partnerName,
          onCoins: widget.onCoins,
          userData: widget.userData,
          initialChest: _season?.key,
        ),
        settings: const RouteSettings(name: '/chest'),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final cs = ProfileTheme.schemeFor(widget.theme);
    final season = _season;
    final counted = season != null ? _seasonState : _state;
    final left = counted?.left ?? season?.perDay ?? 3, perDay = counted?.perDay ?? season?.perDay ?? 3;
    // В тёмной теме контейнер темы тёмный и сливается с фоном главной, поэтому
    // там фон — сам основной цвет темы, а чип — наоборот.
    // Цвет текста считается по контрасту к фону: в части палитр пара
    // контейнер/«на контейнере» даёт белый по светлому — около 2,5:1.
    // Сезонный сундук — в ночных цветах сезона с сервера: блок сразу видно.
    final dark = cs.brightness == Brightness.dark;
    final night = season?.palette;
    final bg = night?.surface ?? (dark ? cs.primary : cs.primaryContainer);
    final fg = night?.ink ?? readableTextOn(bg);
    final chipBg = night?.fill ?? (dark ? cs.onPrimary : cs.primary);
    final chipFg = night?.onFill ?? readableTextOn(chipBg);
    final lang = LocaleService.instance.language.code;
    final jar = PairJarService.instance.groupId == widget.groupId ? PairJarService.instance.jar : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openScreen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 16, 10),
            child: Row(
              children: [
                if (season != null)
                  ChestFrames(
                    key: ValueKey(season.file('idle')),
                    url: season.file('idle'),
                    still: null,
                    stillUrl: season.file('still'),
                    side: 112,
                  )
                else
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
                        season?.nameIn(lang) ?? trKey('chestWeekTitle'),
                        style: TextStyle(
                          fontFamily: ProfileTheme.displayFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (jar == null && season != null)
                        Text(season.hintIn(lang), style: TextStyle(fontSize: 13, height: 1.35, color: fg))
                      else if (jar == null)
                        Text(
                          // Togetherly+ — главный приз, с него описание и начинается.
                          // На iPhone Плюса нет как понятия, а купившему его не
                          // выиграть — им прежний текст.
                          trKey(
                            PlusService.instance.active
                                ? 'chestCardTextFree'
                                : PlusService.instance.visible
                                ? 'chestCardTextPlus'
                                : 'chestCardText',
                          ),
                          style: TextStyle(fontSize: 13, height: 1.35, color: fg),
                        )
                      else ...[
                        // Копилка пары (макет «Копилка пары», вариант А): строка
                        // и десять капель. Мои — цветом чипа, партнёра светлые: так
                        // видно, кто сколько положил.
                        Text(
                          jar.capped
                              ? trKey('jarCapped')
                              : trKey('jarLine').replaceAll('{k}', '${jar.count}').replaceAll('{n}', '${jar.size}'),
                          style: TextStyle(fontSize: 13, height: 1.35, color: fg),
                        ),
                        const SizedBox(height: 7),
                        JarDrops(
                          jar: jar,
                          mine: chipBg,
                          partner: Color.lerp(bg, Colors.white, 0.78)!,
                          dropHeight: 26,
                          gap: 2,
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              trKey('chestLeftChip').replaceAll('{n}', '$left').replaceAll('{m}', '$perDay'),
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: chipFg),
                            ),
                          ),
                          if (jar != null && jar.bonus > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                trKey('jarBonusChip').replaceAll('{n}', '${jar.bonus}'),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2A2D30),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
