import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/avatar_frame.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/widgets/common/avatar_frame_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Рамка крупнее файла (экран приза: сторона ~400 точек, кадр из сборки 256,
// анимация 384) обязана растягиваться на весь квадрат. По умолчанию Flutter
// рисует картинку по BoxFit.scaleDown, и рамка садилась внутрь аватарки —
// жалоба со снимками 28.09.2026.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<Image>> images(WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(child: AvatarFrameImage('hearts', avatarSize: 248)),
    ));
    await t.pump(const Duration(milliseconds: 200));
    return find.byType(Image).evaluate().map((e) => e.widget as Image).toList();
  }

  testWidgets('кадр из сборки растягивается на квадрат рамки', (t) async {
    CatalogService.instance.debugSetFrames(const []);
    final list = await images(t);
    expect(list, isNotEmpty);
    for (final i in list) {
      expect(i.fit, BoxFit.contain);
    }
  });

  testWidgets('анимация из каталога и её заглушка тоже', (t) async {
    CatalogService.instance.debugSetFrames(const [
      AvatarFrame(key: 'hearts', smUrl: 'https://x.test/sm.webp', lgUrl: 'https://x.test/lg.webp', stillUrl: 'https://x.test/still.webp'),
    ]);
    final list = await images(t);
    expect(list.length, greaterThanOrEqualTo(2));
    for (final i in list) {
      expect(i.fit, BoxFit.contain);
    }
  });
}
