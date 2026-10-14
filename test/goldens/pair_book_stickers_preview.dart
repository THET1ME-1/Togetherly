import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/services/pair_book_pdf.dart';
import 'package:love_app/services/pair_book_service.dart';

/// Наклейки в книге пары глазами: запись со снимком и заметка без него.
///
///   BOOK_PHOTO=<снимок.jpg> flutter test test/goldens/pair_book_stickers_preview.dart
///   pdftoppm -r 110 -png build/pair-book-stickers/book.pdf build/pair-book-stickers/page
///
/// Наклейки — настоящие картинки наборов, своё настроение — из
/// `test/fixtures/custom_mood/`. Без снимка вместо фото тональная заливка.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('книга с наклейками', () async {
    Future<Uint8List> png(String path) async =>
        (await bookStickerPng(File(path).readAsBytesSync()))!;

    final path = Platform.environment['BOOK_PHOTO'] ?? '';
    final photo = path.isNotEmpty && File(path).existsSync()
        ? Uint8List.fromList(img.encodeJpg(img.copyResize(
            img.decodeImage(File(path).readAsBytesSync())!,
            width: 1400,
          )))
        : Uint8List.fromList(img.encodeJpg(
            img.Image(width: 472, height: 352)..clear(img.ColorRgb8(196, 176, 160))));

    final bunny = await png('assets/images/mood_packs/bunny/cool.webp');
    final pink = await png('assets/images/mood_packs/pink/love.webp');
    final pug = await png('test/fixtures/custom_mood/pug.webp');
    final pride = await png('assets/images/mood_packs/bunny/pride.webp');

    final bytes = await buildPairBookPdf(
      cover: const BookPdfCover(title: 'THET1ME и JB SHARAN', subtitle: 'Октябрь 2026', footer: ''),
      days: [
        BookPdfDay(
          date: DateTime(2026, 10, 12),
          dateLabel: '12 октября 2026',
          entries: [
            BookPdfEntry(
              title: 'Рыцари семи королевств',
              caption: 'Хороший сериал по факту',
              author: 'THET1ME',
              photos: [photo, photo],
              stickers: [
                BookPdfSticker(image: bunny, x: .92, y: .06, size: .34, angle: .16),
                BookPdfSticker(image: pink, x: .04, y: .82, size: .29, angle: -.19),
                BookPdfSticker(image: pug, x: .55, y: .6, size: .3, angle: .12, rounded: true),
              ],
            ),
            BookPdfEntry(
              title: '',
              caption: 'Купила билеты на субботу, не планируй ничего',
              author: 'JB SHARAN',
              stickers: [
                BookPdfSticker(image: pride, x: .88, y: .7, size: .26, angle: .12),
                BookPdfSticker(image: pug, x: .5, y: .5, size: .3, angle: -.08, rounded: true),
              ],
            ),
          ],
        ),
      ],
      fonts: BookPdfFonts(
        regular: await rootBundle.load('assets/fonts/Onest.ttf'),
        display: await rootBundle.load('assets/fonts/Unbounded.ttf'),
      ),
    );
    Directory('build/pair-book-stickers').createSync(recursive: true);
    File('build/pair-book-stickers/book.pdf').writeAsBytesSync(bytes);
  });
}
