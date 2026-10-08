import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dict_strings.dart' show trKey;
import '../models/chest.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/chest/chest_prize_image.dart';

/// Приз сундука во весь экран: нажали на строку в списке шансов — открылся
/// отдельный экран, а не лист, и на нём монета, подарок или билет Плюса
/// крупно и живым. Крупный показ берёт анимацию 720 px (xl) из каталога.
class ChestPrizeScreen extends StatelessWidget {
  const ChestPrizeScreen({
    super.key,
    required this.theme,
    required this.prize,
    required this.title,
    required this.subtitle,
    required this.tier,
    required this.chance,
  });

  final AppTheme theme;
  final ChestPrize prize;
  final String title;
  final String subtitle;
  final String tier;
  final String chance;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(theme);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: cs.onSurface),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      // Крупнее ширины экрана: у анимаций прозрачное поле под
                      // искры и полёт, сам рисунок занимает около 60% файла.
                      // Поле выходит за край, рисунок — нет.
                      // У рамки поля нет: рисунок доходит до края файла, и
                      // в 1,3 ширины экрана венок вылезал за края и казался
                      // огромным и толстым (жалоба с 1.35.0+245). Рамка — с
                      // фото в натуральную пропорцию, в ширину экрана.
                      final side = prize.kind == ChestPrizeKind.frame
                          ? math.min(math.min(c.maxWidth * 0.86, c.maxHeight * 0.8), 420.0)
                          : math.min(math.min(c.maxWidth * 1.3, c.maxHeight * 1.1), 640.0);
                      return Center(
                        child: OverflowBox(
                          maxWidth: side,
                          maxHeight: side,
                          child: ChestPrizeImage(prize, side: side),
                        ),
                      );
                    },
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(cs, tier, cs.secondaryContainer, cs.onSecondaryContainer),
                    _chip(cs, trKey('chestChance').replaceAll('{p}', chance), cs.primaryContainer, cs.onPrimaryContainer),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: fg,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}
