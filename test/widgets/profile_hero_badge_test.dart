import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/profile/profile_hero.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/common/badge_image.dart';

import '../helpers/badge_catalog.dart';

/// Значок профиля стоит сразу за ником, до «Plus», и шапка не вылезает за
/// край даже на 320 точках с крупным шрифтом и длинным именем.
void main() {
  installTestBadges();

  for (final width in [320.0, 393.0]) {
    testWidgets('значок за ником, без переполнения на $width', (tester) async {
      tester.view.physicalSize = Size(width * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final cs = ColorScheme.fromSeed(seedColor: Colors.pink);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900), textScaler: const TextScaler.linear(1.3)),
          child: Scaffold(
            body: ProfileHero(
              cs: cs,
              uid: 'u1',
              avatarUrl: '',
              name: 'THET1ME THET1ME THET1ME',
              badge: 'Paw',
              plus: true,
              theme: AppThemes.byIndex(0),
              bannerUrl: '',
              onEdit: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final name = tester.getRect(find.text('THET1ME THET1ME THET1ME'));
      final badge = tester.getRect(find.byType(BadgeImage));
      expect(badge.left, greaterThanOrEqualTo(name.right));
      expect(badge.left - name.right, lessThan(12));
      expect(badge.right, lessThanOrEqualTo(width));
    });
  }
}
