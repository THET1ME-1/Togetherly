import 'dart:io';
import 'dart:typed_data';

import '../models/coloring_picture.dart';

/// Своя раскраска, которую завёл партнёр: в очереди загрузок этого телефона
/// её нет, есть только скачанный контур на диске. Пока экран узнавал такую
/// картинку лишь в момент скачивания, при повторном заходе лист открывался
/// обычным холстом (обращение 617, 11.11.2026).
ColoringPicture? adoptedColoring(
  File outline, {
  required String id,
  required String title,
}) {
  if (!ColoringPicture.isOwnId(id) || !outline.existsSync()) return null;
  final ratio = pngRatio(outline);
  if (ratio == null) return null;
  return ColoringPicture.own(id: id, title: title, ratio: ratio);
}

/// Ширина к высоте из заголовка PNG: подпись 8 байт, затем блок IHDR, где
/// ширина лежит в байтах 16–19, высота в 20–23. Весь файл не читается.
double? pngRatio(File file) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final Uint8List head;
  final reader = file.openSync();
  try {
    head = reader.readSync(24);
  } finally {
    reader.closeSync();
  }
  if (head.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (head[i] != signature[i]) return null;
  }
  final size = ByteData.sublistView(head);
  final width = size.getUint32(16);
  final height = size.getUint32(20);
  if (width == 0 || height == 0) return null;
  return width / height;
}
