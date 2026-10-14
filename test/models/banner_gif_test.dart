// GIF-баннер профиля (Togetherly+): GIF узнаётся по подписи в начале файла,
// а не по расширению, и не тяжелее потолка.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/models/banner_gif.dart';

void main() {
  test('узнаёт обе подписи GIF', () {
    expect(BannerGif.isGif('GIF89a'.codeUnits), isTrue);
    expect(BannerGif.isGif('GIF87a'.codeUnits), isTrue);
    expect(BannerGif.isGif([...'GIF89a'.codeUnits, 1, 2, 3]), isTrue);
  });

  test('узнаёт файл, собранный кодировщиком', () {
    final picture = img.Image(width: 2, height: 2);
    expect(BannerGif.isGif(img.encodeGif(picture)), isTrue);
  });

  test('PNG, JPEG, WebP и обрывки — не GIF', () {
    final picture = img.Image(width: 2, height: 2);
    expect(BannerGif.isGif(img.encodePng(picture)), isFalse);
    expect(BannerGif.isGif(img.encodeJpg(picture)), isFalse);
    expect(BannerGif.isGif('RIFF\x00\x00\x00\x00WEBP'.codeUnits), isFalse);
    expect(BannerGif.isGif('GIF88a'.codeUnits), isFalse);
    expect(BannerGif.isGif('GIF8'.codeUnits), isFalse);
    expect(BannerGif.isGif(const []), isFalse);
  });

  test('потолок десять мегабайт включительно, пустой файл не проходит', () {
    expect(BannerGif.maxMb, 10);
    expect(BannerGif.fits(1), isTrue);
    expect(BannerGif.fits(BannerGif.maxBytes), isTrue);
    expect(BannerGif.fits(BannerGif.maxBytes + 1), isFalse);
    expect(BannerGif.fits(0), isFalse);
  });
}
