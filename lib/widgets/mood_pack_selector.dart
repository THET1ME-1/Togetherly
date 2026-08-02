import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/level.dart';
import '../models/mood_pack.dart';
import '../models/user_data.dart';
import '../services/catalog_service.dart';
import '../services/level_service.dart';
import '../services/locale_service.dart';
import '../services/mood_pack_service.dart';
import '../theme/theme_scope.dart';
import 'common/app_dialog.dart';
import 'mood_image.dart';

/// Выбор пака настроений в пикере: таблетки без обводки.
///
/// Пока паков два-три, они делят строку поровну — так строка читается как один
/// переключатель. Появится четвёртый — уезжают в горизонтальную прокрутку.
/// Ростом таблетки ниже вкладок «Настроение / Самочувствие»: выбор вкладки тут
/// главный, а пак — уточнение.
///
/// Платный пак виден всем, но с замком и ценой: закрытый выбрать нельзя, тап
/// по нему предлагает покупку за монеты. Без [user] замков нет вовсе — так
/// ведут себя старые точки вызова, куда данные о человеке не доходят.
class MoodPackSelector extends StatelessWidget {
  final Color primary;

  /// Вызывается после смены пака (родитель обновляет сетку настроений).
  final ValueChanged<MoodPack>? onChanged;

  /// Чей кошелёк и что уже куплено. Без него пак считается открытым.
  final UserData? user;

  /// Купленное партнёром: ключи `owned_features` группы. Пак общий на пару,
  /// как и маскот, поэтому платит кто-то один.
  final Set<String> pairOwned;

  const MoodPackSelector({
    super.key,
    required this.primary,
    this.onChanged,
    this.user,
    this.pairOwned = const {},
  });

  /// Открыт ли пак этому человеку.
  bool isOpen(MoodPack pack) {
    final u = user;
    if (u == null) return true;
    return u.unlocksCatalogItem(
      pack.unlock,
      kMoodPackFeatureKind,
      pack.id,
      LevelService.instance.level,
      boughtByPair: pairOwned.contains(
        Unlock.featureKey(kMoodPackFeatureKind, pack.id),
      ),
    );
  }

  /// До скольких паков строка делится поровну.
  static const int _stretchUpTo = 3;
  static const double _height = 38;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        [MoodPackService.instance, CatalogService.instance],
      ),
      builder: (context, _) {
        final selectedId = MoodPackService.instance.selectedPackId;
        final packs = CatalogService.instance.allPacks;
        if (packs.isEmpty) return const SizedBox.shrink();

        void select(MoodPack pack) {
          if (!isOpen(pack)) {
            _offerPurchase(context, pack);
            return;
          }
          if (pack.id == selectedId) return;
          HapticFeedback.selectionClick();
          MoodPackService.instance.setSelectedPack(pack.id);
          onChanged?.call(pack);
        }

        if (packs.length <= _stretchUpTo) {
          return SizedBox(
            height: _height,
            child: Row(
              children: [
                for (var i = 0; i < packs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PackChip(
                      pack: packs[i],
                      selected: packs[i].id == selectedId,
                      locked: !isOpen(packs[i]),
                      primary: primary,
                      stretched: true,
                      onTap: () => select(packs[i]),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _PackChip(
              pack: packs[i],
              selected: packs[i].id == selectedId,
              locked: !isOpen(packs[i]),
              primary: primary,
              stretched: false,
              onTap: () => select(packs[i]),
            ),
          ),
        );
      },
    );
  }
}

/// Предложить купить пак за монеты.
///
/// Цену показываем из каталога, а списывает её сервер по своей же записи:
/// клиентскому числу он не верит, подменить его в запросе нельзя.
Future<void> _offerPurchase(BuildContext context, MoodPack pack) async {
  final selector = context.findAncestorWidgetOfExactType<MoodPackSelector>();
  final user = selector?.user;
  if (user == null) return;

  final ru = LocaleService.instance.isRussian;
  final price = pack.unlock.price;
  final messenger = ScaffoldMessenger.of(context);

  void say(String text) => messenger.showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  if (!pack.unlock.isForSale) {
    say(ru ? 'Этот набор пока не продаётся' : 'This pack is not for sale yet');
    return;
  }
  if (user.coins < price) {
    say(ru
        ? 'Не хватает монет: нужно $price, у вас ${user.coins}'
        : 'Not enough coins: $price needed, you have ${user.coins}');
    return;
  }

  final ok = await AppDialog.confirm(
    context,
    title: pack.name,
    message: ru
        ? 'Открыть этот набор настроений навсегда за $price монет? '
            'Он появится и у партнёра.'
        : 'Unlock this mood pack forever for $price coins? '
            'Your partner gets it too.',
    confirmLabel: ru ? 'Купить' : 'Buy',
    icon: Icons.mood_rounded,
  );
  if (!ok || !context.mounted) return;

  final bought = await user.purchaseCatalogItem(kMoodPackFeatureKind, pack.id);
  if (!context.mounted) return;
  if (!bought) {
    say(ru ? 'Покупка не прошла' : 'Purchase failed');
    return;
  }

  HapticFeedback.selectionClick();
  await MoodPackService.instance.setSelectedPack(pack.id);
  selector?.onChanged?.call(pack);
}

class _PackChip extends StatelessWidget {
  final MoodPack pack;
  final bool selected;

  /// Пак виден, но закрыт: замок вместо галочки и цена вместо выбора.
  final bool locked;
  final Color primary;

  /// Таблетка занимает свою долю строки (текст по центру) или обжимается
  /// по содержимому в прокручиваемом ряду.
  final bool stretched;
  final VoidCallback onTap;

  const _PackChip({
    required this.pack,
    required this.selected,
    required this.locked,
    required this.primary,
    required this.stretched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = Theme.of(context).colorScheme;
    final gradient = pack.tileGradient;
    final fg = selected ? cs.onPrimaryContainer : t.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: MoodPackSelector._height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : t.surfaceMuted,
          borderRadius: BorderRadius.circular(MoodPackSelector._height / 2),
        ),
        child: Row(
          mainAxisSize: stretched ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Превью пака — первое настроение набора.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient != null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      )
                    : null,
                color: gradient == null ? Colors.white : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: pack.previewImage.isNotEmpty
                  ? MoodImage(pack.previewImage, fit: BoxFit.cover)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                pack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_rounded, size: 13, color: fg),
              if (pack.unlock.isForSale) ...[
                const SizedBox(width: 3),
                Text(
                  '${pack.unlock.price}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ] else if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 15, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
