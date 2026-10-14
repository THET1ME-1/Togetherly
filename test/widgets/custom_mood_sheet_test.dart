import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/mood/custom_mood_sheet.dart';
import 'package:love_app/widgets/mood/mood_canvas.dart';
import 'package:love_app/widgets/mood/own_mood_actions_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_custom_mood_store.dart';

/// Лист «Новое настроение» (холст, вариант Б из макета 14.10.2026), правка
/// своего настроения и действия по удержанию.

Object? _result;

Widget _app({
  required Future<Object?> Function(BuildContext) open,
  Brightness brightness = Brightness.light,
  double scale = 1.0,
}) {
  final t = buildAppTheme(kPalettes[21], brightness);
  return ThemeScope(
    theme: t,
    child: MaterialApp(
      theme: ProfileTheme.themeFor(t),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => _result = await open(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _size(WidgetTester tester, double width, {double height = 760}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.descendant(of: find.byKey(const Key('custom-mood-save')), matching: find.byType(FilledButton)));

Future<void> _tapSave(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('custom-mood-save')));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    _result = null;
  });

  group('новое настроение', () {
    testWidgets('добавить можно, когда есть и картинка, и название', (tester) async {
      await _size(tester, 360);
      final store = FakeCustomMoodStore();
      await tester.pumpWidget(_app(open: (ctx) => showCustomMoodSheet(ctx, 'g1', store: store)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final s = LocaleService.current;
      expect(find.text(s.customMoodTitle), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('custom-mood-src-emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-mood-emoji-🤯')));
      await tester.pumpAndSettle();
      // Картинка есть, названия нет — добавлять ещё нечего.
      expect(_saveButton(tester).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('custom-mood-name')), 'Взрыв мозга');
      await tester.pump();
      expect(_saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('custom-mood-score-2')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('custom-mood-score-label'))).data,
        s.customMoodScore2,
      );

      await _tapSave(tester);
      expect(store.created, isNotNull);
      expect(store.created!.label, 'Взрыв мозга');
      expect(store.created!.score, 2);
      expect(store.created!.emoji, '🤯');
      expect(store.created!.png, isNotEmpty);
      expect(_result, isTrue);
    });

    testWidgets('«Сменить» возвращает к выбору источника и снимает картинку', (tester) async {
      await _size(tester, 360);
      final png = await tester.runAsync(() => renderStrokesPng([
            MoodStroke(points: const [Offset(0.2, 0.2), Offset(0.8, 0.8)], color: const Color(0xFF1F2430), width: 0.1),
          ]));
      final store = FakeCustomMoodStore();
      await tester.pumpWidget(_app(
        open: (ctx) => showCustomMoodSheet(ctx, 'g1', store: store, pickPhoto: () async => png),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('custom-mood-name')), 'Под пледом');
      await tester.tap(find.byKey(const Key('custom-mood-src-photo')));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      expect(_saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('custom-mood-swap')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-mood-src-photo')), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);
    });

    testWidgets('рисунок рисуется прямо на холсте и уходит без эмодзи', (tester) async {
      await _size(tester, 360);
      final store = FakeCustomMoodStore();
      await tester.pumpWidget(_app(open: (ctx) => showCustomMoodSheet(ctx, 'g1', store: store)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('custom-mood-src-draw')));
      await tester.pumpAndSettle();
      final undo = find.byKey(const Key('custom-mood-undo'));
      expect(tester.widget<IconButton>(undo).onPressed, isNull);

      final canvas = find.byKey(const Key('custom-mood-canvas'));
      await tester.drag(canvas, const Offset(80, 40));
      await tester.pump();
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);

      await tester.enterText(find.byKey(const Key('custom-mood-name')), 'Сонная булка');
      await tester.pump();
      await _tapSave(tester);
      expect(store.created!.emoji, '');
      // PNG начинается с подписи \x89PNG.
      expect(store.created!.png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    testWidgets('вертикальный штрих рисует, а не прокручивает лист', (tester) async {
      // Холст стоит в прокрутке листа: без своего перехвата вертикальное
      // движение забирала прокрутка, и лист уезжал вместо линии.
      await _size(tester, 320, height: 640);
      await tester.pumpWidget(_app(
        open: (ctx) => showCustomMoodSheet(ctx, 'g1', store: FakeCustomMoodStore()),
        scale: 1.3,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-mood-src-draw')));
      await tester.pumpAndSettle();

      final canvas = find.byKey(const Key('custom-mood-canvas'));
      final before = tester.getTopLeft(canvas);
      await tester.dragFrom(tester.getCenter(canvas) - const Offset(0, 60), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(canvas), before);
      expect(tester.widget<IconButton>(find.byKey(const Key('custom-mood-undo'))).onPressed, isNotNull);
    });

    testWidgets('отказ сервера виден в листе, а не уезжает под него', (tester) async {
      await _size(tester, 360);
      final store = FakeCustomMoodStore()..failNext = true;
      await tester.pumpWidget(_app(open: (ctx) => showCustomMoodSheet(ctx, 'g1', store: store)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-mood-src-emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-mood-emoji-🍕')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('custom-mood-name')), 'Хочу пиццу');
      await tester.pump();
      await _tapSave(tester);
      expect(find.text(LocaleService.current.customMoodFailed), findsOneWidget);
      expect(_result, isNull);
    });

    for (final lang in [AppLanguage.ru, AppLanguage.de]) {
      for (final b in Brightness.values) {
        testWidgets('320 точек, шрифт 1.3, ${lang.name}, ${b.name}: ничего не вылезает', (tester) async {
          LocaleService.instance.setLanguage(lang);
          await _size(tester, 320, height: 700);
          await tester.pumpWidget(_app(
            open: (ctx) => showCustomMoodSheet(ctx, 'g1', store: FakeCustomMoodStore()),
            brightness: b,
            scale: 1.3,
          ));
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(const Key('custom-mood-src-emoji')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(trKey('customMoodOwnKeyboard')), findsOneWidget);

          await tester.tap(find.byKey(const Key('custom-mood-swap')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('custom-mood-src-draw')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('custom-mood-eraser')), findsOneWidget);
        });
      }
    }
  });

  group('правка своего настроения', () {
    testWidgets('сохраняются название и балл, кнопка ждёт перемен', (tester) async {
      await _size(tester, 360);
      final store = FakeCustomMoodStore();
      final mood = ownMood('pug', label: 'Под пледом', score: 3);
      await tester.pumpWidget(_app(open: (ctx) => showEditCustomMoodSheet(ctx, mood, store: store)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(trKey('customMoodEditTitle')), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('custom-mood-score-4')));
      await tester.pump();
      expect(_saveButton(tester).onPressed, isNotNull);
      await tester.enterText(find.byKey(const Key('custom-mood-name')), 'Под одеялом');
      await tester.pump();

      await _tapSave(tester);
      expect(store.renamed, (recordId: 'pug', label: 'Под одеялом', score: 4));
      expect(_result, isTrue);
    });

    testWidgets('пустое название не сохранить', (tester) async {
      await _size(tester, 360);
      final mood = ownMood('pug', label: 'Под пледом');
      await tester.pumpWidget(_app(open: (ctx) => showEditCustomMoodSheet(ctx, mood, store: FakeCustomMoodStore())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('custom-mood-name')), '   ');
      await tester.pump();
      expect(_saveButton(tester).onPressed, isNull);
    });
  });

  group('удержание своего настроения', () {
    testWidgets('своё можно изменить или убрать', (tester) async {
      await _size(tester, 360);
      final mood = ownMood('pug', label: 'Под пледом');
      await tester.pumpWidget(_app(open: (ctx) => showOwnMoodActions(ctx, mood: mood, mine: true)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final s = LocaleService.current;
      expect(find.text(trKey('customMoodEdit')), findsOneWidget);
      expect(find.text(s.customMoodDeleteHint), findsOneWidget);
      await tester.tap(find.text(s.customMoodDelete));
      await tester.pumpAndSettle();
      expect(_result, OwnMoodAction.remove);
    });

    testWidgets('чужое объясняет, кто может его убрать, и кнопок правки нет', (tester) async {
      await _size(tester, 360);
      final mood = ownMood('bear', label: 'Злюка до кофе', author: 'partner');
      await tester.pumpWidget(_app(
        open: (ctx) => showOwnMoodActions(ctx, mood: mood, mine: false, partnerName: 'Аня'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final s = LocaleService.current;
      expect(find.text(s.customMoodDelete), findsNothing);
      expect(find.text(trKey('customMoodEdit')), findsNothing);
      expect(find.text(trKey('customMoodOnlyAuthor').replaceAll('{name}', 'Аня')), findsOneWidget);
      await tester.tap(find.text(s.gotIt));
      await tester.pumpAndSettle();
      expect(_result, isNull);
    });

    testWidgets('без имени партнёра фраза обходится без него', (tester) async {
      await _size(tester, 360);
      final mood = ownMood('bear', author: 'partner');
      await tester.pumpWidget(_app(open: (ctx) => showOwnMoodActions(ctx, mood: mood, mine: false)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(trKey('customMoodOnlyAuthorAnon')), findsOneWidget);
    });
  });
}
