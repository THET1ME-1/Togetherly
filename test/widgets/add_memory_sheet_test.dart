// Лист «Добавить воспоминание», направление «Главное и полка» (19.09.2026).
//
// Прежний лист: шесть одинаковых бледных плиток, упёртых в края экрана, — у
// листа не было боковых полей. Заказчик: «некрасиво очень». Выбран макет А:
// фото большой кнопкой в цвет темы, пять реже нужных типов на полке формами
// M3, капсула отдельной тёмной пилюлей.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/utils/color_distance.dart';
import 'package:love_app/widgets/common/halftone_painter.dart';
import 'package:love_app/widgets/memory/add_memory_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  double width = 320,
  double scale = 1.3,
  ValueChanged<MemoryType>? onType,
  VoidCallback? onCapsule,
}) async {
  final theme = buildAppTheme(kPalettes[0], brightness);
  final cs = ProfileTheme.themeFor(theme).colorScheme;
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ProfileTheme.data(cs),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        backgroundColor: cs.surfaceContainer,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AddMemorySheetBody(
            scheme: cs,
            fill: theme.fillColor,
            onType: onType ?? (_) {},
            onCapsule: onCapsule ?? () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  group('раскладка', () {
    for (final b in Brightness.values) {
      for (final (width, scale) in [(320.0, 1.3), (320.0, 1.0), (393.0, 1.0)]) {
        testWidgets('${b.name}, $width dp, шрифт $scale — без переполнений',
            (tester) async {
          await _pump(tester, brightness: b, width: width, scale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('поля по 16 точек с обеих сторон', (tester) async {
      await _pump(tester, brightness: Brightness.light, width: 360, scale: 1);
      final hero = tester.getRect(find.byKey(const ValueKey('add-hero')));
      expect(hero.left, 16);
      expect(hero.right, 360 - 16);
      final cap = tester.getRect(find.byKey(const ValueKey('add-capsule')));
      expect(cap.left, 16);
      expect(cap.right, 360 - 16);
    });

    for (final lang in ['ru', 'de', 'fr', 'es', 'it', 'pt', 'en']) {
      testWidgets('подписи полки не рвутся посреди слова ($lang, 320 dp, 1.3)',
          (tester) async {
        await LocaleService.instance.setLanguage(AppLanguage.byCode(lang)!);
        addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.ru));
        await _pump(tester, brightness: Brightness.light);
        for (final t in AddMemorySheetBody.shelfTypes) {
          final item = find.byKey(ValueKey('add-${t.name}'));
          final p = tester.renderObject<RenderParagraph>(
              find.descendant(of: item, matching: find.byType(RichText)).last);
          final text = p.text.toPlainText();
          final lines = p
              .getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: text.length))
              .map((b) => b.top.round())
              .toSet()
              .length;
          final words = text.split(RegExp(r'[\s-]+')).length;
          expect(lines, lessThanOrEqualTo(words),
              reason: '«$text» разложилось на $lines строк: слово разорвано');
        }
      });
    }

    testWidgets('полка — один ряд из пяти', (tester) async {
      await _pump(tester, brightness: Brightness.light);
      final tops = [
        for (final t in AddMemorySheetBody.shelfTypes)
          tester.getTopLeft(find.byKey(ValueKey('add-${t.name}'))).dy,
      ];
      expect(tops.toSet(), hasLength(1));
    });
  });

  group('касания', () {
    testWidgets('каждая кнопка ведёт в свой тип', (tester) async {
      final got = <MemoryType>[];
      var capsule = 0;
      await _pump(tester,
          brightness: Brightness.light,
          onType: got.add,
          onCapsule: () => capsule++);
      await tester.tap(find.byKey(const ValueKey('add-hero')));
      for (final t in AddMemorySheetBody.shelfTypes) {
        await tester.tap(find.byKey(ValueKey('add-${t.name}')));
      }
      await tester.tap(find.byKey(const ValueKey('add-capsule')));
      expect(got, [MemoryType.photo, ...AddMemorySheetBody.shelfTypes]);
      expect(AddMemorySheetBody.shelfTypes, [
        MemoryType.video,
        MemoryType.location,
        MemoryType.music,
        MemoryType.book,
        MemoryType.movie,
      ]);
      expect(capsule, 1);
    });
  });

  group('цвета', () {
    test('фигуры полки видны на листе во всех палитрах', () {
      final weak = <String>[];
      for (final b in Brightness.values) {
        for (final p in kPalettes) {
          final cs = ProfileTheme.themeFor(buildAppTheme(p, b)).colorScheme;
          for (final (c, toward) in [
            (cs.secondaryContainer, cs.secondary),
            (cs.tertiaryContainer, cs.tertiary),
          ]) {
            final tint = shelfTint(c, toward: toward, on: cs.surfaceContainer);
            final d = deltaE(tint, cs.surfaceContainer);
            if (d < kShelfMinDelta) weak.add('${b.name} ${p.name}: $d');
          }
        }
      }
      expect(weak, isEmpty);
    });

    test('заметный контейнер не трогаем — вид из макета остаётся', () {
      const bg = Color(0xFFFCEAEA);
      const sc = Color(0xFFFFB3B8);
      expect(shelfTint(sc, toward: Colors.red, on: bg), sc);
    });

    test('расстояние цветов: одинаковые — ноль, чёрный и белый — сто', () {
      expect(deltaE(Colors.white, Colors.white), 0);
      expect(deltaE(Colors.black, Colors.white), closeTo(100, 0.5));
    });

    for (final b in Brightness.values) {
      testWidgets('на главной кнопке растр цветом подписи (${b.name})',
          (tester) async {
        await _pump(tester, brightness: b);
        final theme = buildAppTheme(kPalettes[0], b);
        final paint = tester.widget<CustomPaint>(find.descendant(
            of: find.byKey(const ValueKey('add-hero')),
            matching: find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is HalftonePainter)));
        final painter = paint.painter! as HalftonePainter;
        expect(painter.color, AppThemes.onColor(theme.fillColor, mode: b));
        expect(painter.dark, b == Brightness.dark);
      });
    }

    testWidgets('главная кнопка в заливке темы, подпись белым', (tester) async {
      await _pump(tester, brightness: Brightness.light);
      final theme = buildAppTheme(kPalettes[0], Brightness.light);
      final hero = tester.widget<Material>(find.descendant(
          of: find.byKey(const ValueKey('add-hero')),
          matching: find.byType(Material)).first);
      expect(hero.color, theme.fillColor);
      final title = tester.widget<Text>(find.text(
          LocaleService.current.addHeroTitle));
      expect(title.style?.color,
          AppThemes.onColor(theme.fillColor, mode: Brightness.light));
    });
  });

  test('новые подписи есть на всех семи языках', () {
    final dict = File('lib/l10n/dict/memory_lane.dart').readAsStringSync();
    for (final key in [
      'addHeroTitle',
      'addHeroSub',
      'addShelfVideo',
      'addShelfPlace',
      'addShelfBook',
      'addShelfMovie',
    ]) {
      final at = dict.indexOf("'$key'");
      expect(at, isPositive, reason: 'нет ключа $key');
      final block = dict.substring(at, dict.indexOf('},', at));
      for (final lang in ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt']) {
        expect(block.contains("'$lang':"), isTrue, reason: '$key без $lang');
      }
    }
  });
}
