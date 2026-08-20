// Селфи приезжало зеркальным и таким оставалось навсегда.
//
// Жалоба от 20.08.2026: «когда фотографируешься на камеру, фотография
// получается отзеркаленной. Можно сделать так, чтобы фото было таким, как оно
// было сфотографировано?»
//
// Телефон, снимая фронтальной камерой, кладёт в файл кадр как есть и ставит в
// EXIF пометку «этот кадр отражён» (ориентация 2, 4, 5 или 7). Показать его
// правильно — забота того, кто открывает файл. Приложение перед кадрированием
// прогоняло снимок через `flutter_image_compress` с `autoCorrectionAngle`, а он
// берёт из EXIF ТОЛЬКО угол (`ExifInterface.rotationDegrees`, дальше
// `matrix.setRotate`) — отражение не применяет вовсе. И тут же `keepExif: false`
// выбрасывал саму пометку. Кадр оставался зеркальным, а сказать об этом было
// уже нечем: ни одна программа после этого не могла его выправить.
//
// Разбор пакетов лежит в CLAUDE.md, раздел про фотографии.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/utils/photo_orientation.dart';

/// Кадр с явным «лево» и «право»: половина красная, половина синяя. По ним и
/// видно, отразили картинку или нет.
Uint8List shot(int orientation, {int width = 40, int height = 20}) {
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

/// Какого цвета левый край.
String leftEdge(img.Image im) {
  final p = im.getPixel(im.width ~/ 8, im.height ~/ 2);
  return p.r > p.b ? 'красный' : 'синий';
}

void main() {
  test('пометка о зеркале читается', () {
    expect(readExifOrientation(shot(2)), 2);
    expect(readExifOrientation(shot(6)), 6);
    expect(readExifOrientation(shot(0)), 0, reason: 'пометки нет вовсе');
  });

  test('зеркальными считаются ровно четыре ориентации', () {
    for (final o in [2, 4, 5, 7]) {
      expect(orientationIsMirrored(o), isTrue, reason: 'ориентация $o');
    }
    for (final o in [0, 1, 3, 6, 8]) {
      expect(orientationIsMirrored(o), isFalse, reason: 'ориентация $o');
    }
  });

  test('селфи разворачивается обратно, а не остаётся зеркальным', () {
    final baked = bakeExifOrientation(shot(2));
    expect(baked, isNotNull, reason: 'кадр помечен зеркальным — работа есть');

    final out = img.decodeImage(baked!)!;
    expect(leftEdge(out), 'синий',
        reason: 'половины обязаны поменяться местами');
    expect(readExifOrientation(baked), anyOf(0, 1),
        reason: 'пометку нельзя оставлять: иначе отразят второй раз');
  });

  test('повёрнутый кадр печётся поворотом, стороны не путаются', () {
    final baked = bakeExifOrientation(shot(6));
    expect(baked, isNotNull);

    final out = img.decodeImage(baked!)!;
    expect(out.width, 20, reason: 'портрет из альбома: стороны меняются');
    expect(out.height, 40);
  });

  test('обычному снимку работа не нужна', () {
    expect(bakeExifOrientation(shot(1)), isNull);
    expect(bakeExifOrientation(shot(0)), isNull);
  });

  test('мусор вместо снимка не роняет приложение', () {
    expect(bakeExifOrientation(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(readExifOrientation(Uint8List.fromList([1, 2, 3, 4])), 0);
  });

  test('подготовка фото зовёт печать ориентации, а не только угол', () {
    final source = File('lib/utils/photo_crop.dart').readAsStringSync();
    expect(source, contains('bakeExifOrientation'),
        reason: 'зеркальность обязана печься в пиксели');
    expect(
      source.contains('autoCorrectionAngle') &&
          !source.contains('orientationIsMirrored'),
      isFalse,
      reason: 'угол в одиночку зеркальные кадры не выправляет',
    );
  });

  test('снимок с камеры выправляется до того, как его увидят', () async {
    final dir = await Directory.systemTemp.createTemp('selfie');
    final source = File('${dir.path}/selfie.jpg')..writeAsBytesSync(shot(2));

    final fixed = await uprightPhotoFile(source.path);
    expect(fixed, isNotNull, reason: 'зеркальный кадр обязан быть переписан');
    expect(fixed, isNot(source.path), reason: 'исходник не трогаем');

    final out = img.decodeImage(File(fixed!).readAsBytesSync())!;
    expect(leftEdge(out), 'синий');
    await dir.delete(recursive: true);
  });

  test('обычный снимок остаётся тем же файлом', () async {
    final dir = await Directory.systemTemp.createTemp('plain');
    final rotated = File('${dir.path}/rotated.jpg')..writeAsBytesSync(shot(6));
    final plain = File('${dir.path}/plain.jpg')..writeAsBytesSync(shot(1));
    final video = File('${dir.path}/clip.mp4')..writeAsBytesSync([0, 1, 2, 3]);

    expect(await uprightPhotoFile(plain.path), isNull);
    expect(await uprightPhotoFile(rotated.path), isNull,
        reason: 'поворот и так печёт быстрый нативный путь');
    expect(await uprightPhotoFile(video.path), isNull,
        reason: 'видео трогать нечем и незачем');
    expect(await uprightPhotoFile('${dir.path}/нет-такого.jpg'), isNull);
    await dir.delete(recursive: true);
  });

  test('выбор фото проходит через выправление, а не мимо', () {
    final safePick = File('lib/utils/safe_pick.dart').readAsStringSync();
    expect(safePick, contains('uprightPhotoFile'),
        reason: 'единая точка на все шестнадцать мест выбора');

    // Пикер зовут только через safePick — иначе фото пройдёт мимо правки.
    final bypass = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('safe_pick.dart')) continue;
      final text = file.readAsStringSync();
      for (final line in const ['picker.pickImage(', 'picker.pickMultiImage(', 'picker.pickMedia(']) {
        if (!text.contains(line)) continue;
        for (final piece in text.split(line).skip(1)) {
          final before = text.substring(0, text.indexOf(line + piece));
          if (!before.endsWith('safePick(\n      () => ') &&
              !before.contains('safePick(')) {
            bypass.add('${file.path}: $line');
          }
        }
      }
    }
    expect(bypass, isEmpty, reason: 'эти вызовы обходят safePick');
  });
}
