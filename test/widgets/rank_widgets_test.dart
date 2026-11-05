// Звания за часы: чип в шапке профиля, лист званий и экран нового звания
// без переполнений на узких телефонах и крупном шрифте, в обеих темах
// (план 2026-11-05-ranks-by-hours, задача 5). Эмблемы из каталога в тесте
// не приходят — место под них держится пустым квадратом.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/rank.dart';
import 'package:love_app/models/rank_art.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/rank/new_rank_dialog.dart';
import 'package:love_app/widgets/rank/rank_chip.dart';
import 'package:love_app/widgets/rank/rank_emblem.dart';
import 'package:love_app/widgets/rank/ranks_sheet.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  Future<void> pump(
    WidgetTester t,
    Widget child, {
    required double width,
    required Brightness b,
    double scale = 1.3,
  }) async {
    t.view.physicalSize = Size(width * 3, 760 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final cs = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF7E8B),
      brightness: b,
    );
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: cs),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 760),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
    await t.pump();
  }

  ColorScheme scheme(Brightness b) =>
      ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B), brightness: b);

  for (final width in [320.0, 360.0]) {
    for (final b in Brightness.values) {
      testWidgets(
        'чип звания помещается под именем: ${width.toInt()} dp, ${b.name}',
        (t) async {
          await pump(
            t,
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width - 138,
                child: RankChip(
                  cs: scheme(b),
                  seconds: 9 * 3600 + 15 * 60,
                  hours: kRankHours,
                ),
              ),
            ),
            width: width,
            b: b,
          );
          expect(t.takeException(), isNull);
          expect(find.textContaining('Свидания'), findsOneWidget);
        },
      );

      testWidgets(
        'лист званий: 14 ступеней, без переполнений: ${width.toInt()} dp, ${b.name}',
        (t) async {
          await pump(
            t,
            RanksSheet(cs: scheme(b), seconds: 2 * 3600, hours: kRankHours),
            width: width,
            b: b,
          );
          expect(t.takeException(), isNull);
          expect(find.text('Сейчас'), findsOneWidget);
          await t.drag(find.byType(ListView), const Offset(0, -3000));
          await t.pump();
          expect(t.takeException(), isNull);
          expect(find.text('Навсегда'), findsWidgets);
        },
      );

      testWidgets('экран нового звания: ${width.toInt()} dp, ${b.name}', (
        t,
      ) async {
        await pump(
          t,
          const NewRankDialog(rank: 12, seconds: 251 * 3600),
          width: width,
          b: b,
        );
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
        expect(find.text('Звёздная пара'), findsOneWidget);
      });
    }
  }

  test('часы коротко', () {
    expect(hourRankHours(40 * 60), '40 мин');
    expect(hourRankHours(3 * 3600 + 20 * 60), '3 ч 20 мин');
    expect(hourRankHours(130 * 3600 + 5 * 60), '130 ч');
  });

  test(
    'каталог: записи вида rank становятся эмблемами, кривые — пропускаются',
    () {
      CatalogService.instance.debugApply([
        {
          'id': 'rank_3',
          'kind': 'rank',
          'enabled': true,
          'min_app': '',
          'data': {
            'index': 3,
            'files': {
              'sm': 'https://x/sm.webp',
              'lg': 'https://x/lg.webp',
              'still': 'https://x/still.png',
            },
          },
        },
        {
          'id': 'rank_4',
          'kind': 'rank',
          'enabled': true,
          'min_app': '',
          'data': {'index': 4, 'files': {}},
        },
        {
          'id': 'rank_5',
          'kind': 'rank',
          'enabled': false,
          'min_app': '',
          'data': {
            'index': 5,
            'files': {'sm': 'https://x/sm.webp'},
          },
        },
      ]);
      final art = CatalogService.instance.rankArt(3);
      expect(art?.urlFor(26), 'https://x/sm.webp');
      expect(art?.urlFor(104), 'https://x/lg.webp');
      expect(art?.urlFor(58, animated: false), 'https://x/still.png');
      expect(CatalogService.instance.rankArt(4), isNull);
      expect(CatalogService.instance.rankArt(5), isNull);
      CatalogService.instance.debugSetRanks(const <RankArt>[]);
    },
  );
}
