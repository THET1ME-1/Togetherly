import 'package:flutter/material.dart';

import '../../screens/plus_screen.dart';
import '../../services/locale_service.dart';
import '../../services/plus_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';

/// Плашка Togetherly+ на главной — раз в семь часов тем, кто не купил.
///
/// Нижний лист, а не экран: экран целиком выглядит как «купи, иначе не пущу», а
/// человек открывал приложение ради своей пары. Отказаться можно и кнопкой, и
/// свайпом вниз — в обоих случаях следующее напоминание будет через семь часов.
///
/// Содержимое обёрнуто в тему пары, а не полагается на ту, что стоит в дереве
/// навигатора: лист живёт ВЫШЕ экрана, и цвета ему достаются от `MaterialApp`.
/// Пока схема там собиралась заново из акцента, лист выходил цветом чужой темы
/// — серый заголовок, кнопка не в тон (жалоба 15 августа 2026).
Future<void> showPlusPromoSheet(BuildContext context) async {
  // На iPhone Togetherly+ не существует: продукта в App Store Connect нет, а
  // вести на внешнюю оплату запрещает 3.1.1. Показ и так закрыт правилом
  // `shouldShowPlusPromo` (gate там `hidden`), но лист обязан отвечать за себя
  // сам: он один переживает любые перестановки на главной, а увидеть лишнюю
  // витрину на Android невозможно — она вылезет только у ревьюера Apple.
  if (!PlusService.instance.visible) return;

  final s = LocaleService.current;
  final t = context.appTheme;
  final cs = ProfileTheme.schemeFor(t);

  final open = await showAppSheet<bool>(
    context,
    background: cs.surfaceContainerHigh,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(cs),
      child: SheetScaffold(
        title: s.plusPromoTitle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Perk(icon: Icons.mood_rounded, text: s.plusPromoPerkMoods, cs: cs),
              _Perk(
                  icon: Icons.calendar_month_rounded,
                  text: s.plusPromoPerkCycle,
                  cs: cs),
              _Perk(
                  icon: Icons.insights_rounded,
                  text: s.plusPromoPerkStats,
                  cs: cs),
              _Perk(
                  icon: Icons.widgets_rounded,
                  text: s.plusPromoPerkWidgets,
                  cs: cs),
              _Perk(
                  icon: Icons.block_rounded,
                  text: s.plusPromoPerkNoAds,
                  cs: cs),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(s.plusPromoOpen),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(s.plusPromoLater),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (open != true || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: cs)),
  );
}

/// Строка витрины: значок в тональном кружке и одна вещь словами.
class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text, required this.cs});

  final IconData icon;
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
