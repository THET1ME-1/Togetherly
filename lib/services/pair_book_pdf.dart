import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Шрифты книги. Подшиваются свои: встроенные в PDF шрифты кириллицы не знают,
/// и русский текст выходит рядами пустых рамок.
class BookPdfFonts {
  final ByteData regular;
  final ByteData display;

  const BookPdfFonts({required this.regular, required this.display});
}

/// Обложка: имена пары, период и строка итогов под ними.
@immutable
class BookPdfCover {
  final String title;
  final String subtitle;
  final String footer;

  const BookPdfCover({
    required this.title,
    required this.subtitle,
    required this.footer,
  });
}

/// Одна запись книги: что было, чем подписано, кто добавил и какие снимки.
@immutable
class BookPdfEntry {
  final String title;
  final String caption;
  final String author;
  final List<Uint8List> photos;

  const BookPdfEntry({
    required this.title,
    required this.caption,
    required this.author,
    this.photos = const [],
  });
}

/// День книги — глава с заголовком-датой.
@immutable
class BookPdfDay {
  final DateTime date;
  final String dateLabel;
  final List<BookPdfEntry> entries;

  const BookPdfDay({
    required this.date,
    required this.dateLabel,
    required this.entries,
  });
}

const PdfColor _ink = PdfColor.fromInt(0xFF1B1B1F);
const PdfColor _soft = PdfColor.fromInt(0xFF6B6B72);
const PdfColor _accent = PdfColor.fromInt(0xFFFF7E9B);

/// Собирает книгу пары.
///
/// Данные приходят готовыми — текст и байты снимков, — поэтому сборку можно
/// гонять в тестах и, при нужде, в отдельном изоляте: сеть и хранилище тут не
/// участвуют.
Future<Uint8List> buildPairBookPdf({
  required BookPdfCover cover,
  required List<BookPdfDay> days,
  required BookPdfFonts fonts,
}) async {
  final body = pw.Font.ttf(fonts.regular);
  final display = pw.Font.ttf(fonts.display);
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: body, bold: body),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Container(width: 64, height: 4, color: _accent),
            pw.SizedBox(height: 28),
            pw.Text(
              cover.title,
              style: pw.TextStyle(font: display, fontSize: 34, color: _ink),
              textAlign: pw.TextAlign.center,
            ),
            if (cover.subtitle.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text(cover.subtitle,
                  style: pw.TextStyle(fontSize: 15, color: _soft)),
            ],
            if (cover.footer.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(cover.footer,
                  style: pw.TextStyle(fontSize: 12, color: _soft)),
            ],
          ],
        ),
      ),
    ),
  );

  if (days.isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${context.pageNumber}',
              style: pw.TextStyle(fontSize: 10, color: _soft)),
        ),
        build: (context) => [
          for (final day in days) ..._dayBlock(day, display),
        ],
      ),
    );
  }

  return doc.save();
}

List<pw.Widget> _dayBlock(BookPdfDay day, pw.Font display) => [
      pw.SizedBox(height: 10),
      pw.Text(day.dateLabel,
          style: pw.TextStyle(font: display, fontSize: 16, color: _accent)),
      pw.SizedBox(height: 4),
      pw.Divider(color: PdfColors.grey300, height: 12),
      for (final entry in day.entries) ..._entryBlock(entry),
      pw.SizedBox(height: 12),
    ];

List<pw.Widget> _entryBlock(BookPdfEntry entry) {
  final images = <pw.Widget>[];
  for (final bytes in entry.photos) {
    // Битый или неподдерживаемый кадр пропускаем: книга из-за одного снимка
    // собираться не перестанет, а человек и не узнает, какой именно её сломал.
    try {
      images.add(
        pw.ClipRRect(
          horizontalRadius: 10,
          verticalRadius: 10,
          child: pw.Image(pw.MemoryImage(bytes),
              width: 236, height: 176, fit: pw.BoxFit.cover),
        ),
      );
    } catch (e) {
      debugPrint('pair book: снимок пропущен ($e)');
    }
  }

  return [
    if (entry.title.isNotEmpty)
      pw.Text(entry.title,
          style: pw.TextStyle(fontSize: 13, color: _ink, lineSpacing: 2)),
    if (entry.caption.isNotEmpty) ...[
      pw.SizedBox(height: 2),
      pw.Text(entry.caption,
          style: pw.TextStyle(fontSize: 11.5, color: _soft, lineSpacing: 2)),
    ],
    if (images.isNotEmpty) ...[
      pw.SizedBox(height: 8),
      pw.Wrap(spacing: 8, runSpacing: 8, children: images),
    ],
    pw.SizedBox(height: 4),
    pw.Text(entry.author, style: pw.TextStyle(fontSize: 9.5, color: _soft)),
    pw.SizedBox(height: 12),
  ];
}
