import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/canvas_meta.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/screens/draw_gallery_screen.dart';
import 'package:love_app/services/canvas_storage_service.dart';
import 'package:love_app/theme/app_theme.dart';

/// TOG-39: холст закрывается сразу, а картинку для галереи дописывает уже
/// после ухода. Галерея к этому моменту прочитала список и стоит со старой
/// плиткой, поэтому свежую картинку она обязана подхватить сама.
void main() {
  // Картинка 1×1: галерее важен сам факт новой картинки, а не её вид.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  bool showsPreview(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .any((image) => image.image is MemoryImage);

  testWidgets('картинка, дописанная после ухода с холста, появляется на плитке',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'canvases_v1__solo': jsonEncode([
        CanvasMeta(
          id: 'canvas_1',
          name: 'Котик',
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
    expect(showsPreview(tester), isFalse);

    await tester.runAsync(
      () => CanvasStorageService.instance.updatePreview('', 'canvas_1', png),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(showsPreview(tester), isTrue,
        reason: 'галерея не узнала о свежей картинке холста');
    await tester.pumpWidget(const SizedBox());
  });
}
