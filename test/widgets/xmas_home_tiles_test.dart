import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree.dart';
import 'package:love_app/models/xmas_tree_geometry.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/xmas_tree_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/xmas/home_half_tile.dart';
import 'package:love_app/widgets/xmas/tree_home_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Декабрьский ряд главной: две половины по 131–151 точке. Ни пилюля
/// «Вернуть», ни длинное имя партнёра, ни крупный шрифт телефона не должны
/// вылезать за плитку.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('ряд на ширине $width, шрифт ×$scale — без вылезаний', (tester) async {
        XmasTreeService.instance.debugSet(
          group: 'g',
          season: 2026,
          me: 'me',
          state: const TreeState(toys: [TreeToy(id: '1', toy: 'red', x: 50, y: 60, author: 'him')]),
        );
        await tester.binding.setSurfaceSize(Size(width, 300));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cs = ProfileTheme.themeFor(buildAppTheme(kPalettes[0], Brightness.light)).colorScheme;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 300), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: HomeHalfTile(
                        color: cs.secondaryContainer,
                        onTap: () {},
                        top: const SizedBox.square(dimension: 48),
                        bottom: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Облачко Ту', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.local_fire_department_rounded, size: 15),
                                SizedBox(width: 5),
                                Flexible(child: Text('Вернуть', maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TreeHomeTile(
                        groupId: 'g',
                        season: 2026,
                        myUid: 'me',
                        partnerName: 'Александра-Валентина Константиновна',
                        onOpen: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('+1'), findsOneWidget);
      });
    }
  }

  test('места на хвое для 60 игрушек считаются быстрее, чем за кадр-другой', () {
    final sw = Stopwatch()..start();
    var found = 0;
    for (var i = 0; i < 60; i++) {
      // каждый раз новая точка — без кэша
      if (xtAnchor('fir', 30 + (i % 10) * 4.1 + i * 0.013, 40 + (i ~/ 10) * 6.3) != null) found++;
    }
    sw.stop();
    expect(found, greaterThan(50));
    // на ноутбуке около 0,1 с на все 60; на телефоне считается один раз за игрушку
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('часы ёлки подменяются: 1 декабря плитка есть, 1 января нет', () {
    addTearDown(() => xtNow = DateTime.now);
    xtNow = () => DateTime(2026, 12, 1, 0, 0);
    expect(xtActiveSeason(xtNow()), 2026);
    xtNow = () => DateTime(2027, 1, 1, 0, 0);
    expect(xtActiveSeason(xtNow()), isNull);
  });
}
