import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/timer_item.dart';
import '../models/memory.dart';

/// Сервис для синхронизации данных всех виджетов рабочего стола
/// (кроме основного парного виджета [LoveWidgetProvider],
///  который обновляется в [WidgetService]).
///
/// Виджеты:
/// 1. DaysCounterWidgetProvider — счётчик дней вместе
/// 2. TimerWidgetProvider       — таймер / обратный отсчёт
/// 3. PhotoDayWidgetProvider    — фото дня из Memory Lane
/// 4. MoodWidgetProvider        — крупный виджет настроения
class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ════════════════════════════════════════════════════════════════════════
  //  1. СЧЁТЧИК ДНЕЙ ВМЕСТЕ
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует данные для виджета «Дни вместе».
  ///
  /// [daysCount]  — количество дней (int).
  /// [coupleNames] — «Алекс & Юля».
  /// [emoji]       — эмодзи отношений (❤️).
  /// [startDate]   — дата начала в читаемом формате (01.06.2024).
  Future<void> syncDaysCounter({
    required int daysCount,
    required String coupleNames,
    String emoji = '❤️',
    String startDate = '',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        'days_count',
        daysCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>('couple_names', coupleNames);
      await HomeWidget.saveWidgetData<String>('relationship_emoji', emoji);
      await HomeWidget.saveWidgetData<String>('start_date_label', startDate);
      await HomeWidget.updateWidget(
        name: 'DaysCounterWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.DaysCounterWidgetProvider',
      );
      debugPrint('HomeWidgetService: days counter synced — $daysCount days');
    } catch (e) {
      debugPrint('HomeWidgetService.syncDaysCounter failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  2. ТАЙМЕР / ОБРАТНЫЙ ОТСЧЁТ
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует данные выбранного таймера.
  ///
  /// Передаётся [TimerItem] — текущий дефолтный или выбранный таймер.
  Future<void> syncTimer(TimerItem timer) async {
    try {
      await HomeWidget.saveWidgetData<String>('timer_title', timer.title);
      await HomeWidget.saveWidgetData<String>(
        'timer_days',
        timer.daysElapsed.toString(),
      );
      await HomeWidget.saveWidgetData<String>('timer_emoji', timer.emoji);
      await HomeWidget.saveWidgetData<String>(
        'timer_is_countdown',
        timer.isCountdown ? '1' : '0',
      );
      await HomeWidget.saveWidgetData<String>(
        'timer_date',
        timer.formattedStartDate,
      );
      await HomeWidget.updateWidget(
        name: 'TimerWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.TimerWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: timer synced — ${timer.title}, ${timer.daysElapsed}d',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncTimer failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  3. ФОТО ДНЯ  (Memory Lane)
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует конкретное фото для виджета «Фото дня».
  Future<void> syncPhotoOfDay({
    required String photoUrl,
    String caption = '',
    String memoryId = '',
    String authorName = '',
  }) async {
    try {
      final localPath = await _cachePhotoFromUrl(photoUrl, 'photo_day');
      await HomeWidget.saveWidgetData<String>('photo_day_path', localPath);
      await HomeWidget.saveWidgetData<String>('photo_day_caption', caption);
      await HomeWidget.saveWidgetData<String>('photo_day_memory_id', memoryId);
      await HomeWidget.saveWidgetData<String>('photo_day_author', authorName);
      await HomeWidget.updateWidget(
        name: 'PhotoDayWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.PhotoDayWidgetProvider',
      );
      debugPrint('HomeWidgetService: photo of day synced — $memoryId');
    } catch (e) {
      debugPrint('HomeWidgetService.syncPhotoOfDay failed: $e');
    }
  }

  /// Выбирает случайное фото из Memory Lane и синхронизирует виджет.
  ///
  /// Вызывается при запуске приложения и периодически.
  Future<void> refreshPhotoOfDay(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .where('type', isEqualTo: 'photo')
          .get();

      if (snap.docs.isEmpty) {
        debugPrint('HomeWidgetService: no photo memories for photo of day');
        return;
      }

      final random = Random();
      final doc = snap.docs[random.nextInt(snap.docs.length)];
      final memory = Memory.fromFirestore(doc.id, doc.data());

      if (memory.imageUrl != null && memory.imageUrl!.isNotEmpty) {
        await syncPhotoOfDay(
          photoUrl: memory.imageUrl!,
          caption: memory.caption ?? '',
          memoryId: memory.id,
          authorName: memory.authorName,
        );
      }
    } catch (e) {
      debugPrint('HomeWidgetService.refreshPhotoOfDay failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  4. НАСТРОЕНИЕ
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует виджет настроения.
  ///
  /// [moodEmojiAssetPath] — путь к ассету (напр. 'assets/images/emoji/033-love.png').
  /// [moodLabel]          — текстовое название настроения.
  /// [userName]           — имя пользователя.
  Future<void> syncMood({
    required String moodEmojiAssetPath,
    required String moodLabel,
    String userName = '',
  }) async {
    try {
      String localPath = '';
      if (moodEmojiAssetPath.isNotEmpty) {
        localPath = await _copyAssetToLocal(moodEmojiAssetPath);
      }
      await HomeWidget.saveWidgetData<String>('mood_emoji_path', localPath);
      await HomeWidget.saveWidgetData<String>('mood_label', moodLabel);
      await HomeWidget.saveWidgetData<String>('mood_user_name', userName);
      await HomeWidget.updateWidget(
        name: 'MoodWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.MoodWidgetProvider',
      );
      debugPrint('HomeWidgetService: mood synced — $moodLabel');
    } catch (e) {
      debugPrint('HomeWidgetService.syncMood failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ВСПОМОГАТЕЛЬНЫЕ
  // ════════════════════════════════════════════════════════════════════════

  /// Обновляет ВСЕ виджеты рабочего стола (включая парный).
  Future<void> updateAllProviders() async {
    try {
      await HomeWidget.updateWidget(
        name: 'LoveWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.LoveWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'DaysCounterWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.DaysCounterWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'TimerWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.TimerWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'PhotoDayWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.PhotoDayWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'MoodWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.MoodWidgetProvider',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.updateAllProviders failed: $e');
    }
  }

  // ── Скачать фото по URL в локальный кэш ──
  Future<String> _cachePhotoFromUrl(String url, String key) async {
    if (url.isEmpty) return '';
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/widget_$key.jpg');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('HomeWidgetService: photo cached → ${file.path}');
        return file.path;
      }
    } catch (e) {
      debugPrint('HomeWidgetService._cachePhotoFromUrl failed: $e');
    }
    return '';
  }

  // ── Скопировать Flutter-ассет (emoji PNG) в локальный файл ──
  Future<String> _copyAssetToLocal(String assetPath) async {
    if (assetPath.isEmpty) return '';
    try {
      final dir = await getApplicationSupportDirectory();
      final fileName = assetPath.split('/').last;
      final file = File('${dir.path}/widget_mood_$fileName');

      // Если уже скопировано — не копируем повторно
      if (file.existsSync()) return file.path;

      final bytes = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      debugPrint('HomeWidgetService: asset copied → ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('HomeWidgetService._copyAssetToLocal failed: $e');
    }
    return '';
  }
}
