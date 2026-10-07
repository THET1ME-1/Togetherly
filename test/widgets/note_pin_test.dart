import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/memory/note_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пин-заметка ленты, вариант «Большая кавычка» (07.10.2026).
///
/// Прежняя заметка была жёлтым стикером: цвет #FCE08A прошит в коде и не
/// менялся с темой, автор подписан курсивом внизу, шапки не было вовсе.
/// Новая — лист тонального цвета темы, над краем огромная кавычка цвета темы,
/// короткая заметка набрана крупно.

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Future<ColorScheme> _pump(
  WidgetTester tester, {
  String? title,
  String body = 'Возвращаюсь домой',
  Brightness brightness = Brightness.light,
  double width = 360,
  double scale = 1.0,
}) async {
  final theme = buildAppTheme(kPalettes[0], brightness);
  final cs = ProfileTheme.themeFor(theme).colorScheme;
  tester.view.physicalSize = Size(width * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ProfileTheme.data(cs),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 1400), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: NotePin(
                scheme: cs,
                fill: theme.fillColor,
                title: title,
                body: body,
                bodyBuilder: (text, style) => Text(
                  text,
                  key: const ValueKey('note-body'),
                  style: style,
                  maxLines: 14,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
  return cs;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  group('крупно или обычно', () {
    test('короткая заметка без заголовка — крупно, как цитата', () {
      expect(noteIsShort('Возвращаюсь домой', hasTitle: false), isTrue);
    });
    test('с заголовком — обычно: крупным стоит заголовок', () {
      expect(noteIsShort('Возвращаюсь домой', hasTitle: true), isFalse);
    });
    test('список в несколько строк — обычно', () {
      expect(noteIsShort('Хлеб\nМолоко', hasTitle: false), isFalse);
    });
    test('длинный текст — обычно', () {
      expect(noteIsShort('слово ' * 30, hasTitle: false), isFalse);
    });
  });

  testWidgets('лист цвета темы, кавычка цвета темы, без жёлтого и без рамок', (tester) async {
    final cs = await _pump(tester);
    final pin = find.byType(NotePin);
    final colors = <Color>[];
    for (final w in tester.widgetList<Container>(find.descendant(of: pin, matching: find.byType(Container)))) {
      final d = w.decoration;
      if (d is BoxDecoration) {
        expect(d.border, isNull, reason: 'рамок в заметке нет');
        if (d.color != null) colors.add(d.color!);
      }
    }
    expect(colors, contains(cs.secondaryContainer), reason: 'лист — secondaryContainer темы');
    expect(colors, isNot(contains(const Color(0xFFFCE08A))), reason: 'прошитого жёлтого больше нет');
    final quote = tester.widget<Text>(find.text('“'));
    expect(quote.style?.color, isNotNull);
  });

  testWidgets('короткая — 21, обычная — 17', (tester) async {
    await _pump(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('note-body'))).style?.fontSize, 21);
    await _pump(tester, title: 'Список на выходные', body: 'Купить хлеб\nЗабрать посылку');
    expect(find.text('Список на выходные'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('note-body'))).style?.fontSize, 17);
  });

  testWidgets('пустая заметка подписана «Заметка»', (tester) async {
    await _pump(tester, body: '');
    expect(find.text('Заметка'), findsOneWidget);
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
          title: 'Очень длинный заголовок заметки, который не помещается в одну строку',
          body: List.filled(20, 'строка списка, довольно длинная').join('\n'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
