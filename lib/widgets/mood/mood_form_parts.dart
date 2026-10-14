import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../dict_strings.dart';
import '../../models/custom_mood.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../connect_expressive.dart' show M3ShapeClipper;
import '../mood_image.dart';

/// Общие детали листов своего настроения: создание и правка.

/// Цвет плитки под эмодзи: цвет шкалы поверх поверхности листа. Эмодзи
/// хранится картинкой на прозрачном фоне и без подложки висел бы в воздухе.
Color moodScoreTint(int score, ColorScheme cs, {double alpha = 0.16}) =>
    Color.alphaBlend(
      CustomMood.colorOfScore(score).withValues(alpha: alpha),
      cs.surfaceContainerHigh,
    );

/// Подпись балла 1…5 тем же словом, что на кнопках шкалы.
String moodScoreLabel(int score) {
  final s = LocaleService.current;
  return switch (CustomMood.clampScore(score)) {
    1 => s.customMoodScore1,
    2 => s.customMoodScore2,
    3 => s.customMoodScore3,
    4 => s.customMoodScore4,
    _ => s.customMoodScore5,
  };
}

/// Картинка уже заведённого настроения в мягком квадрате.
class OwnMoodPicture extends StatelessWidget {
  final CustomMood mood;
  final double size;

  /// Балл для подложки эмодзи. В листе правки он меняется вместе со шкалой.
  final int? score;

  const OwnMoodPicture({super.key, required this.mood, required this.size, this.score});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    return SizedBox(
      width: size,
      height: size,
      child: ClipPath(
        clipper: ShapeBorderClipper(
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(size * 0.34)),
        ),
        child: ColoredBox(
          color: mood.onTintedTile
              ? moodScoreTint(score ?? mood.score, cs, alpha: 0.30)
              : cs.surfaceContainerHighest,
          child: mood.imageUrl.isEmpty
              ? const SizedBox.shrink()
              : MoodImage(mood.imageUrl, fit: BoxFit.cover, width: size, height: size),
        ),
      ),
    );
  }
}

/// Поле названия: заливка без рамки, счётчик появляется к концу предела.
class MoodNameField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  static const int maxLength = 40;

  /// С какого знака показывать счётчик: раньше он только отвлекает.
  static const int counterFrom = 30;

  const MoodNameField({super.key, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final s = LocaleService.current;
    final shape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );
    return TextField(
      key: const Key('custom-mood-name'),
      controller: controller,
      onChanged: onChanged,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      style: TextStyle(fontFamily: 'Onest', fontSize: 16, fontWeight: FontWeight.w500, color: cs.onSurface),
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
          currentLength >= counterFrom
              ? Text(
                  '$currentLength/${maxLength ?? MoodNameField.maxLength}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                )
              : null,
      decoration: InputDecoration(
        labelText: s.customMoodLabelHint,
        hintText: trKey('customMoodLabelExample'),
        floatingLabelStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: shape,
        enabledBorder: shape,
        focusedBorder: shape,
      ),
    );
  }
}

/// Шкала 1…5 кружками цвета календаря: выбранный становится «печеньем» M3.
///
/// Подпись выбранного стоит под рядом, а не на каждом кружке: пять слов в
/// строку на 320 точках резались бы до «Грус…».
class MoodScoreScale extends StatelessWidget {
  final int score;
  final ValueChanged<int> onChanged;

  const MoodScoreScale({super.key, required this.score, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final s = LocaleService.current;
    final hint = TextStyle(fontFamily: 'Onest', fontSize: 12.5, color: cs.onSurfaceVariant.withValues(alpha: 0.85));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.customMoodScoreTitle,
                style: TextStyle(fontFamily: 'Onest', fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(trKey('customMoodScoreHint'), style: hint),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 5; i++) _ScoreDot(score: i, selected: score == i, onTap: () => onChanged(i)),
            ],
          ),
        ),
        // Три подписи делят строку поровну: при доле 1:2:1 края на 320 точках
        // резались до «Strahl…».
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(trKey('customMoodScaleLow'), style: hint, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: Text(
                  moodScoreLabel(score),
                  key: const Key('custom-mood-score-label'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Onest', fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
              Expanded(
                child: Text(
                  trKey('customMoodScaleHigh'),
                  style: hint,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreDot extends StatelessWidget {
  final int score;
  final bool selected;
  final VoidCallback onTap;

  const _ScoreDot({required this.score, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final color = CustomMood.colorOfScore(score);
    // Жёлтый «Светлого» слишком светлый для белой галочки.
    final mark = color.computeLuminance() > 0.5 ? const Color(0xFF3B2C00) : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: moodScoreLabel(score),
      child: GestureDetector(
        key: Key('custom-mood-score-$score'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 52,
          height: 56,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.3 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: 40,
                height: 40,
                child: ClipPath(
                  clipper: selected
                      ? M3ShapeClipper(MaterialShapes.cookie9Sided)
                      : const ShapeBorderClipper(shape: CircleBorder()),
                  child: ColoredBox(
                    color: selected ? color : Color.alphaBlend(color.withValues(alpha: 0.38), cs.surfaceContainerHighest),
                    child: selected ? Icon(Icons.check_rounded, size: 20, color: mark) : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Главная кнопка листа: пилюля 56 цвета заливки темы.
class MoodSheetButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  const MoodSheetButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    final onFill = AppThemes.onColor(t.fillColor, mode: t.brightness);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: t.fillColor,
          foregroundColor: onFill,
          disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: 'Onest', fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onSurface.withValues(alpha: 0.5)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 8)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}
