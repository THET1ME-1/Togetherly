import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/mood_image.dart';

/// Стикер настроения живёт на экране в 28–64 точках, а в паке лежит квадратом
/// 512. Без подсказки Flutter держит в памяти полный кадр — мегабайт на
/// картинку размером с ноготь, и это в сетке календаря на тридцать дней.
///
/// Тесты проверяют, что картинка разворачивается под свой размер на экране и
/// что задан ровно один предел: с двумя (`cacheWidth` и `cacheHeight` разом)
/// кадр декодируется в прямоугольник и стикер сплющивается — на этом уже
/// обжигались миниатюры админки.
void main() {
  Future<Image> pumpMood(
    WidgetTester tester, {
    double? width,
    double? height,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MoodImage(
            'assets/images/moods/classic/happy.png',
            width: width,
            height: height,
          ),
        ),
      ),
    );
    return tester.widget<Image>(find.byType(Image).first);
  }

  testWidgets('размер на экране задаёт размер в памяти', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final image = await pumpMood(tester, width: 32);

    expect(image.image, isA<ResizeImage>());
    final resize = image.image as ResizeImage;
    expect(resize.width, 96, reason: '32 точки на плотности 3');
    expect(resize.height, isNull, reason: 'второй предел сплющил бы стикер');
  });

  testWidgets('когда задана только высота, предел ставится по ней', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final image = await pumpMood(tester, height: 40);

    final resize = image.image as ResizeImage;
    expect(resize.height, 80);
    expect(resize.width, isNull);
  });

  testWidgets('без размера предел не выдумываем', (tester) async {
    final image = await pumpMood(tester);

    expect(image.image, isNot(isA<ResizeImage>()));
  });
}
