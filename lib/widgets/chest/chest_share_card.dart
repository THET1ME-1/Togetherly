import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chest.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import 'chest_frames.dart';
import 'chest_prize_image.dart';
import 'chest_rays.dart';

/// Сторона карточки: снимок ×3 даёт 1080×1920, как у сторис сосуда.
const double kChestShareWidth = 360;
const double kChestShareHeight = 640;

/// Карточка выпавшего приза для «Поделиться» (макет «Карточка приза из
/// сундука», вариант B «Лучи на всю карточку», 07.10.2026).
///
/// Лучи на всю карточку, открытый сундук с призом там, где он лёг на экране,
/// название и факты на тёмной плашке, внизу подпись Togetherly и адрес — как
/// у карточки сосуда. Углы прямые: скруглённую картинку принимают за
/// обрезанный скриншот, а скриншоты люди и делали вместо неё.
class ChestShareCard extends StatelessWidget {
  const ChestShareCard({
    super.key,
    required this.prize,
    required this.title,
    required this.tierLabel,
    required this.strongTier,
    required this.chance,
    required this.scheme,
    required this.fill,
    required this.openUrl,
  });

  /// Заливка темы (`AppTheme.fillColor`) для выделенного яруса. Контейнер
  /// схемы не годится: у рисованных тем в светлом режиме он почти белый.
  final Color fill;

  final ChestPrize prize;

  /// «Togetherly+ на 7 дней» — та же строка, что под сундуком на экране.
  final String title;
  final String tierLabel;

  /// Ярус залит цветом темы (главный и легендарный приз).
  final bool strongTier;

  /// «Шанс 1%»; пустая — без пилюли.
  final String chance;
  final ColorScheme scheme;

  /// Анимация открытия из каталога: на карточке её последний кадр. Нет файла —
  /// стоит неподвижный кадр из сборки.
  final String? openUrl;

  static const double _chest = 300;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final onInv = cs.onInverseSurface;
    final onFill = AppThemes.onColor(fill, mode: cs.brightness);
    Widget pill(String text, {required bool strong}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: strong ? fill : onInv.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text, style: AppFonts.onest(size: 12.5, weight: 600, color: strong ? onFill : onInv)),
        );

    // Картинка: системный размер шрифта на неё не влияет, иначе у человека с
    // крупным шрифтом название вылезало бы за плашку прямо в сторис.
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: kChestShareWidth,
        height: kChestShareHeight,
        // Material, а не голый ColoredBox: карточку снимают вне привычного
        // дерева, и текст без унаследованного стиля Flutter метит жёлтым
        // подчёркиванием — прямо в картинку (грабля карточки сосуда).
        child: Material(
          color: cs.secondaryContainer,
          child: Stack(
            children: [
              // Лучи расходятся из сундука, а он стоит выше середины.
              Positioned.fill(child: ChestRays(scheme: cs, animate: false, focus: const Alignment(0, -0.28))),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SizedBox.square(
                          dimension: _chest,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ChestFrames(url: openUrl, still: kChestStill, side: _chest, loop: false, showLast: true),
                              ChestPrizeFlight(prize: prize, spot: kChestPrizeRest, stage: _chest),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(22)),
                      child: Column(
                        children: [
                          Text(
                            trKey('chestShareLabel').toUpperCase(),
                            textAlign: TextAlign.center,
                            style: AppFonts.onest(
                                size: 11, weight: 700, letterSpacing: 1.1, color: onInv.withValues(alpha: 0.75)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            // Число держится за соседние слова: «на 7 дней» не
                            // рвётся на «на 7 / дней».
                            title.replaceAllMapped(RegExp(r' (\d+) '), (m) => ' ${m[1]} '),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.unbounded(size: 20, weight: 800, height: 1.15, color: onInv),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              pill(tierLabel, strong: strongTier),
                              if (chance.isNotEmpty) pill(chance, strong: false),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Togetherly',
                      style: AppFonts.unbounded(
                          size: 19, weight: 800, letterSpacing: -0.2, color: cs.onSecondaryContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'togetherly.day',
                      style: AppFonts.onest(
                          size: 10, weight: 500, color: cs.onSecondaryContainer.withValues(alpha: 0.75)),
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
