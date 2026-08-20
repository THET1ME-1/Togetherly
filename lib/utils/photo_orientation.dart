import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// EXIF-ориентация снимка и её печать в пиксели.
///
/// Телефон почти никогда не поворачивает кадр физически: он кладёт его как
/// снял, а рядом пишет пометку — «поверни на 90», «отрази по горизонтали».
/// Фронтальная камера ставит именно отражение (2, 4, 5, 7): человек видел себя
/// как в зеркале, и файл сохраняет ровно то, что было на матрице.
///
/// Пометку понимают не все. Наш путь обработки фото её терял: нативный
/// компрессор применяет из EXIF только УГОЛ, а сам EXIF выбрасывает, — и
/// селфи оставалось зеркальным навсегда, без всякой возможности выправить.
/// Отсюда жалоба 20.08.2026 «фотография получается отзеркаленной».
///
/// Функции здесь — чистый Dart, без платформы: их можно проверить обычным
/// тестом (`test/selfie_mirror_test.dart`), не поднимая телефон.

/// Ориентация из EXIF: 1..8, либо 0 — пометки нет или файл не разобрался.
int readExifOrientation(Uint8List jpeg) {
  try {
    final exif = img.decodeJpgExif(jpeg);
    final value = exif?.imageIfd.orientation;
    if (value == null || value < 1 || value > 8) return 0;
    return value;
  } catch (_) {
    return 0;
  }
}

/// Отражён ли кадр. Ровно эти четыре ориентации несут зеркало — остальные
/// только поворачивают, и с ними справляется быстрый нативный путь.
bool orientationIsMirrored(int orientation) =>
    orientation == 2 || orientation == 4 || orientation == 5 ||
    orientation == 7;

/// Печёт ориентацию в пиксели: и поворот, и отражение. Возвращает JPEG без
/// пометки — снимок теперь выглядит так же, каким его видели в кадре.
///
/// `null`, если печь нечего (обычный снимок) или файл не разобрался: звать
/// дальше нечего, пусть идёт исходник.
///
/// Декодер пакета `image` применяет EXIF сам, поэтому отдельной перекладки
/// пикселей не нужно — достаточно раскодировать и закодировать обратно.
/// Работа тяжёлая (целый кадр в памяти), поэтому зовут её только для
/// зеркальных ориентаций и в отдельном изоляте.
Uint8List? bakeExifOrientation(Uint8List jpeg, {int quality = 95}) {
  final orientation = readExifOrientation(jpeg);
  if (orientation <= 1) return null;
  try {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return null;
    return img.encodeJpg(decoded, quality: quality);
  } catch (_) {
    return null;
  }
}

/// Снимок с камеры мог родиться зеркальным. Возвращает путь к выправленному
/// файлу — или `null`, если трогать нечего: обычное фото, повёрнутый кадр
/// (с ним справится быстрый нативный путь в `cropPhoto`), видео, чужой формат.
///
/// Зовётся из [safePick] — единственной двери, через которую фотографии
/// попадают в приложение. Так выправляются все шестнадцать мест выбора разом,
/// включая те, где кадрирования нет вовсе: аватар, чат, обложка виджета.
/// Гео и дата съёмки при этом остаются на месте — карта воспоминаний берёт их
/// из того же файла.
Future<String?> uprightPhotoFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    // Снимок в память влезает, панорама на сотню мегабайт — нет.
    if (await file.length() > 40 * 1024 * 1024) return null;

    final bytes = await file.readAsBytes();
    if (!orientationIsMirrored(readExifOrientation(bytes))) return null;

    // Целый кадр в памяти — работа не для главного потока.
    final baked = await compute(bakeExifOrientation, bytes);
    if (baked == null) return null;

    final target = '${Directory.systemTemp.path}/'
        '${DateTime.now().microsecondsSinceEpoch}_upright.jpg';
    await File(target).writeAsBytes(baked, flush: true);
    return target;
  } catch (_) {
    return null;
  }
}
