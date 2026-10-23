import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/canvas_meta.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/screens/draw_gallery_screen.dart';
import 'package:love_app/services/canvas_storage_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';

/// «Почему холсты нельзя удалять» (TOG-12, 22.10.2026).
///
/// С 21.09.2026 удалить холст было нечем: выбор холстов включался только
/// долгим нажатием, а долгое нажатие отдали под меню «на рабочий стол» и
/// «переименовать». Найдено на эмуляторе: в меню нет удаления, а войти в
/// выбор больше неоткуда.
void main() {
  Future<void> openMenu(WidgetTester tester) async {
    // Экран телефона: в окне теста 800×600 подпись плитки уходит под кнопку.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'canvases_v1__solo': jsonEncode([
        CanvasMeta(
          id: 'canvas_1',
          name: 'Раскраска «Кафе»',
          createdAt: DateTime(2026, 10, 20),
          updatedAt: DateTime(2026, 10, 20),
        ).toJson(),
      ]),
    });
    await tester.pumpWidget(MaterialApp(
      home: DrawGalleryScreen(
        userData: UserData(),
        pairData: PairData(),
        theme: AppThemes.pink,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.ancestor(
      of: find.text('Раскраска «Кафе»'),
      matching: find.byType(GestureDetector),
    ).first);
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('в меню холста есть удаление, и оно удаляет', (tester) async {
    await openMenu(tester);
    final delete = find.text(trKey('canvasMenuDelete'));
    expect(delete, findsOneWidget, reason: 'Без этого пункта холст не удалить');

    await tester.tap(delete);
    // Меню уезжает, выезжает лист подтверждения.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text(LocaleService.current.delete).last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await CanvasStorageService.instance.getCanvases('', groupId: ''),
        isEmpty);
    expect(find.text('Раскраска «Кафе»'), findsNothing);
  });

  testWidgets('«Выбрать несколько» включает выбор с этим холстом', (tester) async {
    await openMenu(tester);
    await tester.tap(find.text(trKey('canvasMenuSelect')));
    await tester.pump(const Duration(milliseconds: 600));

    // Режим выбора: внизу кнопка удаления вместо «Новый холст».
    expect(find.widgetWithText(FilledButton, LocaleService.current.delete),
        findsOneWidget);
  });
}
