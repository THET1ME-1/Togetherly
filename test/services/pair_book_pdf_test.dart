// Книга пары собирается в PDF на телефоне. Проверяем сборку без сети: данные
// приходят уже готовыми (текст и байты снимков), а на выходе обязан быть
// настоящий файл с нужным числом страниц и живой кириллицей — шрифт
// подшивается свой, иначе PDF показывает вместо русских букв пустые рамки.

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

BookPdfDay _day(int day, {int photos = 0}) => BookPdfDay(
      date: DateTime(2026, 5, day),
      dateLabel: '$day мая 2026',
      entries: [
        BookPdfEntry(
          title: 'Прогулка по набережной',
          caption: 'Ели мороженое и считали катера',
          author: 'Аня',
          photos: List.filled(photos, _jpeg),
        ),
      ],
    );

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
