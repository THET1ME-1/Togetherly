// Книга пары собирается в PDF на телефоне. Проверяем сборку без сети: данные
// приходят уже готовыми (текст и байты снимков), а на выходе обязан быть
// настоящий файл с нужным числом страниц и живой кириллицей — шрифт
// подшивается свой, иначе PDF показывает вместо русских букв пустые рамки.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/services/pair_book_pdf.dart';

/// Однопиксельный JPEG — минимальная настоящая картинка для страницы.
final Uint8List _jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, ...List.filled(64, 0x08), 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
  ...List.filled(16, 0x00), 0x08, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01,
  ...List.filled(16, 0x00), 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00,
  0x3F, 0x00, 0xD2, 0xCF, 0x20, 0xFF, 0xD9,
]);

/// Наклейка 8×8 на прозрачном фоне — PNG, как её готовит сборка книги.
final Uint8List _png = Uint8List.fromList(img.encodePng(
  img.Image(width: 8, height: 8, numChannels: 4)..clear(img.ColorRgba8(240, 110, 175, 255)),
));

BookPdfSticker _sticker(Uint8List image, {double x = .8, double angle = .2}) =>
    BookPdfSticker(image: image, x: x, y: .2, size: .3, angle: angle);

BookPdfDay _day(int day, {int photos = 0, List<BookPdfSticker> stickers = const []}) =>
    BookPdfDay(
      date: DateTime(2026, 5, day),
      dateLabel: '$day мая 2026',
      entries: [
        BookPdfEntry(
          title: 'Прогулка по набережной',
          caption: 'Ели мороженое и считали катера',
          author: 'Аня',
          photos: List.filled(photos, _jpeg),
          stickers: stickers,
        ),
      ],
    );

/// Сколько картинок легло в файл. Словари картинок PDF не сжимает: картинка —
/// поток, а поток не прячется в поток объектов.
int _images(Uint8List pdf) =>
    RegExp(r'/Subtype\s*/Image').allMatches(latin1.decode(pdf)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BookPdfFonts fonts;

  setUpAll(() async {
    fonts = BookPdfFonts(
      regular: await rootBundle.load('assets/fonts/Onest.ttf'),
      display: await rootBundle.load('assets/fonts/Unbounded.ttf'),
    );
  });

  test('книга собирается в настоящий PDF', () async {
    final bytes = await buildPairBookPdf(
      cover: const BookPdfCover(
        title: 'Аня и Костя',
        subtitle: 'Май 2026',
        footer: '124 дня вместе · 3 воспоминания',
      ),
      days: [_day(1), _day(2, photos: 1)],
      fonts: fonts,
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('пустая книга всё равно даёт файл с обложкой', () async {
    final bytes = await buildPairBookPdf(
      cover: const BookPdfCover(title: 'Аня и Костя', subtitle: '', footer: ''),
      days: const [],
      fonts: fonts,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  Future<Uint8List> book(List<BookPdfDay> days) => buildPairBookPdf(
        cover: const BookPdfCover(title: 'Аня и Костя', subtitle: '', footer: ''),
        days: days,
        fonts: fonts,
      );

  group('наклейки', () {
    test('ложатся на первый снимок записи', () async {
      final plain = await book([_day(1, photos: 2)]);
      final stuck = await book([_day(1, photos: 2, stickers: [_sticker(_png)])]);
      expect(_images(stuck), greaterThan(_images(plain)));
    });

    test('одна картинка на две наклейки ложится в файл один раз', () async {
      final one = await book([_day(1, photos: 1, stickers: [_sticker(_png)])]);
      final two = await book([
        _day(1, photos: 1, stickers: [_sticker(_png), _sticker(_png, x: .1)]),
      ]);
      expect(_images(two), _images(one));
    });

    test('у записи без снимка встают строкой под текстом', () async {
      final plain = await book([_day(1)]);
      final stuck = await book([_day(1, stickers: [_sticker(_png)])]);
      expect(_images(plain), 0);
      expect(_images(stuck), greaterThan(0));
    });

    test('стоит на том же месте снимка, свисает за край не дальше поля', () {
      final middle = bookStickerTopLeft(
          BookPdfSticker(image: _png, x: .5, y: .5, size: .28));
      expect(middle.dx, closeTo(236 * .5 - 236 * .28 / 2, 1e-9));
      expect(middle.dy, closeTo(176 * .5 - 236 * .28 / 2, 1e-9));

      // Самая крупная в углу свисала бы на 82 pt — за поле страницы и на
      // соседнюю запись.
      final corner =
          bookStickerTopLeft(BookPdfSticker(image: _png, x: 0, y: 1, size: .7));
      expect(corner.dx, -kBookStickerOverhang);
      expect(corner.dy, 176 - 236 * .7 + kBookStickerOverhang);
    });

    test('битая наклейка пропускается, книга собирается', () async {
      final broken = Uint8List.fromList([1, 2, 3, 4, 5]);
      final plain = await book([_day(1, photos: 1)]);
      final stuck = await book([_day(1, photos: 1, stickers: [_sticker(broken)])]);
      expect(String.fromCharCodes(stuck.take(5)), '%PDF-');
      expect(_images(stuck), _images(plain));
    });
  });

  test('битый снимок пропускается, а не роняет всю книгу', () async {
    final broken = Uint8List.fromList([1, 2, 3, 4, 5]);
    final bytes = await buildPairBookPdf(
      cover: const BookPdfCover(title: 'Аня и Костя', subtitle: '', footer: ''),
      days: [
        BookPdfDay(
          date: DateTime(2026, 5, 3),
          dateLabel: '3 мая 2026',
          entries: [
            BookPdfEntry(
              title: 'Кадр не открылся',
              caption: '',
              author: 'Костя',
              photos: [broken, _jpeg],
            ),
          ],
        ),
      ],
      fonts: fonts,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
