/// Содержимое архива воспоминаний из профиля: какие файлы и под какими именами.
///
/// До 19.09.2026 архив брал по одному кадру с записи (только `imageUrl`), не
/// брал видео вовсе и писал текст `codeUnits`: ZIP ждёт байты, а единицы
/// UTF-16 усекались до байта, и русские буквы превращались в мусор. Отбор
/// файлов теперь общий с сохранением в галерею ([memoryMediaFiles]).
library;

import 'dart:convert';

import 'memory.dart';
import 'memory_media.dart';

class ArchiveEntry {
  final Memory memory;
  final MediaFile file;

  /// Путь внутри архива: `Media/2026-09/Togetherly_20260905_130507_01.webp`.
  final String path;

  const ArchiveEntry(this.memory, this.file, this.path);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Файлы архива в порядке записей. Папка — месяц воспоминания, имя — то же,
/// что в галерее. Совпавшие имена получают хвост `_2`, `_3`: две записи в одну
/// секунду иначе затёрли бы друг друга.
List<ArchiveEntry> archiveEntries(List<Memory> memories, {DateTime? now}) {
  final used = <String>{};
  final out = <ArchiveEntry>[];
  for (final m in memories) {
    for (final f in memoryMediaFiles(m, now: now)) {
      final d = m.createdAt;
      final dir = 'Media/${d.year}-${_two(d.month)}';
      final name = galleryFileName(d, f);
      var path = '$dir/$name';
      var n = 2;
      while (!used.add(path)) {
        final dot = name.lastIndexOf('.');
        path = '$dir/${name.substring(0, dot)}_$n${name.substring(dot)}';
        n++;
      }
      out.add(ArchiveEntry(m, f, path));
    }
  }
  return out;
}

/// `Memories.txt`: запись за записью, с путями её файлов в архиве.
String memoriesText(List<Memory> memories, List<ArchiveEntry> entries) {
  final byMemory = <String, List<String>>{};
  for (final e in entries) {
    byMemory.putIfAbsent(e.memory.id, () => []).add(e.path);
  }
  final b = StringBuffer()..writeln('=== ВОСПОМИНАНИЯ ===');
  for (final m in memories) {
    final d = m.createdAt;
    b.writeln('[${m.typeEmoji} ${m.typeLabel}] '
        '${_two(d.day)}.${_two(d.month)}.${d.year} — ${m.authorName}');
    if (m.title?.trim().isNotEmpty ?? false) b.writeln('Название: ${m.title}');
    if (m.caption?.trim().isNotEmpty ?? false) b.writeln('Заметка: ${m.caption}');
    if (m.locationName?.trim().isNotEmpty ?? false) {
      b.writeln('Место: ${m.locationName}');
    }
    for (final p in byMemory[m.id] ?? const <String>[]) {
      b.writeln('Файл: $p');
    }
    b.writeln('--------------------');
  }
  return b.toString();
}

/// Текст для ZIP — байты UTF-8 с меткой порядка байтов: без неё «Блокнот»
/// в Windows открывает файл не в той кодировке.
List<int> archiveText(String text) => [0xEF, 0xBB, 0xBF, ...utf8.encode(text)];
