// Сколько пикселей класть в виджет.
//
// Расширению виджета система даёт около 30 МБ на всё. Снимок с камеры на
// 4000×3000 в разжатом виде занимает под пятьдесят: расширение убивают, и
// человек видит серый прямоугольник вместо фотографии. Ровно так пустовал
// маленький «Вместе» (13.08.2026), и 18.08 тестер принёс то же самое про
// квадратные виджеты 1×1.
//
// Часть путей уже жала картинки (`_cachePhotoFromUrl`, до 1200 px), а вот
// парный виджет и аватарки клали ОРИГИНАЛ: `_downloadPhoto` писал байты ответа
// как есть.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_image_limit.dart';

void main() {
  test('фото пары ужимается до 1200 точек по большей стороне', () {
    expect(widgetImageMaxSide('my_photo_path'), 1200);
    expect(widgetImageMaxSide('partner_photo_path'), 1200);
  });

  test('аватарки мельче: они рисуются кружком в углу', () {
    expect(widgetImageMaxSide('my_avatar_path'), 400);
    expect(widgetImageMaxSide('partner_avatar_path'), 400);
    expect(widgetImageMaxSide('user_2_avatar_path'), 400);
  });

  test('незнакомый ключ жмётся по общему правилу, а не остаётся оригиналом', () {
    expect(widgetImageMaxSide('что_то_новое'), 1200);
  });
}
