import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Узор темы поверх фона: плитка повторяется по всей площади, контуры
/// красятся одним цветом из [AppTheme.bgPattern].
///
/// У темы без узора слой пустой, но место в дереве за ним остаётся: смена
/// темы не пересоздаёт соседей (тот же урок, что со слотом сезонного фона).
class ThemePatternLayer extends StatelessWidget {
  final AppTheme theme;

  const ThemePatternLayer({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final pattern = theme.bgPattern;
    if (pattern == null) return const SizedBox.shrink();
    // Узор — фон: касания идут сквозь него к ловцу пустых нажатий и кнопкам,
    // читалке экрана описывать нечего. Своя граница перерисовки: слой не
    // двигается, и прокрутка вкладок его не трогает.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Image(
            image: ExactAssetImage(pattern.asset, scale: pattern.density),
            repeat: ImageRepeat.repeat,
            // Плитка ложится своим размером: `scaleDown` по умолчанию ужал бы
            // её на узком экране, и предметы мельчали бы от телефона к
            // телефону.
            fit: BoxFit.none,
            alignment: Alignment.topLeft,
            width: double.infinity,
            height: double.infinity,
            color: pattern.tint,
            colorBlendMode: BlendMode.srcIn,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
