import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chest.dart';
import '../../screens/chest_screen.dart';
import '../../services/catalog_service.dart';
import '../../services/chest_service.dart';
import '../../services/pb_data_service.dart';
import '../../services/plus_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../utils/readable_text.dart';
import 'chest_frames.dart';
import 'chest_prize_image.dart';

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
  const ChestHomeCard({super.key, required this.theme, required this.groupId, this.partnerName, this.onCoins});

  final AppTheme theme;
  final String groupId;
  final String? partnerName;
  final ValueChanged<int>? onCoins;

  @override
  State<ChestHomeCard> createState() => _ChestHomeCardState();
}

class _ChestHomeCardState extends State<ChestHomeCard> {
  ChestState? _state;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([ChestService.instance.state(), PbDataService().fetchChestEnabled()]);
    if (!mounted) return;
    setState(() {
      _state = (results[0] as ChestState?) ?? _state;
      _enabled = results[1] as bool;
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
    final left = _state?.left ?? 3, perDay = _state?.perDay ?? 3;
    // В тёмной теме контейнер темы тёмный и сливается с фоном главной, поэтому
    // там фон — сам основной цвет темы, а чип — наоборот.
    // Цвет текста считается по контрасту к фону: в части палитр пара
    // контейнер/«на контейнере» даёт белый по светлому — около 2,5:1.
    final dark = cs.brightness == Brightness.dark;
    final bg = dark ? cs.primary : cs.primaryContainer;
    final fg = readableTextOn(bg);
    final chipBg = dark ? cs.onPrimary : cs.primary;
    final chipFg = readableTextOn(chipBg);
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
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          trKey('chestLeftChip').replaceAll('{n}', '$left').replaceAll('{m}', '$perDay'),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: chipFg),
                        ),
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
