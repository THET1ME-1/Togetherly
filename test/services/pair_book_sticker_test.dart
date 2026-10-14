// Наклейки в книге пары. Наборы лежат в WebP, а PDF понимает только JPEG и
// PNG; JPEG съел бы прозрачный фон наклейки. Сборка переводит картинку в PNG
// нужного размера и отдаёт книге то же место на снимке, что на пине.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_sticker.dart';
import 'package:love_app/services/pair_book_service.dart';

const _bunny = 'assets/images/mood_packs/bunny/love.webp';
const _own =
    'https://togetherly.day/api/files/custom_moods/k3m9x2p7q1w5e8r/custom_ab12cd34_x9y8z7w6v5.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WebP набора становится PNG не больше заданной стороны', () async {
    final raw = (await rootBundle.load(_bunny)).buffer.asUint8List();
    final png = await bookStickerPng(raw, side: 128);
    expect(png, isNotNull);
    expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47]);
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, lessThanOrEqualTo(128));
    expect(frame.image.height, lessThanOrEqualTo(128));
  });

  test('битая картинка — null, а не исключение', () async {
    expect(await bookStickerPng(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('наклейки записи идут в книгу на своих местах, свои — скруглёнными',
      () async {
    final pic = Uint8List.fromList([7]);
    final loaded = <String>[];
    final out = await bookStickers(
      const [
        MemorySticker(id: 'a', uid: 'me', image: _bunny, x: .9, y: .1, size: .3, angle: .2, at: 1),
        MemorySticker(id: 'b', uid: 'jb', image: _own, x: .2, y: .8, size: .4, angle: -.3, at: 2),
        MemorySticker(
            id: 'c', uid: 'jb', image: 'assets/images/mood_packs/bunny/cool.webp', x: .5, y: .5, at: 3),
      ],
      (image) async {
        loaded.add(image);
        return image.endsWith('cool.webp') ? null : pic;
      },
    );
    expect(out.length, 2, reason: 'не доехавшая картинка пропускается');
    expect(out.first.x, .9);
    expect(out.first.y, .1);
    expect(out.first.size, .3);
    expect(out.first.angle, .2);
    expect(out.first.rounded, isFalse);
    expect(out.last.rounded, isTrue);
    expect(identical(out.first.image, pic), isTrue);
    expect(loaded, [_bunny, _own, 'assets/images/mood_packs/bunny/cool.webp']);
  });
}
