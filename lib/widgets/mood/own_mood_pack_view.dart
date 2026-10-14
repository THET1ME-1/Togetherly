import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import 'mood_canvas.dart';
import 'mood_form_parts.dart';

/// Части набора «Свои» в листе выбора настроения (макет 14.10.2026, вариант А
/// «Как все наборы»): строка с местом в наборе и кнопкой «Новое», пустой
/// набор и пример для тех, у кого нет Плюса.

/// Строка над своими настроениями: сколько места занято и кнопка «Новое».
class OwnMoodsBar extends StatelessWidget {
  final String meta;

  /// Без Плюса кнопка ведёт на его экран и носит замок.
  final bool locked;

  /// Набор полон: кнопка тише и объясняет, что сначала надо убрать одно.
  final bool full;
  final String newLabel;
  final VoidCallback onNew;

  const OwnMoodsBar({
    super.key,
    required this.meta,
    required this.locked,
    required this.full,
    required this.newLabel,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    final quiet = locked || full;
    final bg = quiet ? cs.surfaceContainerHighest : t.fillColor;
    final fg = quiet ? cs.onSurface : AppThemes.onColor(t.fillColor, mode: t.brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              meta,
              style: TextStyle(fontFamily: 'Onest', fontSize: 13, fontWeight: FontWeight.w600, height: 1.3, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            key: const Key('own-moods-new'),
            color: bg,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onNew,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(locked ? Icons.lock_rounded : Icons.add_rounded, size: locked ? 16 : 20, color: fg),
                      const SizedBox(width: 6),
                      Text(newLabel, style: TextStyle(fontFamily: 'Onest', fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Пустой набор «Свои»: веер из трёх примеров, заголовок и текст.
///
/// [onCreate] есть у того, у кого Плюс: под текстом встаёт «Создать
/// настроение». Без Плюса это пример, а вход в Плюс стоит внизу листа, как у
/// закрытого платного набора.
class OwnMoodsEmpty extends StatelessWidget {
  final String title;
  final String text;
  final VoidCallback? onCreate;

  const OwnMoodsEmpty({super.key, required this.title, required this.text, this.onCreate});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 6),
      child: Column(
        children: [
          const OwnMoodsFan(),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.25,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Onest', fontSize: 14, height: 1.45, color: cs.onSurfaceVariant),
            ),
          ),
          if (onCreate != null) ...[
            const SizedBox(height: 20),
            IntrinsicWidth(
              child: MoodSheetButton(
                key: const Key('own-moods-create'),
                label: trKey('customMoodCreate'),
                icon: Icons.add_rounded,
                onPressed: onCreate,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Веер из трёх плиток: эмодзи, фото, рисунок — три способа завести своё.
class OwnMoodsFan extends StatelessWidget {
  const OwnMoodsFan({super.key});

  static const double _tile = 88;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    Widget tile(Widget child, Color color) => SizedBox(
          width: _tile,
          height: _tile,
          child: ClipPath(
            clipper: ShapeBorderClipper(
              shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(_tile * 0.34)),
            ),
            child: ColoredBox(color: color, child: child),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        width: 236,
        height: 112,
        child: Stack(
          children: [
            Positioned(
              left: 6,
              top: 10,
              child: Transform.rotate(
                angle: -9 * math.pi / 180,
                child: tile(
                  Center(
                    child: MediaQuery.withNoTextScaling(
                      child: const Text('🤯', style: TextStyle(fontSize: 50, height: 1)),
                    ),
                  ),
                  moodScoreTint(2, cs, alpha: 0.30),
                ),
              ),
            ),
            Positioned(
              left: 142,
              top: 10,
              child: Transform.rotate(
                angle: 9 * math.pi / 180,
                child: tile(MoodStrokesView(strokes: sleepyDoodle()), Colors.white),
              ),
            ),
            Positioned(
              left: 74,
              top: 2,
              child: tile(
                Icon(Icons.photo_rounded, size: 44, color: cs.onTertiaryContainer),
                cs.tertiaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Рисунок-пример в веере: сонная булочка, нарисованная «пальцем».
List<MoodStroke> sleepyDoodle() {
  const ink = Color(0xFF1F2430);
  const pink = Color(0xFFF06EAF);
  const sky = Color(0xFF62B8E8);
  final head = <Offset>[
    for (var i = 0; i <= 380; i++)
      () {
        final t = i / 360 * 2 * math.pi - 0.4;
        final r = 0.34 + 0.017 * math.sin(3 * t) + 0.008 * math.sin(7 * t);
        return Offset(0.5 + r * math.cos(t), 0.55 + r * 0.92 * math.sin(t));
      }(),
  ];
  List<Offset> arc(double cx) => [
        for (var k = 0; k <= 30; k++) Offset(cx + 0.066 * math.cos(math.pi * k / 30), 0.523 + 0.035 * math.sin(math.pi * k / 30)),
      ];
  final mouth = [
    for (var k = 0; k <= 40; k++) Offset(0.5 + 0.027 * math.cos(2 * math.pi * k / 40), 0.703 + 0.031 * math.sin(2 * math.pi * k / 40)),
  ];
  MoodStroke zed(double x, double y, double k) => MoodStroke(
        points: [Offset(x, y), Offset(x + 0.078 * k, y), Offset(x, y + 0.078 * k), Offset(x + 0.078 * k, y + 0.078 * k)],
        color: sky,
        width: 0.02 * k + 0.006,
      );
  return [
    MoodStroke(points: head, color: ink, width: 0.03),
    MoodStroke(points: arc(0.38), color: ink, width: 0.026),
    MoodStroke(points: arc(0.62), color: ink, width: 0.026),
    MoodStroke(points: const [Offset(0.31, 0.655), Offset(0.35, 0.655)], color: pink, width: 0.065),
    MoodStroke(points: const [Offset(0.65, 0.655), Offset(0.69, 0.655)], color: pink, width: 0.065),
    MoodStroke(points: mouth, color: ink, width: 0.022),
    zed(0.70, 0.14, 1),
    zed(0.82, 0.045, 0.7),
  ];
}
