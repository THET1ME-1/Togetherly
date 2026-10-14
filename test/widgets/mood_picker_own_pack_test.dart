import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/models/mood_pack.dart';
import 'package:love_app/models/own_mood_pack.dart';
import 'package:love_app/screens/home/widgets/mood_picker_dialog.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/mood_pack_service.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_custom_mood_store.dart';

/// «Свои» — отдельный набор в ряду наборов (макет 14.10.2026, вариант А):
/// у остальных наборов раздела «Свои» больше нет.

const _emo = 'assets/images/new emodji';

List<CustomMood> _three() => [
      ownMood('pug', label: 'Под пледом', score: 3, image: '$_emo/Смущен.webp'),
      ownMood('boom', label: 'Взрыв мозга', score: 2, emoji: '🤯', image: '$_emo/Удивление.webp'),
      ownMood('bear', label: 'Злюка до кофе', score: 1, author: 'partner', image: '$_emo/Злость.webp'),
    ];

Widget _sheet({
  required FakeCustomMoodStore store,
  PlusGate gate = PlusGate.open,
  Brightness brightness = Brightness.light,
  double scale = 1.0,
  String current = '',
  String partnerName = 'Аня',
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
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 640,
            child: MoodPickerSheet(
              // Свежий лист на каждый pumpWidget: набор грузится в initState.
              key: UniqueKey(),
              scrollController: ScrollController(),
              currentEmoji: current,
              primary: t.primary,
              title: 'Как вы себя чувствуете?',
              subtitle: 'Партнёр увидит ваше настроение',
              onSelect: (_) {},
              onClear: current.isEmpty ? null : () async {},
              groupId: 'g1',
              partnerName: partnerName,
              showAilmentTab: true,
              store: store,
              plusGate: gate,
              myUid: 'me',
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

Finder get _ownChip => find.byKey(const Key('mood-pack-own'));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    await MoodPackService.instance.setSelectedPack(MoodPack.classic.id);
  });

  testWidgets('«Свои» стоят первой таблеткой, перед «Классическими»', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three())));
    await tester.pumpAndSettle();
    final own = tester.getTopLeft(_ownChip);
    final classic = tester.getTopLeft(find.byKey(const Key('mood-pack-classic')));
    expect(own.dx, lessThan(classic.dx));
  });

  testWidgets('в «Классических» своих настроений нет: раздел «Свои» ушёл', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three())));
    await tester.pumpAndSettle();
    final s = LocaleService.current;
    expect(find.text('Под пледом'), findsNothing);
    // «Свои» остались только подписью таблетки.
    expect(find.text(s.customMoodBand), findsOneWidget);
    expect(find.text(s.moodBandBright), findsOneWidget);
  });

  testWidgets('выбрали «Свои»: свои настроения по разделам, место в наборе, выбор запомнен', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three())));
    await tester.pumpAndSettle();
    await tester.tap(_ownChip);
    await tester.pumpAndSettle();

    final s = LocaleService.current;
    expect(find.text('Под пледом'), findsOneWidget);
    expect(find.text('Взрыв мозга'), findsOneWidget);
    expect(find.text('Злюка до кофе'), findsOneWidget);
    expect(find.text(s.moodBandEven), findsOneWidget);
    expect(find.text(s.moodBandSad), findsOneWidget);
    expect(find.text(s.moodBandHeavy), findsOneWidget);
    expect(
      find.text(trKey('customMoodSetCount').replaceAll('{n}', '3').replaceAll('{max}', '$kOwnMoodLimit')),
      findsOneWidget,
    );
    // Встроенных эмоций в своём наборе нет.
    expect(find.text(MoodOption.all.first.localizedLabel), findsNothing);
    expect(MoodPackService.instance.selectedPackId, kOwnMoodPackId);
  });

  testWidgets('выбранные «Свои» открываются сразу своими', (tester) async {
    await _size(tester, 360);
    await MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three())));
    await tester.pumpAndSettle();
    expect(find.text('Под пледом'), findsOneWidget);
  });

  testWidgets('без Плюса и без своих: пример и вход в Плюс, выбор не запоминается', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(), gate: PlusGate.locked));
    await tester.pumpAndSettle();
    await tester.tap(_ownChip);
    await tester.pumpAndSettle();
    expect(find.text(trKey('customMoodTeaserTitle')), findsOneWidget);
    expect(find.text(trKey('customMoodUnlock')), findsOneWidget);
    expect(find.text(trKey('customMoodCreate')), findsNothing);
    expect(MoodPackService.instance.selectedPackId, MoodPack.classic.id);

    // Другая таблетка возвращает обычный набор.
    await tester.tap(find.byKey(const Key('mood-pack-classic')));
    await tester.pumpAndSettle();
    expect(find.text(trKey('customMoodTeaserTitle')), findsNothing);
  });

  testWidgets('без Плюса, но с настроениями партнёра: выбирать можно, новые заводит тот, у кого Плюс', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three()), gate: PlusGate.locked));
    await tester.pumpAndSettle();
    await tester.tap(_ownChip);
    await tester.pumpAndSettle();
    expect(find.text('Под пледом'), findsOneWidget);
    expect(find.text(trKey('customMoodLockedMeta')), findsOneWidget);
    expect(MoodPackService.instance.selectedPackId, kOwnMoodPackId);
  });

  testWidgets('с Плюсом и без своих: зовём создать первое', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore()));
    await tester.pumpAndSettle();
    await tester.tap(_ownChip);
    await tester.pumpAndSettle();
    expect(find.text(trKey('customMoodEmptyTitle')), findsOneWidget);
    expect(find.text(trKey('customMoodCreate')), findsOneWidget);
  });

  testWidgets('где Плюса нет вовсе, таблетки «Свои» нет', (tester) async {
    await _size(tester, 360);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three()), gate: PlusGate.hidden));
    await tester.pumpAndSettle();
    expect(_ownChip, findsNothing);
  });

  testWidgets('удержание своего: убрать из набора', (tester) async {
    await _size(tester, 360);
    final store = FakeCustomMoodStore(_three());
    await MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
    await tester.pumpWidget(_sheet(store: store));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Под пледом'));
    await tester.pumpAndSettle();
    final s = LocaleService.current;
    await tester.tap(find.text(s.customMoodDelete));
    await tester.pumpAndSettle();
    expect(store.removed, ['pug']);
    expect(find.text('Под пледом'), findsNothing);
  });

  testWidgets('удержание чужого: убрать его может только автор', (tester) async {
    await _size(tester, 360);
    await MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three())));
    await tester.pumpAndSettle();

    // Тяжёлое стоит последним разделом, ниже края листа.
    await tester.ensureVisible(find.text('Злюка до кофе'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Злюка до кофе'));
    await tester.pumpAndSettle();
    expect(find.text(LocaleService.current.customMoodDelete), findsNothing);
    expect(find.text(trKey('customMoodOnlyAuthor').replaceAll('{name}', 'Аня')), findsOneWidget);
  });

  testWidgets('полный набор: «Новое» объясняет, а не открывает лист', (tester) async {
    await _size(tester, 360);
    final full = [for (var i = 0; i < kOwnMoodLimit; i++) ownMood('m$i', label: 'Своё $i', score: 1 + i % 5)];
    await MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
    await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(full)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own-moods-new')));
    await tester.pump();
    expect(find.text(LocaleService.current.customMoodLimitReached), findsOneWidget);
    expect(find.text(LocaleService.current.customMoodTitle), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  for (final lang in [AppLanguage.ru, AppLanguage.de]) {
    for (final b in Brightness.values) {
      testWidgets('320 точек, шрифт 1.3, ${lang.name}, ${b.name}: свой набор, пустой и пример без переполнения', (tester) async {
        LocaleService.instance.setLanguage(lang);
        await _size(tester, 320, height: 700);
        await MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
        await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(_three()), brightness: b, scale: 1.3, current: '$_emo/Смущен.webp'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('own-moods-new')), findsOneWidget);

        await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(), brightness: b, scale: 1.3));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(_sheet(store: FakeCustomMoodStore(), gate: PlusGate.locked, brightness: b, scale: 1.3));
        await tester.pumpAndSettle();
        await tester.tap(_ownChip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(trKey('customMoodUnlock')), findsOneWidget);
      });
    }
  }
}
