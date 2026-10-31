import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/guide_mascot.dart';

/// Облачко меняет сцену по касанию, по настроению, по выбору пола, и каждая
/// сцена — отдельный файл. Владелец увидел на телефоне: смена с задержкой,
/// облачко двоится, на миг пропадает. Двоилось затухание старой картинки
/// поверх новой, пропадало — пока новая разжималась, место было пустым.
void main() {
  test('размер разжатия — одна из трёх ступеней, чтобы заготовка совпала с показом', () {
    expect(artDecodeBucket(100), 240);
    expect(artDecodeBucket(240), 240);
    expect(artDecodeBucket(241), 480);
    expect(artDecodeBucket(480), 480);
    expect(artDecodeBucket(700), 960);
    expect(artDecodeBucket(5000), 960);
  });

  testWidgets('смена сцены без затухания и без пустого места', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CatalogArtAnim('cloud_idle_base', side: 100)));
    // Каталог пуст — место держится, ничего не рисуется.
    expect(find.byType(SizedBox), findsWidgets);
    final images = tester.widgetList<Image>(find.byType(Image));
    for (final image in images) {
      expect(image.gaplessPlayback, isTrue);
    }
  });

  test('картинка из сети строится с прежним кадром до готовности новой', () {
    final image = catalogArtImage('https://example.com/a.webp', side: 100, decode: 240);
    expect(image.gaplessPlayback, isTrue);
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, 240);
  });
}
