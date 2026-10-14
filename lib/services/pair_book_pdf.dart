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

/// Наклейка на записи книги: картинка и то же место, что на пине.
///
/// Центр [x], [y] — в долях главного блока, сторона [size] — в долях его
/// ширины, поворот [angle] — в радианах по часовой, как во Flutter.
@immutable
class BookPdfSticker {
  /// PNG: у наклейки прозрачный фон, JPEG его не держит.
  final Uint8List image;
  final double x;
  final double y;
  final double size;
  final double angle;

  /// Своё настроение пары — квадрат фото во весь кадр, углы скругляются.
  final bool rounded;

  const BookPdfSticker({
    required this.image,
    required this.x,
    required this.y,
    required this.size,
    this.angle = 0,
    this.rounded = false,
  });
}

/// Одна запись книги: что было, чем подписано, кто добавил, какие снимки и
/// наклейки.
@immutable
class BookPdfEntry {
  final String title;
  final String caption;
  final String author;
  final List<Uint8List> photos;

  /// Старые снизу, новые сверху — как на пине.
  final List<BookPdfSticker> stickers;

  const BookPdfEntry({
    required this.title,
    required this.caption,
    required this.author,
    this.photos = const [],
    this.stickers = const [],
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
    // Картинка наклейки ложится в файл один раз, сколько бы записей её ни
    // несли: сборка отдаёт одну и ту же наклейку одним и тем же массивом.
    final stickerImages = Map<Uint8List, pw.ImageProvider?>.identity();
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
          for (final day in days) ..._dayBlock(day, display, stickerImages),
        ],
      ),
    );
  }

  return doc.save();
}

List<pw.Widget> _dayBlock(
  BookPdfDay day,
  pw.Font display,
  Map<Uint8List, pw.ImageProvider?> stickerImages,
) =>
    [
      pw.SizedBox(height: 10),
      pw.Text(day.dateLabel,
          style: pw.TextStyle(font: display, fontSize: 16, color: _accent)),
      pw.SizedBox(height: 4),
      pw.Divider(color: PdfColors.grey300, height: 12),
      for (final entry in day.entries) ..._entryBlock(entry, stickerImages),
      pw.SizedBox(height: 12),
    ];

const double _photoWidth = 236;
const double _photoHeight = 176;

/// Сторона наклейки в строке под текстом записи без снимка.
const double _rowStickerSide = 46;

List<pw.Widget> _entryBlock(
  BookPdfEntry entry,
  Map<Uint8List, pw.ImageProvider?> stickerImages,
) {
  final stickers = <(BookPdfSticker, pw.ImageProvider)>[];
  for (final s in entry.stickers) {
    // Битую наклейку пропускаем, как и битый снимок.
    final image = stickerImages.putIfAbsent(s.image, () {
      try {
        return pw.MemoryImage(s.image);
      } catch (e) {
        debugPrint('pair book: наклейка пропущена ($e)');
        return null;
      }
    });
    if (image != null) stickers.add((s, image));
  }

  final images = <pw.Widget>[];
  for (final bytes in entry.photos) {
    // Битый или неподдерживаемый кадр пропускаем: книга из-за одного снимка
    // собираться не перестанет, а человек и не узнает, какой именно её сломал.
    try {
      final photo = pw.ClipRRect(
        horizontalRadius: 10,
        verticalRadius: 10,
        child: pw.Image(pw.MemoryImage(bytes),
            width: _photoWidth, height: _photoHeight, fit: pw.BoxFit.cover),
      );
      // Наклейки стоят на первом кадре, как в открытой записи.
      images.add(images.isEmpty && stickers.isNotEmpty
          ? _stuckPhoto(photo, stickers)
          : photo);
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
    ] else if (stickers.isNotEmpty) ...[
      // Без снимка наклейки стоят строкой под текстом, как на листе заметки.
      pw.SizedBox(height: 10),
      pw.Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (s, image) in stickers)
            _stickerPicture(s, image, _rowStickerSide),
        ],
      ),
      pw.SizedBox(height: 4),
    ],
    pw.SizedBox(height: 4),
    pw.Text(entry.author, style: pw.TextStyle(fontSize: 9.5, color: _soft)),
    pw.SizedBox(height: 12),
  ];
}

/// Насколько наклейка свисает за край снимка, pt. На пине она свисает до
/// половины стороны, а самая крупная в углу ушла бы на 82 pt — за поле
/// страницы (42 pt) и на соседнюю запись.
const double kBookStickerOverhang = 36;

/// Левый верхний угол наклейки на снимке книги: то же место в долях, что на
/// пине, но свес не дальше [kBookStickerOverhang].
({double dx, double dy}) bookStickerTopLeft(BookPdfSticker s) {
  final side = s.size * _photoWidth;
  double place(double center, double extent) => (center - side / 2)
      .clamp(-kBookStickerOverhang, extent - side + kBookStickerOverhang);
  return (
    dx: place(s.x * _photoWidth, _photoWidth),
    dy: place(s.y * _photoHeight, _photoHeight),
  );
}

/// Снимок с наклейками на тех же местах, что на пине. Наклейка свисает за
/// край снимка, как в ленте.
pw.Widget _stuckPhoto(
  pw.Widget photo,
  List<(BookPdfSticker, pw.ImageProvider)> stickers,
) =>
    pw.SizedBox(
      width: _photoWidth,
      height: _photoHeight,
      child: pw.Stack(
        overflow: pw.Overflow.visible,
        children: [
          photo,
          for (final (s, image) in stickers)
            pw.Positioned(
              left: bookStickerTopLeft(s).dx,
              top: bookStickerTopLeft(s).dy,
              child: _stickerPicture(s, image, s.size * _photoWidth),
            ),
        ],
      ),
    );

pw.Widget _stickerPicture(
  BookPdfSticker s,
  pw.ImageProvider image,
  double side,
) {
  pw.Widget picture = pw.Image(image, width: side, height: side, fit: pw.BoxFit.contain);
  if (s.rounded) {
    picture = pw.ClipRRect(
      horizontalRadius: side * 0.26,
      verticalRadius: side * 0.26,
      child: picture,
    );
  }
  // Ось y в PDF смотрит вверх: поворот по часовой здесь — отрицательный.
  return pw.SizedBox(
    width: side,
    height: side,
    child: pw.Transform.rotate(angle: -s.angle, child: picture),
  );
}
