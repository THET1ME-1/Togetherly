import 'dart:io';
import 'dart:ui' show Rect;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/memory.dart';
import '../models/memory_archive.dart';
import '../models/timer_item.dart';
import '../models/user_data.dart';
import 'media_fetcher.dart';
import 'pb_data_service.dart';

/// Архив воспоминаний пары из профиля: `Timers.txt`, `Memories.txt` и все
/// файлы записей по месяцам.
///
/// До 19.09.2026 архив собирался целиком в памяти, брал по одному кадру с
/// записи, пропускал видео и портил русский текст. Теперь файлы берутся тем же
/// правилом, что у сохранения в галерею, ZIP пишется потоком на диск (у самой
/// активной пары это около 170 МБ), а текст — в UTF-8.
class ExportService {
  Future<void> exportMemories({
    required String groupId,
    required List<TimerItem> timers,
    required UserData userData,
    // iPad-поповер: якорь для share-листа; без него на планшете лист не
    // откроется. Считается вызывающим из BuildContext до вызова сервиса.
    Rect? sharePositionOrigin,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final zipPath =
          '${tempDir.path}/Togetherly_${DateTime.now().millisecondsSinceEpoch}.zip';
      final zip = ZipFileEncoder()..create(zipPath);

      // 1. Таймеры. Символ в текстовую выгрузку не пишем: с версии 1.20 там
      //    лежит имя значка (`favorite`), а не эмодзи.
      final timerBuffer = StringBuffer()..writeln('=== ТАЙМЕРЫ ===');
      for (final t in timers) {
        timerBuffer
          ..writeln(t.title)
          ..writeln('Начало: ${t.formattedStartDate}')
          ..writeln('Прошло: ${t.daysElapsed} дней')
          ..writeln('--------------------');
      }
      final timerBytes = archiveText(timerBuffer.toString());
      zip.addArchiveFile(ArchiveFile('Timers.txt', timerBytes.length, timerBytes));

      // 2. Воспоминания в хронологическом порядке (лента идёт новые сверху).
      final recs = await PbDataService().loadMemories(groupId, limit: 100000);
      final memories = recs.reversed.map((r) => Memory.fromPb(r)).toList();
      final entries = archiveEntries(memories);

      // 3. Файлы — по одному, чтобы в памяти не лежало больше одного.
      final fetcher = HttpMediaFetcher();
      final missing = <String>{};
      for (final e in entries) {
        try {
          final got = await fetcher.fetch(e.file);
          await zip.addFile(got.file, e.path);
          if (got.temporary) {
            try {
              await got.file.delete();
            } catch (_) {}
          }
        } catch (err) {
          debugPrint('Export: ${e.file.key} не скачался: $err');
          missing.add(e.path);
        }
      }

      final text = memoriesText(
        memories,
        [for (final e in entries) if (!missing.contains(e.path)) e],
      );
      final memoryBytes = archiveText(text);
      zip.addArchiveFile(
          ArchiveFile('Memories.txt', memoryBytes.length, memoryBytes));
      await zip.close();

      await Share.shareXFiles(
        [XFile(zipPath)],
        text: 'Архив воспоминаний',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      debugPrint('Export Error: $e');
      throw Exception('Ошибка при экспорте архива: $e');
    }
  }
}
