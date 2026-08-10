// Шапка главного экрана: все блоки одной высоты.
//
// Строка живёт на каждой из пяти вкладок, и до августа 2026 собиралась из
// четырёх разных ростов (аватары 48, бейдж 30, счёт 34, круглая кнопка 28).
// Тест держит их вместе: если новый элемент придёт со своей высотой, ряд
// разъедется и проверка упадёт. Заодно ловится переполнение — Flutter при
// обрезке RenderFlex бросает ошибку и валит прогон сам.
//
// Кадры для глаз:
//
//     flutter test test/goldens/home_header_test.dart --update-goldens
//
// Лежат рядом в `goldens/header/`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/models/connection.dart';
import 'package:love_app/screens/home/home_header.dart';
import 'package:love_app/screens/miss_you_button.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Самый узкий телефон, который мы поддерживаем: 360 dp.
const Size _narrow = Size(360, 120);

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    any = true;
  }
  if (any) await loader.load();
}

Widget _header(AppTheme theme, {required String status}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ProfileTheme.themeFor(theme),
    home: Scaffold(
      backgroundColor: theme.bgGradient.first,
      body: Align(
        alignment: Alignment.topCenter,
        child: HomeHeader(
          theme: theme,
          isPaired: true,
          myAvatarUrl: '',
          myDisplayName: 'Саша',
          partners: const [GroupMember(uid: 'p1', name: 'Кристина', avatar: '')],
          myMood: const MemberMood(),
          moodOf: (_) => const MemberMood(),
          statusBadgeText: status,
          statusBadgeEmoji: '💕',
          pairId: '',
        ),
      ),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, Widget child, String name,
    {Size size = _narrow}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('header/$name.png'),
  );
}

void main() {
  final light = buildAppTheme(kPalettes[0], Brightness.light);
  final dark = buildAppTheme(kPalettes[1], Brightness.dark);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('все блоки шапки одного роста', (tester) async {
    tester.view.physicalSize = _narrow * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_header(light, status: 'Встречаемся'));
    await tester.pump();

    // Ряд ровно в рост блока.
    final row = find.descendant(
      of: find.byType(HomeHeader),
      matching: find.byType(Row),
    );
    expect(tester.getSize(row.first).height, kHeaderRowHeight);

    // Каждый блок — той же высоты: аватары, пилюля типа связи, счёт с
    // сердцем. Разнобой здесь и был тем, что бросалось в глаза.
    expect(
      tester.getSize(find.byType(MissYouButton)).height,
      kHeaderControlHeight,
    );
    final pill = find.ancestor(
      of: find.text('Встречаемся'),
      matching: find.byType(Container),
    );
    expect(tester.getSize(pill.first).height, kHeaderControlHeight);

    // Верхние грани совпадают — блоки стоят на одной линии, а не «плавают».
    final top = tester.getRect(find.byType(MissYouButton)).top;
    expect(tester.getRect(pill.first).top, top);
  });

  testWidgets('длинный тип связи ужимается, а не ломает ряд', (tester) async {
    tester.view.physicalSize = _narrow * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Своя связь может называться как угодно — обрезка обязана быть мягкой.
    await tester.pumpWidget(
      _header(light, status: 'Женаты уже целую вечность и один день'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MissYouButton)).height,
        kHeaderControlHeight);
  });

  testWidgets('снимок: светлая тема', (tester) async {
    await _shoot(tester, _header(light, status: 'Встречаемся'), 'light');
  });

  testWidgets('снимок: тёмная тема', (tester) async {
    await _shoot(tester, _header(dark, status: 'Встречаемся'), 'dark');
  });

  testWidgets('снимок: обычный телефон, оба счёта', (tester) async {
    // 412 dp — типичный экран. Здесь в пилюле помещается «моё / партнёра».
    await _shoot(tester, _header(light, status: 'Встречаемся'), 'wide',
        size: const Size(412, 120));
  });

  testWidgets('на узком экране «Встречаемся» не режется', (tester) async {
    tester.view.physicalSize = _narrow * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_header(light, status: 'Встречаемся'));
    await tester.pump();

    // Обрезку Flutter не показывает в дереве, зато её видно по ширине: у
    // ужатого текста она равна отведённой, а не собственной. Счётчик здесь
    // нулевой (сети в тесте нет), поэтому проверка ловит не сам порог, а
    // появление в ряду нового широкого блока — от него слово и страдало.
    final text = tester.renderObject<RenderBox>(find.text('Встречаемся'));
    // Слово живёт в `Expanded`, поэтому занимает всю отведённую ширину. Режется
    // оно тогда, когда отведённого МЕНЬШЕ собственной ширины — это и проверяем.
    expect(
      text.size.width,
      greaterThanOrEqualTo(text.getMaxIntrinsicWidth(kHeaderControlHeight) - 0.5),
      reason: 'слово не помещается и будет обрезано',
    );
  });
}
