// Кнопка «Отразить» у снимка в форме воспоминания.
//
// Обращение 187 (23.09.2026): «версия последняя, но всё равно зеркалит, в
// настройках ничего не меняется». Часть телефонов сохраняет селфи уже
// отражённым и без пометки в EXIF — выправить такое сами мы не можем, поэтому
// человек переворачивает кадр руками.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/utils/photo_orientation.dart';

/// Кадр с явным «лево» и «право»: слева красный, справа синий.
Uint8List shot({int orientation = 0, int width = 40, int height = 20}) {
  final im = img.Image(width: width, height: height);
  img.fill(im, color: img.ColorRgb8(255, 0, 0));
  img.fillRect(im,
      x1: width ~/ 2,
      y1: 0,
      x2: width - 1,
      y2: height - 1,
      color: img.ColorRgb8(0, 0, 255));
  if (orientation > 0) im.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(im);
}

String leftEdge(img.Image im) {
  final p = im.getPixel(2, im.height ~/ 2);
  return p.r > p.b ? 'красный' : 'синий';
}

void main() {
  test('отражение меняет лево и право местами', () {
    final flipped = flipPhotoBytes(shot());
    expect(flipped, isNotNull);
    final im = img.decodeImage(flipped!)!;
    expect(leftEdge(im), 'синий');
    expect(im.width, 40);
    expect(im.height, 20);
  });

  test('двойное отражение возвращает исходный кадр', () {
    final twice = flipPhotoBytes(flipPhotoBytes(shot())!)!;
    expect(leftEdge(img.decodeImage(twice)!), 'красный');
  });

  test('пометка ориентации не удваивает поворот', () {
    // Кадр с поворотом на 90°: после отражения он обязан остаться стоячим,
    // а пометка в файле — сброшенной, иначе просмотрщик повернёт его ещё раз.
    final out = flipPhotoBytes(shot(orientation: 6))!;
    final im = img.decodeImage(out)!;
    expect(im.width, 20);
    expect(im.height, 40);
    expect(readExifOrientation(out), lessThanOrEqualTo(1));
  });

  test('битый файл не роняет форму', () {
    expect(flipPhotoBytes(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('в форме воспоминания у снимка есть кнопка «Отразить»', () {
    final src =
        File('lib/screens/memory_photo_form_screen.dart').readAsStringSync();
    expect(src, contains('_flipAt('));
    expect(src, contains('flipPhotoFile('));
    expect(src, contains('Icons.flip_rounded'));
  });
}
