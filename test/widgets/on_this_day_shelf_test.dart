import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/on_this_day.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/memory/on_this_day_shelf.dart';

Memory _m(String id, MemoryType type, {String? title}) => Memory(
      id: id,
      groupId: 'g',
      authorUid: 'a',
      authorName: 'a',
      type: type,
      createdAt: DateTime(2025, 9, 28),
      title: title,
    );

final _items = [
  OnThisDayShelf(day: DateTime(2026, 8, 28), monthsAgo: 1, yearsAgo: 0, memories: [
    _m('a', MemoryType.location, title: 'Первый снег в горах'),
    _m('b', MemoryType.photo),
  ]),
  OnThisDayShelf(day: DateTime(2025, 9, 28), monthsAgo: 0, yearsAgo: 1, memories: [
    _m('c', MemoryType.music, title: 'Очень длинное название прогулки у Днестра вечером'),
  ]),
  OnThisDayShelf(day: DateTime(2024, 9, 28), monthsAgo: 0, yearsAgo: 2, memories: [
    _m('d', MemoryType.text),
  ]),
];

Widget _app(double scale, {ValueChanged<OnThisDayShelf>? onOpen, Key? key}) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFFFE7E8B)),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(320, 400), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: OnThisDayShelfRow(items: _items, onOpen: onOpen ?? (_) {}),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    if (!Platform.environment.containsKey('OTD_PREVIEW')) return;
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('MaterialIcons', '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  for (final scale in [1.0, 1.3]) {
    testWidgets('полка без переполнения на 320 dp, шрифт $scale', (t) async {
      t.view.physicalSize = const Size(320, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(scale));
      expect(t.takeException(), isNull);
      expect(find.text('Месяц назад'), findsWidgets);
      expect(find.text('Год назад'), findsWidgets);
      expect(find.text('2 года назад'), findsWidgets);
      expect(find.text('2'), findsOneWidget, reason: 'число записей только у плитки, где их больше одной');
    });
  }

  testWidgets('касание отдаёт свой период', (t) async {
    OnThisDayShelf? got;
    await t.pumpWidget(_app(1, onOpen: (s) => got = s));
    await t.tap(find.text('Год назад').first);
    expect(got?.yearsAgo, 1);
  });

  testWidgets('снимок полки для глаз', (t) async {
    final key = GlobalKey();
    t.view.physicalSize = const Size(640, 800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(1.3, key: key));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/otd').createSync(recursive: true);
      File('build/otd/shelf.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }, skip: !Platform.environment.containsKey('OTD_PREVIEW'));
}
