import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/avatar_frame.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/widgets/avatar_widget.dart';
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

  // Рамка частью лежит внутри круга фото (кольцо ленточки начинается с
  // радиуса 26 из 31), и фото уходило под неё на треть площади. Фото
  // ужимается до `data.hole`, место в раскладке прежнее.
  test('радиус фото берётся из каталога, без него — из сборки', () {
    final f = AvatarFrame.fromCatalog({
      'kind': 'frame',
      'data': {'key': 'ribbon', 'hole': 27.5, 'sm': 'https://x.test/sm.webp'},
    })!;
    expect(f.photoScale, closeTo(27.5 / 31, 1e-9));
    final noHole = AvatarFrame.fromCatalog({
      'kind': 'frame',
      'data': {'key': 'ribbon', 'sm': 'https://x.test/sm.webp'},
    })!;
    expect(noHole.hole, AvatarFrame.bundledHole['ribbon']);
    final fresh = AvatarFrame.fromCatalog({
      'kind': 'frame',
      'data': {'key': 'new_one', 'hole': 99, 'sm': 'https://x.test/sm.webp'},
    })!;
    expect(fresh.hole, AvatarFrame.avatarR, reason: 'больше фото не бывает');
  });

  testWidgets('фото под рамкой ужато, раскладка прежняя', (t) async {
    CatalogService.instance.debugSetFrames(const [
      AvatarFrame(key: 'ribbon', smUrl: 'https://x.test/sm.webp', hole: 27.5),
    ]);
    const photo = SizedBox.square(key: ValueKey('photo'), dimension: 100);
    await t.pumpWidget(const MaterialApp(
      home: Center(child: FramedAvatar(uid: 'u', size: 100, frame: 'ribbon', child: photo)),
    ));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.getSize(find.byType(FramedAvatar)), const Size(100, 100));
    final r = t.getRect(find.byKey(const ValueKey('photo')));
    expect(r.width, closeTo(100 * 27.5 / 31, 0.01));
    expect(r.center, const Offset(400, 300));
  });
}
