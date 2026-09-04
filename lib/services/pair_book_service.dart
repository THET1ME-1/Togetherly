import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/memory.dart';
import '../models/pair_book.dart';
import 'locale_service.dart';
import 'pb_media_service.dart';
import 'pair_book_pdf.dart';

/// Сколько снимков берётся от одной записи.
///
/// Пара выкладывает в одно воспоминание и пятнадцать кадров с прогулки; в
/// книге это страница за страницей одного дня, а файл разбухает до сотен
/// мегабайт и не уходит ни в один мессенджер.
const int kBookPhotosPerEntry = 3;

/// Длинная сторона снимка в книге. A4 при 150 точках на дюйм — это около 1240
/// точек по ширине листа, крупнее в печати всё равно не видно.
const int kBookPhotoSide = 1400;

/// Сколько записей книга собирает без предупреждения.
const int kBookSoftLimit = 800;

/// Сборка книги пары: скачивает снимки, ужимает их и складывает PDF.
class PairBookService {
  PairBookService._();
  static final PairBookService instance = PairBookService._();

  final PbMediaService _media = PbMediaService();

  /// Собирает файл книги и возвращает его.
  ///
  /// [onProgress] зовётся после каждой записи — экран показывает полосу, иначе
  /// сборка сотни воспоминаний выглядит зависшей.
  Future<File> build({
    required List<Memory> memories,
    required String coupleTitle,
    required String periodLabel,
    required String footer,
    void Function(int done, int total)? onProgress,
  }) async {
    final days = bookDays(memories);
    final fonts = BookPdfFonts(
      regular: await rootBundle.load('assets/fonts/Onest.ttf'),
      display: await rootBundle.load('assets/fonts/Unbounded.ttf'),
    );

    var done = 0;
    final pdfDays = <BookPdfDay>[];
    for (final day in days) {
      final entries = <BookPdfEntry>[];
      for (final m in day.memories) {
        entries.add(BookPdfEntry(
          title: _titleOf(m),
          caption: _captionOf(m),
          author: m.authorName,
          photos: await _photosOf(m),
        ));
        onProgress?.call(++done, memories.length);
      }
      pdfDays.add(BookPdfDay(
        date: day.day,
        dateLabel: LocaleService.current.dayLogDate(day.day),
        entries: entries,
      ));
    }

    final bytes = await buildPairBookPdf(
      cover: BookPdfCover(
        title: coupleTitle,
        subtitle: periodLabel,
        footer: footer,
      ),
      days: pdfDays,
      fonts: fonts,
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/togetherly-book.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Заголовок записи. У записи без своего названия им становится тип — иначе
  /// в книге идёт ряд безымянных абзацев.
  String _titleOf(Memory m) {
    final title = (m.title ?? '').trim();
    if (title.isNotEmpty) return title;
    final place = (m.locationName ?? '').trim();
    if (place.isNotEmpty) return place;
    if (m.type == MemoryType.music) {
      final song = [m.musicArtist, m.musicTitle]
          .where((s) => (s ?? '').trim().isNotEmpty)
          .join(' — ');
      if (song.isNotEmpty) return song;
    }
    return '';
  }

  String _captionOf(Memory m) => normalizeMemoryCaption(m.caption)?.trim() ?? '';

  /// Снимки записи: скачиваются по правам текущего человека и ужимаются.
  ///
  /// Видео и ссылки в книгу кадром не идут: вытащить кадр на телефоне стоит
  /// дороже, чем весь остальной PDF, а без него запись остаётся строкой с
  /// подписью — как и всё, у чего нет своей фотографии.
  Future<List<Uint8List>> _photosOf(Memory m) async {
    final refs = <String>[
      if ((m.imageUrl ?? '').isNotEmpty) m.imageUrl!,
      ...?m.imageUrls,
    ];
    final seen = <String>{};
    final out = <Uint8List>[];
    for (final ref in refs) {
      if (out.length >= kBookPhotosPerEntry) break;
      if (!seen.add(ref)) continue;
      final bytes = await _download(ref);
      if (bytes != null) out.add(bytes);
    }
    return out;
  }

  Future<Uint8List?> _download(String ref) async {
    try {
      if (ref.startsWith('localfile://')) {
        final file = File(ref.substring('localfile://'.length));
        return await file.exists() ? await _shrink(await file.readAsBytes()) : null;
      }
      if (!ref.startsWith('http') && !_media.isPbRef(ref)) {
        final file = File(ref);
        return await file.exists() ? await _shrink(await file.readAsBytes()) : null;
      }
      final url = await _media.resolveUrlAuthed(ref);
      if (url == null || url.isEmpty) return null;
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return await _shrink(res.bodyBytes);
    } catch (e) {
      // Один недоехавший снимок не повод рушить книгу целиком.
      debugPrint('PairBook: снимок не доехал ($e)');
      return null;
    }
  }

  Future<Uint8List> _shrink(Uint8List bytes) async {
    if (!Platform.isAndroid && !Platform.isIOS) return bytes;
    try {
      // Предел по времени: зависший нативный кодек не бросает исключение, и
      // сборка книги встала бы намертво (разбор 04.09.2026).
      final smaller = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: kBookPhotoSide,
        minHeight: kBookPhotoSide,
        quality: 82,
        format: CompressFormat.jpeg,
      ).timeout(const Duration(seconds: 20));
      return smaller.isEmpty ? bytes : smaller;
    } catch (e) {
      debugPrint('PairBook: снимок не ужался ($e)');
      return bytes;
    }
  }
}
