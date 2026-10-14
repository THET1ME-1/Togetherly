// Снимки набора «Свои» и листа «Новое настроение» настоящими шрифтами:
// flutter test test/goldens/custom_mood_preview.dart → build/custom-mood/.
//
// Картинки своих настроений лежат в test/fixtures/custom_mood: фото, рисунки и
// эмодзи, нарисованные в картинку, как их хранит приложение.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/models/mood_pack.dart';
import 'package:love_app/models/own_mood_pack.dart';
import 'package:love_app/screens/home/widgets/mood_picker_dialog.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/mood_pack_service.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/mood/custom_mood_sheet.dart';
import 'package:love_app/widgets/mood/own_mood_actions_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_custom_mood_store.dart';

const _fx = 'test/fixtures/custom_mood';

Future<void> _font(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Картинки из test/fixtures отдаются как ассеты сборки.
class _FixtureBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    // Синхронно: настоящий ввод-вывод внутри фальшивого времени теста
    // доезжает не всегда, и картинка оставалась пустой.
    if (key.startsWith('test/fixtures/')) return ByteData.sublistView(File(key).readAsBytesSync());
    return rootBundle.load(key);
  }
}

List<CustomMood> _set() => [
      ownMood('pug', label: 'Под пледом', score: 3, image: '$_fx/pug.webp'),
      ownMood('boom', label: 'Взрыв мозга', score: 2, emoji: '🤯', image: '$_fx/boom.webp'),
      ownMood('sleepy', label: 'Сонная булка', score: 3, author: 'partner', image: '$_fx/sleepy.webp'),
      ownMood('pizza', label: 'Хочу пиццу', score: 4, emoji: '🍕', image: '$_fx/pizza.webp'),
      ownMood('bear', label: 'Злюка до кофе', score: 1, author: 'partner', image: '$_fx/bear.webp'),
      ownMood('hug', label: 'Обними меня', score: 2, emoji: '🥺', author: 'partner', image: '$_fx/hug.webp'),
      ownMood('proud', label: 'Мы молодцы', score: 5, emoji: '🫶', image: '$_fx/proud.webp'),
      ownMood('heart', label: 'Скучаю по тебе', score: 4, author: 'partner', image: '$_fx/heart.webp'),
    ];

final _key = GlobalKey();

