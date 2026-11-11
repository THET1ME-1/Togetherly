// Панель поиска и фильтров над каталогом виджетов (11.11.2026).
//
// Владелец: «Сделай на странице виджетов поиск, фильтрацию, сортировку…
// Платные бесплатные, людям неудобно». Правила выдачи проверяет
// widget_catalog_query_test.dart, здесь — сама панель и её связь с экраном.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_catalog_query.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/widget_catalog/catalog_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  Future<List<CatalogQuery>> pumpToolbar(
    WidgetTester tester, {
    CatalogQuery query = const CatalogQuery(),
    bool showPlus = true,
    int onScreen = 0,
    Size size = const Size(412, 915),
    double textScale = 1,
  }) async {
    final changes = <CatalogQuery>[];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    var current = query;
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(20),
            child: CatalogToolbar(
              theme: t,
              query: current,
              showPlus: showPlus,
              onScreenCount: onScreen,
              onChanged: (next) {
                changes.add(next);
                setState(() => current = next);
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return changes;
  }

  // Чипы лежат в ленте, которую листают вбок: дальний сперва прокручиваем.
  Future<void> tapChip(WidgetTester tester, String text) async {
    final chip = find.text(text);
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
  }

  testWidgets('строка поиска отдаёт запрос, крестик его стирает', (tester) async {
    final changes = await pumpToolbar(tester);
    expect(find.text('Найти виджет'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'фото');
    await tester.pump();
    expect(changes.last.text, 'фото');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(changes.last.text, '');
    expect(find.text('Найти виджет'), findsOneWidget);
  });

  testWidgets('«Бесплатные» и «С Togetherly+» переключают цену, повтор снимает', (tester) async {
    final changes = await pumpToolbar(tester);

    await tapChip(tester, 'Бесплатные');
    expect(changes.last.price, CatalogPrice.free);

    await tapChip(tester, 'С Togetherly+');
    expect(changes.last.price, CatalogPrice.plus);

    await tapChip(tester, 'С Togetherly+');
    expect(changes.last.price, CatalogPrice.all);
  });

  testWidgets('без платных виджетов чипа Togetherly+ нет', (tester) async {
    await pumpToolbar(tester, showPlus: false);
    expect(find.text('С Togetherly+'), findsNothing);
    expect(find.text('Бесплатные'), findsOneWidget);
  });

  testWidgets('«На столе» с числом появляется, только когда виджеты стоят', (tester) async {
    await pumpToolbar(tester);
    expect(find.textContaining('На столе'), findsNothing);

    final changes = await pumpToolbar(tester, onScreen: 3);
    expect(find.text('На столе · 3'), findsOneWidget);
    await tapChip(tester, 'На столе · 3');
    expect(changes.last.onlyOnScreen, isTrue);
  });

  testWidgets('«Все» снимает и цену, и «На столе»', (tester) async {
    final changes = await pumpToolbar(
      tester,
      query: const CatalogQuery(price: CatalogPrice.plus, onlyOnScreen: true),
      onScreen: 2,
    );
    await tapChip(tester, 'Все');
    expect(changes.last.price, CatalogPrice.all);
    expect(changes.last.onlyOnScreen, isFalse);
  });

  testWidgets('порядок выбирается листом снизу', (tester) async {
    final changes = await pumpToolbar(tester);
    expect(find.text('По разделам'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('catalog-sort')));
    await tester.pumpAndSettle();
    expect(find.text('Порядок'), findsOneWidget);
    expect(find.text('Сначала новые'), findsOneWidget);

    await tester.tap(find.text('Сначала новые'));
    await tester.pumpAndSettle();
    expect(changes.last.sort, CatalogSort.newest);
    expect(find.text('Сначала новые'), findsOneWidget, reason: 'чип не показывает выбранный порядок');
  });

  testWidgets('сброс снаружи стирает текст в поле', (tester) async {
    await pumpToolbar(tester, query: const CatalogQuery(text: 'заметка'));
    expect(find.text('заметка'), findsOneWidget);

    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: Scaffold(
        body: CatalogToolbar(
          theme: t,
          query: const CatalogQuery(),
          showPlus: true,
          onScreenCount: 0,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('заметка'), findsNothing);
  });

  for (final lang in [AppLanguage.ru, AppLanguage.de, AppLanguage.uk, AppLanguage.pt]) {
    testWidgets('320 точек, шрифт 1,3, ${lang.name}: панель не вылезает', (tester) async {
      LocaleService.instance.setLanguage(lang);
      await pumpToolbar(
        tester,
        onScreen: 4,
        query: const CatalogQuery(sort: CatalogSort.newest),
        size: const Size(320, 800),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('catalog-search')), findsOneWidget);
    });
  }

  group('связка с экраном каталога', () {
    final screen = File('lib/screens/widget_screen.dart').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final start = screen.indexOf('List<_CatalogCard> _catalogCards(');
    final body = screen.substring(start, screen.indexOf('\n  }\n', start));

    // По этим именам «На столе» узнаёт виджет. Опечатка — и стоящий виджет
    // молча выпадает из фильтра.
    test('каждый провайдер в каталоге есть в манифесте', () {
      final names = RegExp(r"'([A-Za-z0-9]+Provider)'").allMatches(body).map((m) => m.group(1)!).toSet();
      expect(names.length, greaterThan(20), reason: 'список провайдеров пропал из каталога');
      for (final name in names) {
        expect(manifest.contains('.$name"'), isTrue, reason: 'нет приёмника $name');
      }
    });

    test('все карточки каталога описаны для поиска, по одной на виджет', () {
      final ids = RegExp(r"card\('([a-z_]+)'").allMatches(body).map((m) => m.group(1)!).toList();
      expect(ids.toSet().length, ids.length, reason: 'один id у двух карточек');
      for (final id in [
        'pair', 'together', 'miss', 'map', 'relationship_stats', 'mascot', 'doing', 'canvas',
        'days_counter', 'streak', 'timer', 'petal_timer', 'countdown', 'year_ring', 'year_grid',
        'photo_day_self', 'photo_day_partner', 'photo_grid', 'mood', 'mood_tiles', 'lock_mood',
        'note', 'note_paper',
      ]) {
        expect(ids, contains(id), reason: 'карточка $id не попадает в поиск');
      }
    });

    test('платные карточки помечены для фильтра цены', () {
      for (final id in ['together', 'miss', 'countdown', 'year_ring', 'year_grid', 'mood_tiles', 'note', 'note_paper']) {
        final at = body.indexOf("card('$id'");
        final next = body.indexOf('card(', at + 5);
        final chunk = body.substring(at, next < 0 ? body.length : next);
        expect(chunk, contains('plus: true'), reason: '$id не помечен как Togetherly+');
      }
    });

    test('без запроса каталог прежний, с запросом — выдача', () {
      expect(screen, contains('if (filtering) ..._catalogResults(cards) else ..._sections(cards, isPaired)'));
    });
  });
}
