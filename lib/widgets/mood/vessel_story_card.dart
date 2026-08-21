import 'package:flutter/material.dart';

import '../../models/mood_vessel.dart';
import '../../theme/fonts.dart';
import 'mood_vessel.dart';

/// Карточка сосуда для сторис: вертикаль 9:16, готовая уйти в соцсети.
///
/// Углы у самой картинки прямые. Скругление здесь читалось бы как обрезанный
/// скриншот: сторис показывают во весь экран, и белые уголки на чужой ленте
/// выглядят браком, а не приёмом.
/// Пропорция сторис. 1080×1920 получается снимком с pixelRatio 3.
const double kStoryWidth = 360;
const double kStoryHeight = 640;

class VesselStoryCard extends StatelessWidget {
  const VesselStoryCard({
    super.key,
    required this.days,
    required this.columns,
    required this.title,
    required this.scheme,
    required this.daysCaption,
    this.animate = false,
  });

  final List<VesselDay> days;
  final int columns;

  /// Период: «Август 2026», «Неделя 12–18 августа», «2026».
  final String title;

  final ColorScheme scheme;

  /// Подпись под числом: «дней вместе в этом сосуде». Слова приходят готовыми
  /// — карточка их не сочиняет и не склеивает.
  final String daysCaption;

  /// Кладка падает сверху. В карточке анимация не нужна: снимок делается
  /// сразу, а недолетевшие блоки попали бы в кадр на полпути.
  final bool animate;

  Color get _bg => scheme.surface;
  Color get _ink => scheme.onSurface;
  Color get _muted => scheme.onSurfaceVariant;

  int get _liveDays => days.where((d) => !d.isEmpty).length;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kStoryWidth,
      height: kStoryHeight,
      // Material, а не голый ColoredBox: карточку рисуют и вне дерева экрана
      // (снимок для сторис), а текст без унаследованного стиля Flutter метит
      // жёлтым подчёркиванием — прямо в картинку, которую человек выложит.
      child: Material(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          child: _jar(),
        ),
      ),
    );
  }

  Widget _vessel({required double height, bool frame = true}) {
    final vessel = MoodVessel(
      days: days,
      columns: columns,
      height: height,
      animate: animate,
      frame: frame,
    );
    return vessel;
  }

  Widget _brand({double size = 19, TextAlign align = TextAlign.center}) {
    return Column(
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'Togetherly',
          style: AppFonts.unbounded(
            size: size,
            weight: 800,
            color: _ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'togetherly.day',
          style: AppFonts.onest(size: 10, weight: 500, color: _muted),
        ),
      ],
    );
  }

  Widget _jar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppFonts.unbounded(size: 24, weight: 800, color: _ink),
        ),
        const SizedBox(height: 6),
        Text(
          '$_liveDays $daysCaption',
          style: AppFonts.onest(size: 12, weight: 600, color: _muted),
        ),
        const Spacer(),
        _vessel(height: 380),
        const Spacer(),
        _brand(),
      ],
    );
  }
}
