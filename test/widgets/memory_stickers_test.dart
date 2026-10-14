// Наклейки на пинах (14.10.2026, макет «Наклейки на пинах», вариант А).
//
// Слой рисует наклейку там, где она стоит в долях блока, и может свисать за
// край; редактор над затемнённой лентой двигает её пальцем, крутит и тянет
// ручкой, «Готово» отдаёт новое место, «Отмена» — ничего.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_sticker.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/memory/sticker_editor.dart';
import 'package:love_app/widgets/memory/sticker_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _img = 'assets/images/mood_packs/bunny/love.webp';

MemorySticker _s(String id, {double x = .5, double y = .5, double size = .28}) =>
    MemorySticker(id: id, uid: 'me', image: _img, x: x, y: y, size: size);

Widget _app(Widget home, {Brightness b = Brightness.light, double scale = 1}) {
  final theme = buildAppTheme(kPalettes[21], b);
  final cs = ProfileTheme.schemeFor(theme);
  return ThemeScope(
    theme: theme,
    child: MaterialApp(
      theme: ProfileTheme.data(cs),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: home,
        ),
      ),
    ),
  );
}

void _screen(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Что вернул редактор и закрылся ли он.
class _Opened {
  StickerEditResult? result;
  bool done = false;
}

const _block = Rect.fromLTWH(28, 200, 304, 200);
const _card = Rect.fromLTWH(16, 120, 328, 360);

Future<_Opened> _open(
  WidgetTester tester, {
  bool isNew = true,
  Brightness b = Brightness.light,
  double scale = 1,
  double width = 360,
}) async {
  _screen(tester, width: width);
  final opened = _Opened();
  await tester.pumpWidget(_app(
    Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () async {
              opened.result = await placeStickerOnCard(ctx,
                  block: _block, card: _card, sticker: _s('n'), isNew: isNew);
              opened.done = true;
            },
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
    b: b,
    scale: scale,
  ));
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
  expect(find.byType(StickerEditor), findsOneWidget);
  return opened;
}

void main() {
  // Смена языка пишет выбор в настройки: без подмены тест ждёт их вечно.
  setUp(() => SharedPreferences.setMockInitialValues({'app_language': 'ru'}));

  group('слой', () {
    testWidgets('наклейка стоит в долях блока и свисает за край', (tester) async {
      _screen(tester);
      await tester.pumpWidget(_app(Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(left: 40, top: 100),
          child: SizedBox(
            width: 200,
            height: 100,
            child: StickerLayer(stickers: [_s('a', x: 1, y: 0, size: .5)]),
          ),
        ),
      )));
      final r = tester.getRect(find.byKey(const ValueKey('sticker-a')));
      // Центр в правом верхнем углу блока, сторона — половина ширины.
      expect(r.center.dx, closeTo(240, .01));
      expect(r.center.dy, closeTo(100, .01));
      expect(r.width, closeTo(100, .01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('спрятанную не рисует, касание говорит, какая', (tester) async {
      _screen(tester);
      MemorySticker? tapped;
      await tester.pumpWidget(_app(Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: StickerLayer(
              stickers: [_s('a', x: .25), _s('b', x: .75)],
              hiddenId: 'a',
              onTap: (s) => tapped = s,
            ),
          ),
        ),
      )));
      expect(find.byKey(const ValueKey('sticker-a')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sticker-b')));
      expect(tapped?.id, 'b');
    });

    testWidgets('блок сообщает о себе карточке, поставленная видна сразу',
        (tester) async {
      _screen(tester);
      final anchorKey = GlobalKey<StickerAnchorState>();
      late BuildContext inside;
      await tester.pumpWidget(_app(Scaffold(
        body: StickerCardScope(
          child: Builder(builder: (ctx) {
            inside = ctx;
            return Column(children: [
              const SizedBox(height: 50),
              StickerAnchor(
                key: anchorKey,
                stickers: [_s('a')],
                child: const SizedBox(width: 300, height: 200),
              ),
            ]);
          }),
        ),
      )));
      final card = StickerCardScope.maybeOf(inside);
      expect(card?.anchor, same(anchorKey.currentState));
      expect(card!.anchor!.globalRect!.size, const Size(300, 200));

      final before = tester.getRect(find.byKey(const ValueKey('sticker-a')));
      anchorKey.currentState!.expectPlaced(_s('a', x: .9));
      await tester.pump();
      final after = tester.getRect(find.byKey(const ValueKey('sticker-a')));
      expect(after.center.dx, greaterThan(before.center.dx + 100));

      anchorKey.currentState!.expectRemoved('a');
      await tester.pump();
      expect(find.byKey(const ValueKey('sticker-a')), findsNothing);
      // Запись так и не пришла — через три секунды верим записи.
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('sticker-a')), findsOneWidget);
    });
  });

  group('редактор', () {
    // Центр новой наклейки (180, 300), сторона .28 × 304; ручки на 5 точек
    // за углами.
    const side = .28 * 304;
    const centre = Offset(180, 300);
    final grab = centre + const Offset(side / 2 + 5, side / 2 + 5);
    final cross = centre - const Offset(side / 2 + 5, side / 2 + 5);

    testWidgets('пальцем двигается, «Готово» отдаёт новое место', (tester) async {
      final opened = await _open(tester);
      final g = await tester.startGesture(const Offset(180, 650));
      await g.moveBy(const Offset(20, 0));
      await g.moveBy(const Offset(40, -10));
      await g.up();
      await tester.pump();
      await tester.tap(find.byKey(const Key('sticker-done')));
      await tester.pumpAndSettle();
      expect(opened.done, isTrue);
      final s = opened.result!.sticker!;
      expect(s.x, closeTo(.5 + 60 / 304, .01));
      expect(s.y, closeTo(.5 - 10 / 200, .01));
      expect(s.size, closeTo(.28, 1e-9));
    });

    testWidgets('ручка в углу тянет и крутит вокруг центра', (tester) async {
      final opened = await _open(tester);
      final g = await tester.startGesture(grab);
      await g.moveBy(const Offset(15, 15));
      await g.moveBy(const Offset(15, 15));
      await g.up();
      await tester.pump();
      await tester.tap(find.byKey(const Key('sticker-done')));
      await tester.pumpAndSettle();
      final s = opened.result!.sticker!;
      expect(s.size, greaterThan(.4));
      expect(s.angle.abs(), lessThan(.02));
      expect(s.x, .5);
    });

    testWidgets('за край блока центр не уходит', (tester) async {
      final opened = await _open(tester);
      final g = await tester.startGesture(const Offset(180, 650));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(60, 0));
      }
      await g.up();
      await tester.pump();
      await tester.tap(find.byKey(const Key('sticker-done')));
      await tester.pumpAndSettle();
      expect(opened.result!.sticker!.x, 1.0);
    });

    testWidgets('«Отмена» ничего не меняет', (tester) async {
      final opened = await _open(tester);
      await tester.tap(find.byKey(const Key('sticker-cancel')));
      await tester.pumpAndSettle();
      expect(opened.done, isTrue);
      expect(opened.result, isNull);
    });

    testWidgets('крестик у новой отменяет', (tester) async {
      final opened = await _open(tester);
      await tester.tapAt(cross);
      await tester.pumpAndSettle();
      expect(opened.done, isTrue);
      expect(opened.result, isNull);
    });

    testWidgets('крестик у наклеенной убирает её', (tester) async {
      final opened = await _open(tester, isNew: false);
      await tester.tapAt(cross);
      await tester.pumpAndSettle();
      expect(opened.result?.removed, isTrue);
    });

    for (final b in Brightness.values) {
      for (final lang in [AppLanguage.ru, AppLanguage.de]) {
        testWidgets('320 точек, шрифт 1.3, ${lang.name}, ${b.name}',
            (tester) async {
          await LocaleService.instance.setLanguage(lang);
          addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));
          await _open(tester, b: b, scale: 1.3, width: 320);
          expect(tester.takeException(), isNull);
          final cancel = tester.getRect(find.byKey(const Key('sticker-cancel')));
          final done = tester.getRect(find.byKey(const Key('sticker-done')));
          expect(cancel.right, lessThan(done.left));
          expect(done.right, lessThanOrEqualTo(320 - 16 + .01));
        });
      }
    }
  });
}
