import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree.dart';
import 'package:love_app/screens/xmas/xmas_tree_screen.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/xmas_tree_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/xmas/tree_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Касания по ёлке: игрушку берут в листе, вешают касанием по ветке, мимо хвои
/// не вешают, без игрушки в руке подсказывают взять её. Сервера в тесте нет,
/// поэтому повешенная игрушка откатывается со строкой «Не получилось» — так
/// видно, что запрос ушёл.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    CatalogService.instance.debugSetToys([
      XtToy.fromCatalog({'price': 30, 'sort': 1, 'data': {'key': 'red', 'cat': 'balls', 'src': 'coins', 'pick': 'xt_pick_red', 'tree': 'xt3toy_red', 'name': {'ru': 'Красный шар'}}})!,
    ]);
    XmasTreeService.instance.debugSet(
      group: 'g',
      season: 2026,
      me: 'me',
      state: const TreeState(owned: {'red': 2}, seasons: [2026]),
    );
  });

  Future<Rect> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.themeFor(theme),
      home: XmasTreeScreen(theme: theme, groupId: 'g', season: 2026, partnerName: 'Дима'),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    return tester.getRect(find.byType(TreeStage));
  }

  Offset at(Rect r, double ux, double uy) => Offset(r.left + (ux + 8) / kXtSpan * r.width, r.top + (uy + 8) / kXtSpan * r.height);

  testWidgets('без игрушки в руке касание по ветке подсказывает взять игрушку', (tester) async {
    final r = await open(tester);
    await tester.tapAt(at(r, 50, 62));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Сначала возьмите игрушку в «Игрушках» внизу.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('игрушку из листа: мимо хвои не вешается, по ветке — уходит на сервер', (tester) async {
    final r = await open(tester);
    // снег и огонь крутятся без конца, поэтому ждём явно, а не до тишины
    await tester.tap(find.text('Игрушки').last);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Красный шар'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Красный шар: нажмите на ветку или перетащите'), findsOneWidget);

    await tester.tapAt(at(r, 2, 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Сюда не повесить: нужна ветка.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    await tester.tapAt(at(r, 50, 62));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не получилось. Проверь связь и попробуй ещё раз.'), findsOneWidget);
    expect(XmasTreeService.instance.state!.toys, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });
}
