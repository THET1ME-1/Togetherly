import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_form_entry.dart';

void main() {
  // Обращение Sávio (1.43): задание «A calming video for the evening»
  // открывало форму без ссылки и без файла.
  test('задание со ссылкой на видео открывает форму видео на вкладке ссылки',
      () {
    final linkTasks =
        DailyTask.all.where((t) => t.type == MemoryType.videoLink).toList();
    expect(linkTasks, isNotEmpty);
    for (final task in linkTasks) {
      final entry = memoryFormEntry(task.type);
      expect(entry.type, MemoryType.video, reason: task.id);
      expect(entry.byLink, isTrue, reason: task.id);
    }
  });

  test('прочие типы идут в свою форму без вкладки ссылки', () {
    for (final type in [MemoryType.location, MemoryType.music]) {
      final entry = memoryFormEntry(type);
      expect(entry.type, type);
      expect(entry.byLink, isFalse);
    }
  });

  test('лента открывает форму-лист через memoryFormEntry', () {
    final src = File('lib/screens/memory_lane_screen.dart').readAsStringSync();
    expect(src, contains('final entry = memoryFormEntry(type);'));
    expect(src, contains('_showCreateMemoryForm(entry.type, startWithUrl: entry.byLink)'));
  });
}
