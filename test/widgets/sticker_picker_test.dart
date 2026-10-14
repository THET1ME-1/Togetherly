// Лист «Наклейки»: ряд наборов как в выборе настроения и сетка картинок.
// Касание по картинке отдаёт наклейку, а набор запоминается на следующий раз.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/models/own_mood_pack.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/memory/sticker_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_custom_mood_store.dart';

class _Picked {
  StickerChoice? choice;
  bool done = false;
}

const _emo = 'assets/images/new emodji';

/// Свои настроения пары: фото, эмодзи и настроение партнёра.
List<CustomMood> _own() => [
      ownMood('pug', label: 'Под пледом', image: '$_emo/Смущен.webp'),
      ownMood('boom', label: 'Взрыв мозга', emoji: '🤯', image: '$_emo/Удивление.webp'),
      ownMood('bear', label: 'Злюка до кофе', author: 'partner', image: '$_emo/Злость.webp'),
    ];

Future<_Picked> _open(
  WidgetTester tester, {
  Brightness b = Brightness.light,
  double width = 360,
  double scale = 1,
  String groupId = '',
  FakeCustomMoodStore? store,
  PlusGate gate = PlusGate.open,
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final theme = buildAppTheme(kPalettes[21], b);
  final cs = ProfileTheme.schemeFor(theme);
  final picked = _Picked();
  await tester.pumpWidget(ThemeScope(
    theme: theme,
    child: MaterialApp(
      theme: ProfileTheme.data(cs),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () async {
                    picked.choice = await showStickerPicker(
                      ctx,
                      groupId: groupId,
                      store: store,
                      plusGate: gate,
                    );
                    picked.done = true;
                  },
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'app_language': 'ru'}));

  testWidgets('наборы рядом, касание по картинке отдаёт наклейку',
      (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    final picked = await _open(tester);
    expect(find.text('Наклейки'), findsOneWidget);
    expect(find.byKey(const Key('sticker-pack-classic')), findsOneWidget);
    // Ряд наборов прокручивается вбок: «Зайка» может стоять за краем.
    final bunny = find.byKey(const Key('sticker-pack-bunny'), skipOffstage: false);
    expect(bunny, findsOneWidget);
    await tester.ensureVisible(bunny);
    await tester.pumpAndSettle();

    await tester.tap(bunny);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sticker-bunny-love')));
    await tester.pumpAndSettle();

    expect(picked.done, isTrue);
    expect(picked.choice?.image, 'assets/images/mood_packs/bunny/love.webp');
    expect(picked.choice?.pack, 'bunny');
    expect(picked.choice?.mood, 'love');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kStickerLastPackKey), 'bunny');
  });

  testWidgets('прошлый набор открывается сам', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'app_language': 'ru', kStickerLastPackKey: 'pink'});
    await _open(tester);
    expect(find.byKey(const Key('sticker-pack-pink')), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('sticker-pink-')),
        findsWidgets);
  });

  group('«Свои» настроения пары', () {
    final ownChip = find.byKey(const Key('sticker-pack-own'));

    testWidgets('стоят первыми, касание отдаёт своё настроение наклейкой',
        (tester) async {
      await LocaleService.instance.setLanguage(AppLanguage.ru);
      final picked = await _open(tester,
          groupId: 'g1', store: FakeCustomMoodStore(_own()));
      expect(ownChip, findsOneWidget);
      expect(
        tester.getTopLeft(ownChip).dx,
        lessThan(tester.getTopLeft(find.byKey(const Key('sticker-pack-classic'))).dx),
      );

      await tester.tap(ownChip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sticker-own-custom_boom')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sticker-own-custom_pug')));
      await tester.pumpAndSettle();

      expect(picked.done, isTrue);
      expect(picked.choice?.image, '$_emo/Смущен.webp');
      expect(picked.choice?.pack, kOwnMoodPackId);
      expect(picked.choice?.mood, 'custom_pug');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kStickerLastPackKey), kOwnMoodPackId);
    });

    testWidgets('настроения партнёра клеятся и без своего Плюса',
        (tester) async {
      final picked = await _open(tester,
          groupId: 'g1', store: FakeCustomMoodStore(_own()), gate: PlusGate.locked);
      await tester.tap(ownChip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sticker-own-custom_bear')));
      await tester.pumpAndSettle();
      expect(picked.choice?.mood, 'custom_bear');
    });

    testWidgets('прошлый набор «Свои» открывается сам', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'app_language': 'ru', kStickerLastPackKey: kOwnMoodPackId});
      await _open(tester, groupId: 'g1', store: FakeCustomMoodStore(_own()));
      expect(find.byKey(const Key('sticker-own-custom_pug')), findsOneWidget);
    });

    testWidgets('без пары таблетки нет', (tester) async {
      await _open(tester, store: FakeCustomMoodStore(_own()));
      expect(ownChip, findsNothing);
    });

    testWidgets('на iPhone без Плюса таблетки нет', (tester) async {
      await _open(tester,
          groupId: 'g1', store: FakeCustomMoodStore(_own()), gate: PlusGate.hidden);
      expect(ownChip, findsNothing);
    });

    testWidgets('без Плюса и без своих — пример и вход в Плюс', (tester) async {
      await _open(tester,
          groupId: 'g1', store: FakeCustomMoodStore(), gate: PlusGate.locked);
      await tester.tap(ownChip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sticker-own-unlock')), findsOneWidget);
      expect(find.byKey(const Key('own-moods-create')), findsNothing);
    });

    testWidgets('с Плюсом и без своих — «Создать настроение»', (tester) async {
      await _open(tester, groupId: 'g1', store: FakeCustomMoodStore());
      await tester.tap(ownChip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own-moods-create')), findsOneWidget);
      expect(find.byKey(const Key('sticker-own-unlock')), findsNothing);
    });
  });

  for (final b in Brightness.values) {
    for (final lang in [AppLanguage.ru, AppLanguage.de]) {
      testWidgets('320 точек, шрифт 1.3, ${lang.name}, ${b.name}',
          (tester) async {
        await LocaleService.instance.setLanguage(lang);
        addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));
        await _open(tester, b: b, width: 320, scale: 1.3);
        expect(tester.takeException(), isNull);
      });

      for (final empty in [false, true]) {
        final what = empty ? 'пример «Своих»' : '«Свои»';
        testWidgets('$what на 320 точках, шрифт 1.3, ${lang.name}, ${b.name}',
            (tester) async {
          await LocaleService.instance.setLanguage(lang);
          addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));
          await _open(tester,
              b: b,
              width: 320,
              scale: 1.3,
              groupId: 'g1',
              store: FakeCustomMoodStore(empty ? [] : _own()),
              gate: empty ? PlusGate.locked : PlusGate.open);
          await tester.tap(find.byKey(const Key('sticker-pack-own')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