Widget _app({
  required int palette,
  required Brightness brightness,
  required AppLanguage lang,
  required double scale,
  required Widget home,
}) {
  final t = buildAppTheme(kPalettes[palette], brightness);
  final base = ProfileTheme.themeFor(t);
  // Эмодзи на холсте рисует системный шрифт; в тесте его подставляем сами.
  final theme = base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const ['NotoColorEmoji']));
  return RepaintBoundary(
    key: _key,
    child: DefaultAssetBundle(
      bundle: _FixtureBundle(),
      child: ThemeScope(
        theme: t,
        child: MaterialApp(
          // Новое приложение на каждый снимок: иначе лист прошлого снимка
          // остаётся открытым поверх.
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: lang.locale,
          supportedLocales: LocaleService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
}

Widget _picker(Brightness b, int palette, {required FakeCustomMoodStore store, PlusGate gate = PlusGate.open, String current = ''}) {
  final t = buildAppTheme(kPalettes[palette], b);
  // Под листом — притушенный экран, как под настоящей шторкой.
  return Scaffold(
    backgroundColor: Color.alphaBlend(
      Colors.black.withValues(alpha: 0.32),
      ProfileTheme.schemeFor(t).surface,
    ),
    body: Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: MoodPickerSheet(
          key: UniqueKey(),
          scrollController: ScrollController(),
          currentEmoji: current,
          primary: t.primary,
          title: LocaleService.current.howAreYouFeeling,
          subtitle: LocaleService.current.partnerWillSeeMood,
          onSelect: (_) {},
          onClear: current.isEmpty ? null : () async {},
          groupId: 'g1',
          partnerName: 'Аня',
          showAilmentTab: true,
          store: store,
          plusGate: gate,
          myUid: 'me',
        ),
      ),
    ),
  );
}

/// Пустой экран с невидимой кнопкой, открывающей лист: на снимке её нет.
Widget _opener(Future<Object?> Function(BuildContext) open) => Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: Opacity(
            opacity: 0,
            child: TextButton(onPressed: () => open(ctx), child: const Text('open')),
          ),
        ),
      ),
    );

Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/custom-mood').createSync(recursive: true);
    File('build/custom-mood/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await _font('NotoColorEmoji', '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  });

  Future<void> setUpCase(WidgetTester tester, double width, AppLanguage lang, {double height = 760}) async {
    LocaleService.instance.setLanguage(lang);
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  for (final (name, palette, b, width, scale, lang) in [
    ('own-coffee-light-360', 21, Brightness.light, 360.0, 1.0, AppLanguage.ru),
    ('own-coffee-dark-360', 21, Brightness.dark, 360.0, 1.0, AppLanguage.ru),
    ('own-pink-light-320-1.3-de', 0, Brightness.light, 320.0, 1.3, AppLanguage.de),
  ]) {
    testWidgets('picker $name', (tester) async {
      await setUpCase(tester, width, lang);
      await MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
      await tester.pumpWidget(_app(
        palette: palette,
        brightness: b,
        lang: lang,
        scale: scale,
        home: _picker(b, palette, store: FakeCustomMoodStore(_set()), current: '$_fx/pug.webp'),
      ));
      await tester.pumpAndSettle();
      await _shot(tester, 'picker-$name');
    });
  }

  testWidgets('picker classic', (tester) async {
    await setUpCase(tester, 360, AppLanguage.ru);
    await MoodPackService.instance.setSelectedPack(MoodPack.classic.id);
    await tester.pumpWidget(_app(
      palette: 21,
      brightness: Brightness.light,
      lang: AppLanguage.ru,
      scale: 1,
      home: _picker(Brightness.light, 21, store: FakeCustomMoodStore(_set()), current: 'assets/images/new emodji/Счастье.webp'),
    ));
    await tester.pumpAndSettle();
    await _shot(tester, 'picker-classic-coffee-light-360');
  });

  for (final (name, gate, moods) in [
    ('empty', PlusGate.open, <CustomMood>[]),
    ('teaser', PlusGate.locked, <CustomMood>[]),
    ('partner-locked', PlusGate.locked, _set().where((m) => m.authorUid == 'partner').toList()),
  ]) {
    testWidgets('picker $name', (tester) async {
      await setUpCase(tester, 360, AppLanguage.ru);
      await MoodPackService.instance.setSelectedPack(gate == PlusGate.locked && moods.isEmpty ? MoodPack.classic.id : kOwnMoodPackId);
      await tester.pumpWidget(_app(
        palette: 21,
        brightness: Brightness.light,
        lang: AppLanguage.ru,
        scale: 1,
        home: _picker(Brightness.light, 21, store: FakeCustomMoodStore(moods), gate: gate),
      ));
      await tester.pumpAndSettle();
      if (moods.isEmpty && gate == PlusGate.locked) {
        await tester.tap(find.byKey(const Key('mood-pack-own')));
        await tester.pumpAndSettle();
      }
      await _shot(tester, 'picker-$name-coffee-light-360');
    });
  }

  for (final (name, palette, b, width, scale, lang) in [
    ('coffee-light-360', 21, Brightness.light, 360.0, 1.0, AppLanguage.ru),
    ('pink-dark-320-1.3-de', 0, Brightness.dark, 320.0, 1.3, AppLanguage.de),
  ]) {
    testWidgets('sheet $name', (tester) async {
      await setUpCase(tester, width, lang);
      final photo = await tester.runAsync(() => File('$_fx/pug.webp').readAsBytes());
      Future<void> open() async {
        await tester.pumpWidget(_app(
          palette: palette,
          brightness: b,
          lang: lang,
          scale: scale,
          home: _opener((ctx) => showCustomMoodSheet(ctx, 'g1', store: FakeCustomMoodStore(), pickPhoto: () async => photo)),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await open();
      await _shot(tester, 'sheet-pick-$name');

      await tester.tap(find.byKey(const Key('custom-mood-src-emoji')));
      await tester.pumpAndSettle();
      await _shot(tester, 'sheet-grid-$name');

      await tester.tap(find.byKey(const Key('custom-mood-emoji-🤯')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('custom-mood-name')), 'Взрыв мозга');
      await tester.tap(find.byKey(const Key('custom-mood-score-2')));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _shot(tester, 'sheet-emoji-$name');

      await tester.tap(find.byKey(const Key('custom-mood-swap')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-mood-src-draw')));
      await tester.pumpAndSettle();
      final canvas = find.byKey(const Key('custom-mood-canvas'));
      final box = tester.getRect(canvas);
      Future<void> stroke(List<Offset> pts) async {
        final g = await tester.startGesture(box.topLeft + Offset(pts.first.dx * box.width, pts.first.dy * box.height));
        for (final p in pts.skip(1)) {
          await g.moveTo(box.topLeft + Offset(p.dx * box.width, p.dy * box.height));
        }
        await g.up();
      }

      // Лицо пальцем: круг, два глаза дугой, улыбка.
      await stroke([
        for (var i = 0; i <= 36; i++) Offset(0.5 + 0.32 * _cos(i / 36), 0.53 + 0.30 * _sin(i / 36)),
      ]);
      await stroke([for (var i = 0; i <= 10; i++) Offset(0.36 + 0.08 * i / 10, 0.45 - 0.05 * _sin(i / 20))]);
      await stroke([for (var i = 0; i <= 10; i++) Offset(0.56 + 0.08 * i / 10, 0.45 - 0.05 * _sin(i / 20))]);
      await tester.tap(find.byKey(const Key('custom-mood-ink-2')));
      await stroke([for (var i = 0; i <= 12; i++) Offset(0.38 + 0.24 * i / 12, 0.62 + 0.07 * _sin(i / 24))]);
      await tester.pumpAndSettle();
      await _shot(tester, 'sheet-draw-$name');

      await tester.tap(find.byKey(const Key('custom-mood-swap')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-mood-src-photo')));
      await tester.pumpAndSettle();
      await _shot(tester, 'sheet-photo-$name');
    });
  }

  testWidgets('actions and edit', (tester) async {
    await setUpCase(tester, 360, AppLanguage.ru);
    final moods = _set();
    await tester.pumpWidget(_app(
      palette: 21,
      brightness: Brightness.light,
      lang: AppLanguage.ru,
      scale: 1,
      home: _opener((ctx) => showOwnMoodActions(ctx, mood: moods.first, mine: true)),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _shot(tester, 'hold-mine-coffee-light-360');

    await tester.pumpWidget(_app(
      palette: 21,
      brightness: Brightness.light,
      lang: AppLanguage.ru,
      scale: 1,
      home: _opener((ctx) => showOwnMoodActions(ctx, mood: moods[4], mine: false, partnerName: 'Аня')),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _shot(tester, 'hold-partner-coffee-light-360');

    await tester.pumpWidget(_app(
      palette: 21,
      brightness: Brightness.light,
      lang: AppLanguage.ru,
      scale: 1,
      home: _opener((ctx) => showEditCustomMoodSheet(ctx, moods[1], store: FakeCustomMoodStore())),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _shot(tester, 'edit-coffee-light-360');
  });
}

/// Доля оборота → косинус и синус.
double _cos(double turn) => math.cos(turn * 2 * math.pi);
double _sin(double turn) => math.sin(turn * 2 * math.pi);
