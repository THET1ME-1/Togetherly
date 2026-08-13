import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/emoji_image.dart';

void main() {
  test('эмодзи превращается в PNG нужного размера', () async {
    // toImage работает только внутри runAsync: рендер уходит на движок.
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      final png = await renderEmojiPng('🎉', size: 128);

      expect(png.length, greaterThan(100));
      // Сигнатура PNG — иначе PocketBase примет файл, а картинка не откроется.
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  test('пустая строка не роняет рендер', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      final png = await renderEmojiPng('', size: 64);
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });
}
