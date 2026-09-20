import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/together_milestones.dart';
import 'package:love_app/models/together_track_spec.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/widget_theme_sync.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/together_track_card.dart';

/// Картинки виджета «Вместе» для глаз: build/together-preview/*.png.
///
/// Имя файла без `_test` намеренно — обычный `flutter test` его не подхватит:
/// это не проверка, а рендер для сверки с макетом.
///
///     flutter test test/goldens/together_preview.dart
void main() {
  setUpAll(() async {
    for (final family in ['Onest', 'Unbounded']) {
      final loader = FontLoader(family);
      final dir = Directory('assets/fonts');
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.toLowerCase().contains(family.toLowerCase())) continue;
        loader.addFont(f.readAsBytes().then((b) => b.buffer.asByteData()));
      }
      await loader.load();
    }
  });

  testWidgets('вместе — три размера', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    final theme = buildAppTheme(kPalettes.first, Brightness.light);
    final roles = WidgetThemeSync.rolesOf(theme.scheme!);
    final start = DateTime(2026, 5, 12);
    final today = DateTime(2026, 9, 20);
    final track = milestoneTrack(start: start, today: today);
    final s = LocaleService.current;
    final labels = trackLabels(track, s, s.dayLogDate);

    Widget card(TogetherCardSize size) => TogetherTrackCard(
          size: size,
          days: track.days,
          daysLabel: s.tgDaysTogetherCaption(track.days),
          percent: track.percent,
          roles: roles,
          startDate: 'С ${s.dayLogDate(start)} ${start.year}',
          names: 'THET1ME + JB SHARAN',
          previousTitle: labels.previousTitle,
          previousSub: labels.previousSub,
          todayTitle: labels.todayTitle,
          todaySub: labels.todaySub,
          nextTitle: labels.nextTitle,
          nextSub: labels.nextSub,
          anniversaryTitle: labels.anniversaryTitle,
          anniversarySub: labels.anniversarySub,
          myAvatar: _face('Т', roles['avatarMine']!, roles['onPrimaryContainer']!),
          partnerAvatar:
              _face('Ш', roles['avatarPartner']!, roles['onTertiaryContainer']!),
        );

    final out = Directory('build/together-preview')..createSync(recursive: true);
    for (final (name, size, w, h) in [
      ('small', TogetherCardSize.small, 160.0, 160.0),
      ('medium', TogetherCardSize.medium, 338.0, 158.0),
      ('large', TogetherCardSize.large, 338.0, 338.0),
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: ThemeData(colorScheme: theme.scheme),
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(width: w, height: h, child: card(size)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/$name.png').writeAsBytesSync(
          bytes!.buffer.asUint8List(),
        );
      });
    }

    expect(TogetherTrackSpec.dotStep, 15);
  });
}

Widget _face(String initial, Color bg, Color fg) => Container(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
