/// Сколько точек по большей стороне класть в картинку для виджета.
///
/// Расширению виджета система отводит около 30 МБ на всё. Снимок с камеры на
/// 4000×3000 в разжатом виде занимает под пятьдесят, и расширение убивают ещё
/// до того, как оно что-то нарисует: человек видит серый прямоугольник. Так уже
/// пустовал маленький «Вместе» (13.08.2026), и 18.08.2026 тестер принёс то же
/// самое про квадратные виджеты 1×1, при том что средний и большой показывали
/// ту же фотографию.
///
/// Часть путей картинки жала и раньше (`_cachePhotoFromUrl`, 1200 точек), а вот
/// парный виджет и аватарки клали в общий контейнер ОРИГИНАЛ: `_downloadPhoto`
/// писал байты ответа как есть.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Предел для ключа виджета. Аватарки мельче: они рисуются кружком в углу.
int widgetImageMaxSide(String key) => key.contains('avatar') ? 400 : 1200;

/// Предел для готового файла в контейнере виджета.
///
/// Считается не «сколько весит файл», а «сколько займёт разжатая картинка»:
/// расширению виджета на iPhone отводят около 30 МБ, RemoteViews на Android
/// упирается в Binder. Полтора мегабайта сжатого — это примерно 1200×1200
/// точек, ровно тот размер, который мы и просим у кодека.
const int kMaxWidgetPhotoBytes = 1536 * 1024;

/// Что положить в контейнер виджета после попытки сжатия.
///
/// `null` — не класть ничего: на столе останется прежний снимок, и это лучше
/// пустоты. Раньше здесь стоял оригинал («лучше большой, чем никакой»), и он
/// гарантированно убивал виджет: снимок с камеры в разжатом виде занимает под
/// пятьдесят мегабайт при отведённых тридцати. Человек видел не «большое
/// фото», а пустой прямоугольник — и писал, что виджеты не работают.
Uint8List? widgetPhotoPayload({
  required Uint8List original,
  required Uint8List? compressed,
}) {
  if (compressed != null &&
      compressed.isNotEmpty &&
      compressed.length <= kMaxWidgetPhotoBytes) {
    return compressed;
  }
  // Кодек не справился. Оригинал годится, только если он и так мал.
  if (original.isNotEmpty && original.length <= kMaxWidgetPhotoBytes) {
    return original;
  }
  return null;
}

/// Запасное уменьшение: декодер пакета `image`, на выходе JPEG.
///
/// Нужен там, где нативный кодек не справился — завис по таймауту или не знает
/// формат. Раньше запасным путём шёл движок Flutter с `ImageByteFormat.png`, а
/// PNG кадра 1200×1200 весит два-четыре мегабайта: [widgetPhotoPayload] такой
/// файл отбраковывает, и если оригинал тоже крупный, в контейнер не попадает
/// НИЧЕГО. Путь остаётся пустым, виджет — пустым, и починить это человек не
/// может ничем, кроме смены фото. На 06.09.2026 так жили 45% iPhone, у которых
/// фото стоит на сервере.
///
/// `null` — байты не разобрались как картинка. Меньшую сторону не растягиваем.
Uint8List? shrinkToJpeg(Uint8List bytes, int maxSide, {int quality = 85}) {
  if (bytes.isEmpty) return null;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final frame = longest > maxSide
        ? img.copyResize(decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
            interpolation: img.Interpolation.average)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(frame, quality: quality));
  } catch (_) {
    return null;
  }
}
