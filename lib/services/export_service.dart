import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/memory.dart';
import '../models/timer_item.dart';
import '../models/user_data.dart';

class ExportService {
  Future<void> exportMemories({
    required String groupId,
    required List<TimerItem> timers,
    required UserData userData,
  }) async {
    try {
      final archive = Archive();

      // 1. Compile Timers.txt
      final timerBuffer = StringBuffer();
      timerBuffer.writeln('=== ТАЙМЕРЫ ===');
      for (final t in timers) {
        timerBuffer.writeln('${t.emoji} ${t.title}');
        timerBuffer.writeln('Начало: ${t.formattedStartDate}');
        timerBuffer.writeln('Прошло: ${t.daysElapsed} дней');
        timerBuffer.writeln('--------------------');
      }
      final timerBytes = timerBuffer.toString().codeUnits;
      archive.addFile(ArchiveFile('Timers.txt', timerBytes.length, timerBytes));

      // 2. Fetch Memories from Firestore for the given group
      final memoriesQuery = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .orderBy('createdAt', descending: false)
          .get();

      final memories = memoriesQuery.docs
          .map((doc) => Memory.fromFirestore(doc.id, doc.data()))
          .toList();

      // 3. Compile Memories.txt and download photos
      final memoryBuffer = StringBuffer();
      memoryBuffer.writeln('=== ВОСПОМИНАНИЯ (MEMORY LANE) ===');

      int photoCounter = 1;
      for (final m in memories) {
        final dateStr =
            '${m.createdAt.day.toString().padLeft(2, '0')}.${m.createdAt.month.toString().padLeft(2, '0')}.${m.createdAt.year}';

        memoryBuffer.writeln(
          '[${m.typeEmoji} ${m.typeLabel}] $dateStr — ${m.authorName}',
        );
        if (m.title != null && m.title!.isNotEmpty) {
          memoryBuffer.writeln('Название: ${m.title}');
        }
        if (m.caption != null && m.caption!.isNotEmpty) {
          memoryBuffer.writeln('Заметка: ${m.caption}');
        }
        if (m.locationName != null && m.locationName!.isNotEmpty) {
          memoryBuffer.writeln('Место: ${m.locationName}');
        }

        // Try downloading photo if it exists
        if (m.imageUrl != null &&
            m.imageUrl!.isNotEmpty &&
            m.imageUrl!.startsWith('http')) {
          try {
            final response = await http
                .get(Uri.parse(m.imageUrl!))
                .timeout(const Duration(seconds: 15));
            if (response.statusCode == 200) {
              final photoName =
                  'Photos/${m.createdAt.year}_${m.createdAt.month.toString().padLeft(2, '0')}_${m.createdAt.day.toString().padLeft(2, '0')}_Photo_$photoCounter.jpg';
              archive.addFile(
                ArchiveFile(
                  photoName,
                  response.bodyBytes.length,
                  response.bodyBytes,
                ),
              );
              memoryBuffer.writeln('Фото сохранено как: $photoName');
              photoCounter++;
            }
          } catch (e) {
            debugPrint('Failed to download image ${m.imageUrl}: $e');
            memoryBuffer.writeln('Фото: ${m.imageUrl}'); // fallback
          }
        }
        memoryBuffer.writeln('--------------------');
      }
      final memoryBytes = memoryBuffer.toString().codeUnits;
      archive.addFile(
        ArchiveFile('Memories.txt', memoryBytes.length, memoryBytes),
      );

      // 4. Save ZIP and Share
      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);

      final tempDir = await getTemporaryDirectory();
      final zipFile = File(
        '${tempDir.path}/LoveApp_Export_${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      await zipFile.writeAsBytes(zipData);

      // Share
      await Share.shareXFiles([
        XFile(zipFile.path),
      ], text: 'Архив воспоминаний');
    } catch (e) {
      debugPrint('Export Error: $e');
      throw Exception('Ошибка при экспорте архива: $e');
    }
  }
}
