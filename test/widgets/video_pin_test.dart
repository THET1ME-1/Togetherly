import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/memory/video_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Видео-пин ленты воспоминаний, вариант «Подпись на кадре» (07.10.2026).
///
/// Прежний пин был карточкой в карточке с рамкой, кнопками фирменного цвета
/// площадки и маленьким кадром 80×56 у всего, кроме YouTube. Новый — кадр на
/// карточке без рамок, площадка пилюлей, название пилюлей на кадре, действия
/// связанной группой M3E.

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

class _Calls {
  int play = 0, open = 0, watch = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  String url = 'https://youtu.be/dQw4w9WgXcQ',
  String platform = 'YouTube',
  bool watchTogether = true,
  Widget? player,
  Brightness brightness = Brightness.light,
  double width = 360,
  double scale = 1.0,
  String? title = 'Сплав по озеру — влог за выходные',
  String? author = 'Аня и Кирилл',
  String? caption,
}) async {
  final theme = buildAppTheme(kPalettes[0], brightness);
  final cs = ProfileTheme.themeFor(theme).colorScheme;
  final calls = _Calls();
  tester.view.physicalSize = Size(width * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ProfileTheme.data(cs),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 1200), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: VideoPin(
                scheme: cs,
                fill: theme.fillColor,
                url: url,
                platformName: platform,
                platformIcon: Icons.smart_display_rounded,
                title: title,
                author: author,
                caption: caption,
                player: player,
                onPlay: () => calls.play++,
                onOpen: () => calls.open++,
                onWatchTogether: watchTogether ? () => calls.watch++ : null,
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
  return calls;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
  });

  group('вертикальный ролик', () {
    test('короткие форматы — вертикальные', () {
      for (final u in [
        'https://www.tiktok.com/@mila.k/video/7350000000000000000',
        'https://vm.tiktok.com/ZMabc123/',
        'https://youtube.com/shorts/ro0KqgvlS4Y?feature=share',
        'https://www.instagram.com/reel/C1abc/',
        'https://vk.com/clip-220754053_456239310',
        'https://rutube.ru/shorts/c6cc4d620b1d4338901770a44b3e82f4/',
      ]) {
        expect(isVerticalVideo(u), isTrue, reason: u);
      }
    });

    test('обычные ролики — горизонтальные', () {
      for (final u in [
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=ro0KqgvlS4Y',
        'https://rutube.ru/video/c6cc4d620b1d4338901770a44b3e82f4/',
        'https://vk.com/video-220754053_456239310',
        'https://vimeo.com/123456',
        '',
      ]) {
        expect(isVerticalVideo(u), isFalse, reason: u);
      }
    });
  });

  group('пропорции кадра', () {
    test('вертикальный ролик с обложкой — 4:5', () {
      expect(videoPinAspect('https://www.tiktok.com/@a/video/1', hasThumb: true), 4 / 5);
    });
    test('вертикальный без обложки — 16:9: пустой высокий блок занял бы пол-экрана', () {
      expect(videoPinAspect('https://www.tiktok.com/@a/video/1', hasThumb: false), 16 / 9);
    });
    test('горизонтальный — 16:9 всегда', () {
      expect(videoPinAspect('https://youtu.be/dQw4w9WgXcQ', hasThumb: true), 16 / 9);
      expect(videoPinAspect('https://youtu.be/dQw4w9WgXcQ', hasThumb: false), 16 / 9);
    });
  });

  testWidgets('YouTube: кадр 16:9, подпись на кадре, «Смотреть вместе» и «Открыть»', (tester) async {
    final calls = await _pump(tester);
    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio;
    expect(ratio, closeTo(16 / 9, 0.001));
    expect(find.text('Сплав по озеру — влог за выходные'), findsOneWidget);
    expect(find.text('Аня и Кирилл'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Смотреть вместе'), findsOneWidget);
    // Кнопка «Открыть» без слова — подсказка обязана назвать площадку.
    expect(find.byTooltip('Открыть в YouTube'), findsOneWidget);

    await tester.tap(find.text('Смотреть вместе'));
    await tester.tap(find.byTooltip('Открыть в YouTube'));
    await tester.tap(find.byKey(const ValueKey('video-pin-play')));
    expect([calls.watch, calls.open, calls.play], [1, 1, 1]);
  });

  testWidgets('TikTok без обложки и совместного просмотра: кадр 16:9, одна кнопка «Открыть»', (tester) async {
    final calls = await _pump(
      tester,
      url: 'https://www.tiktok.com/@mila.k/video/7350000000000000000',
      platform: 'TikTok',
      watchTogether: false,
      title: 'когда он опять забыл купить хлеб',
      author: '@mila.k',
      caption: 'Из совместной ленты',
    );
    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio;
    expect(ratio, closeTo(16 / 9, 0.001));
    // Без обложки в кадре нет значка площадки поверх «играть»: её называет пилюля.
    expect(find.byIcon(Icons.smart_display_rounded), findsOneWidget);
    expect(find.text('Смотреть вместе'), findsNothing);
    expect(find.text('Открыть в TikTok'), findsOneWidget);
    expect(find.text('Из совместной ленты'), findsOneWidget);
    await tester.tap(find.text('Открыть в TikTok'));
    expect(calls.open, 1);
  });

  testWidgets('без названия — подпись «Видео», без автора — одна строка', (tester) async {
    await _pump(tester, title: '', author: null);
    expect(find.text('Видео'), findsOneWidget);
  });

  testWidgets('играет в карточке: вместо кадра плеер, подписи на кадре нет', (tester) async {
    await _pump(tester, player: const SizedBox(key: ValueKey('player'), height: 200));
    expect(find.byKey(const ValueKey('player')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-pin-play')), findsNothing);
    expect(find.text('Сплав по озеру — влог за выходные'), findsNothing);
    expect(find.text('Смотреть вместе'), findsOneWidget);
  });

  testWidgets('ни одной рамки внутри пина', (tester) async {
    await _pump(tester);
    final pin = find.byType(VideoPin);
    for (final w in tester.widgetList<Container>(find.descendant(of: pin, matching: find.byType(Container)))) {
      final d = w.decoration;
      if (d is BoxDecoration) expect(d.border, isNull);
    }
    for (final w in tester.widgetList<DecoratedBox>(find.descendant(of: pin, matching: find.byType(DecoratedBox)))) {
      final d = w.decoration;
      if (d is BoxDecoration) expect(d.border, isNull);
    }
    for (final w in tester.widgetList<OutlinedButton>(find.descendant(of: pin, matching: find.byType(OutlinedButton)))) {
      expect(w, isNull, reason: 'кнопки с обводкой в пине нет');
    }
  });

  for (final b in Brightness.values) {
    for (final w in [320.0, 360.0]) {
      testWidgets('без переполнений: ${b.name}, $w dp, шрифт 1.3', (tester) async {
        await _pump(tester, brightness: b, width: w, scale: 1.3);
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          brightness: b,
          width: w,
          scale: 1.3,
          url: 'https://www.tiktok.com/@mila.k/video/1',
          platform: 'TikTok',
          watchTogether: false,
          title: 'очень длинное название ролика, которое точно не поместится в одну строку на узком экране',
          author: '@очень.длинный.ник.автора.ролика',
          caption: 'Из совместной ленты',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
