import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';
import '../models/timer_item.dart';
import '../models/memory.dart';

/// Сервис для синхронизации данных всех виджетов рабочего стола
/// (кроме основного парного виджета [LoveWidgetProvider],
///  который обновляется в [WidgetService]).
///
/// Каждый тип виджета привязан к конкретной группе (groupId).
/// При синхронизации виджет ВСЕГДА обновляется данными **своей** группы,
/// даже если сейчас активна другая группа.
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
  //  ПРИВЯЗКА ВИДЖЕТОВ К ГРУППАМ
  // ════════════════════════════════════════════════════════════════════════

  static const _boundGroupPrefix = 'widget_bound_group_';
  static const _photoModePrefix = 'photo_day_mode_';
  static const _photoSaveMemoryPrefix = 'photo_day_save_memory_';
  static const _photoRefreshSeedPrefix = 'photo_day_refresh_seed_';

  /// Привязать тип виджета к группе (вызывается при пине).
  Future<void> bindWidgetToGroup(String widgetType, String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_boundGroupPrefix$widgetType', groupId);

    // Если это фото дня и режим не задан — ставим по умолчанию random
    if (widgetType == 'photo_day') {
      if (prefs.getString('$_photoModePrefix$groupId') == null) {
        await prefs.setString('$_photoModePrefix$groupId', 'random');
      }
    }

    debugPrint('HomeWidgetService: $widgetType bound to group $groupId');
  }

  Future<String> getPhotoDayMode(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_photoModePrefix$groupId') ?? 'random';
  }

  Future<void> setPhotoDayMode(String groupId, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_photoModePrefix$groupId', mode);
  }

  Future<bool> getPhotoDaySaveMemory(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_photoSaveMemoryPrefix$groupId') ?? true;
  }

  Future<void> setPhotoDaySaveMemory(String groupId, bool save) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_photoSaveMemoryPrefix$groupId', save);
  }

  Future<int> getPhotoRefreshSeed(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_photoRefreshSeedPrefix$groupId') ?? 0;
  }

  Future<int> incrementPhotoRefreshSeed(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt('$_photoRefreshSeedPrefix$groupId') ?? 0) + 1;
    await prefs.setInt('$_photoRefreshSeedPrefix$groupId', next);
    return next;
  }

  /// Получить groupId, к которому привязан виджет. null = не привязан.
  Future<String?> getBoundGroup(String widgetType) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_boundGroupPrefix$widgetType');
  }

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
    String myGender = '',
    String partnerGender = '',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        'days_count',
        daysCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>('couple_names', coupleNames);
      await HomeWidget.saveWidgetData<String>('relationship_emoji', emoji);
      await HomeWidget.saveWidgetData<String>('start_date_label', startDate);
      await HomeWidget.saveWidgetData<String>(
        'my_gender',
        myGender.isNotEmpty ? myGender : 'male',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_gender',
        partnerGender.isNotEmpty ? partnerGender : 'female',
      );
      await HomeWidget.updateWidget(
        name: 'DaysCounterWidgetProvider',
        androidName: 'DaysCounterWidgetProvider',
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
        androidName: 'TimerWidgetProvider',
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
    String authorUid = '',
    File? localFile,
  }) async {
    try {
      String localPath = '';
      if (localFile != null) {
        // Если передали файл напрямую (с устройства) — копируем его в кэш виджета
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/widget_photo_day.jpg');
        await localFile.copy(file.path);
        localPath = file.path;
      } else {
        localPath = await _cachePhotoFromUrl(photoUrl, 'photo_day');
      }

      final viewerUid = FirebaseService().uid ?? '';
      String viewerName = '';
      if (viewerUid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(viewerUid).get();
        viewerName = userDoc.data()?['displayName'] ?? '';
      }

      await HomeWidget.saveWidgetData<String>('photo_day_path', localPath);
      await HomeWidget.saveWidgetData<String>('photo_day_caption', caption);
      await HomeWidget.saveWidgetData<String>('photo_day_memory_id', memoryId);
      await HomeWidget.saveWidgetData<String>('photo_day_author', authorName);
      await HomeWidget.saveWidgetData<String>(
        'photo_day_author_uid',
        authorUid,
      );
      await HomeWidget.saveWidgetData<String>(
        'photo_day_viewer_uid',
        viewerUid,
      );
      await HomeWidget.saveWidgetData<String>(
        'photo_day_viewer_name',
        viewerName,
      );
      await HomeWidget.updateWidget(
        name: 'PhotoDayWidgetProvider',
        androidName: 'PhotoDayWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: photo of day synced — $memoryId (path=$localPath)',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncPhotoOfDay failed: $e');
    }
  }

  /// Выбирает последнее фото из Memory Lane и синхронизирует виджет.
  ///
  /// [forceNext] — если true, инкрементирует seed, чтобы выбрать следующее фото.
  Future<void> refreshPhotoOfDay(
    String groupId, {
    bool forceNext = false,
  }) async {
    if (groupId.isEmpty) return;
    try {
      final mode = await getPhotoDayMode(groupId);

      // Сохраняем текущий профиль (viewer) для различения моего/партнёрского фото
      final currentUserUid = FirebaseService().uid ?? '';
      String currentUserName = '';
      if (currentUserUid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(currentUserUid).get();
        currentUserName = userDoc.data()?['displayName'] ?? '';
      }
      await HomeWidget.saveWidgetData<String>(
        'photo_day_viewer_uid',
        currentUserUid,
      );
      await HomeWidget.saveWidgetData<String>(
        'photo_day_viewer_name',
        currentUserName,
      );

      final partnerData = await _getPartnerWidgetData(groupId, currentUserUid);
      final partnerMode = partnerData?['photoDayMode'] ?? 'random';
      final partnerPhotoUrl = partnerData?['photoUrl'] ?? '';

      // ── Матрица режимов ──
      // Рабочий стол ВСЕГДА показывает фото ПАРТНЁРА:
      // • random + custom  → кастомное фото партнёра
      // • custom + custom  → кастомное фото партнёра
      // • custom + random  → случайное (фото партнёра — random)
      // • random + random  → случайное (общее для обоих)
      final bool partnerHasCustomPhoto =
          partnerMode == 'custom' && partnerPhotoUrl.isNotEmpty;

      if (partnerHasCustomPhoto) {
        // Партнёр выбрал конкретное фото — показываем его
        debugPrint(
          'HomeWidgetService: showing partner custom photo '
          '(partnerMode=$partnerMode, myMode=$mode) '
          'author=${partnerData!['authorName']} uid=${partnerData['authorUid']}',
        );
        await syncPhotoOfDay(
          photoUrl: partnerPhotoUrl,
          caption: '',
          memoryId: '',
          authorName: partnerData['authorName'] ?? '',
          authorUid: partnerData['authorUid'] ?? '',
        );
        return;
      }

      // В остальных случаях (random+random или custom+random) —
      // показываем случайное фото из Memory Lane
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

      final allMemories = snap.docs
          .map((doc) => Memory.fromFirestore(doc.id, doc.data()))
          .toList();

      // Предпочитаем фото партнёра: он выбрал фото из памяти, а не я
      final partnerMemories = partnerData != null
          ? allMemories
                .where((m) => m.authorUid == partnerData['authorUid'])
                .toList()
          : <Memory>[];
      final candidateMemories = partnerMemories.isNotEmpty
          ? partnerMemories
          : allMemories;

      // Получаем (и при необходимости инкрементируем) сдвиг
      final seed = forceNext
          ? await incrementPhotoRefreshSeed(groupId)
          : await getPhotoRefreshSeed(groupId);

      final selectedMemory = _pickDailyRandomMemory(
        candidateMemories,
        groupId,
        seed,
      );
      if (selectedMemory == null ||
          selectedMemory.imageUrl == null ||
          selectedMemory.imageUrl!.isEmpty) {
        debugPrint('HomeWidgetService: selected random memory has no image');
        return;
      }

      await syncPhotoOfDay(
        photoUrl: selectedMemory.imageUrl!,
        caption: selectedMemory.caption ?? '',
        memoryId: selectedMemory.id,
        authorName: selectedMemory.authorName,
        authorUid: selectedMemory.authorUid,
      );
    } catch (e) {
      debugPrint('HomeWidgetService.refreshPhotoOfDay failed: $e');
    }
  }

  /// Ищет информацию о партнёре из widgetData.
  /// Возвращает данные партнёра вне зависимости от наличия photoUrl.
  Future<Map<String, String>?> _getPartnerWidgetData(
    String groupId,
    String currentUserUid,
  ) async {
    try {
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('widgetData')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? '';
        if (uid.isEmpty || uid == currentUserUid) continue;

        final photoUrl = data['photoUrl'] as String? ?? '';
        final mode = data['photoDayMode'] as String? ?? 'random';

        // Возвращаем данные партнёра вне зависимости от наличия фотографии
        return {
          'authorUid': uid,
          'authorName': data['displayName'] as String? ?? '',
          'photoUrl': photoUrl,
          'photoDayMode': mode,
        };
      }
    } catch (e) {
      debugPrint('HomeWidgetService._getPartnerWidgetData failed: $e');
    }
    return null;
  }

  Memory? _pickDailyRandomMemory(
    List<Memory> memories,
    String groupId, [
    int seed = 0,
  ]) {
    if (memories.isEmpty) return null;
    final sorted = List<Memory>.from(memories)
      ..sort((a, b) => a.id.compareTo(b.id));
    final dayIndex = DateTime.now().difference(DateTime(2000)).inDays;
    final hash = groupId.hashCode ^ dayIndex;
    // seed сдвигает индекс, позволяя выбирать разные фото при повторных нажатиях
    final index = (hash.abs() + seed) % sorted.length;
    return sorted[index];
  }

  /// Вызывается при удалении воспоминания, чтобы убрать его из виджете, если оно там отображалось
  Future<void> handleMemoryDeleted(
    String groupId,
    String deletedMemoryId,
  ) async {
    try {
      final currentMemoryId = await HomeWidget.getWidgetData<String>(
        'photo_day_memory_id',
      );
      if (currentMemoryId == deletedMemoryId) {
        debugPrint(
          'HomeWidgetService: Deleted memory was displayed in widget. Updating...',
        );

        // Если это был кастомный режим (свое фото), переключаем обратно в random
        final mode = await getPhotoDayMode(groupId);
        if (mode == 'custom') {
          await setPhotoDayMode(groupId, 'random');
        }

        // Временно очищаем виджет (на случай если это было последнее фото)
        await HomeWidget.saveWidgetData<String>('photo_day_path', '');
        await HomeWidget.saveWidgetData<String>('photo_day_caption', '');
        await HomeWidget.saveWidgetData<String>('photo_day_memory_id', '');
        await HomeWidget.saveWidgetData<String>('photo_day_author', '');
        await HomeWidget.updateWidget(
          name: 'PhotoDayWidgetProvider',
          androidName: 'PhotoDayWidgetProvider',
        );

        // Пытаемся загрузить новое случайное фото
        await refreshPhotoOfDay(groupId);
      }
    } catch (e) {
      debugPrint('HomeWidgetService.handleMemoryDeleted failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  4. НАСТРОЕНИЕ
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует виджет настроения.
  ///
  /// [moodEmojiAssetPath]        — путь к ассету моего эмодзи (напр. 'assets/images/emoji/033-love.png').
  /// [moodLabel]                 — текстовое название моего настроения.
  /// [userName]                  — моё имя.
  /// [partnerMoodEmojiAssetPath] — путь к ассету эмодзи партнёра.
  /// [partnerMoodLabel]          — текстовое название настроения партнёра.
  /// [partnerUserName]           — имя партнёра.
  Future<void> syncMood({
    required String moodEmojiAssetPath,
    required String moodLabel,
    String userName = '',
    String partnerMoodEmojiAssetPath = '',
    String partnerMoodLabel = '',
    String partnerUserName = '',
  }) async {
    try {
      // ── Моё настроение ──
      String myLocalPath = '';
      if (moodEmojiAssetPath.isNotEmpty) {
        myLocalPath = await _copyAssetToLocal(moodEmojiAssetPath);
      }
      await HomeWidget.saveWidgetData<String>('mood_emoji_path', myLocalPath);
      await HomeWidget.saveWidgetData<String>('mood_label', moodLabel);
      await HomeWidget.saveWidgetData<String>('mood_user_name', userName);

      // ── Настроение партнёра ──
      String partnerLocalPath = '';
      if (partnerMoodEmojiAssetPath.isNotEmpty) {
        partnerLocalPath = await _copyAssetToLocal(partnerMoodEmojiAssetPath);
      }
      await HomeWidget.saveWidgetData<String>(
        'partner_mood_emoji_path',
        partnerLocalPath,
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_mood_label',
        partnerMoodLabel,
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_mood_user_name',
        partnerUserName,
      );

      await HomeWidget.updateWidget(
        name: 'MoodWidgetProvider',
        androidName: 'MoodWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: mood synced — me=$moodLabel, partner=$partnerMoodLabel',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncMood failed: $e');
    }
  }

  /// Синхронизирует данные настроения для MoodWidgetProvider (групповой формат до 4 человек).
  ///
  /// [members] — список мап, где ключи 'name' и 'emojiPath'.
  Future<void> syncGroupMood(List<Map<String, String>> members) async {
    try {
      await HomeWidget.saveWidgetData<int>('user_count', members.length);
      for (int i = 0; i < members.length; i++) {
        final member = members[i];
        final emojiAsset = member['emojiPath'] ?? '';
        String localPath = '';
        if (emojiAsset.isNotEmpty) {
          localPath = await _copyAssetToLocal(emojiAsset);
        }
        await HomeWidget.saveWidgetData<String>(
          'user_${i}_emoji_path',
          localPath,
        );
        await HomeWidget.saveWidgetData<String>(
          'user_${i}_name',
          member['name'] ?? '',
        );
      }

      await HomeWidget.updateWidget(
        name: 'MoodWidgetProvider',
        androidName: 'MoodWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: group mood synced for ${members.length} users',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncGroupMood failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  5. RELATIONSHIP STATS
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует данные для виджета «Статистика отношений».
  Future<void> syncRelationshipStats({
    required int daysTogether,
    required int memoriesCount,
    required int drawingsCount,
    required int missYouCount,
    String? daysLabel,
    String? memoriesLabel,
    String? drawingsLabel,
    String? missYouLabel,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        'stats_days_together',
        daysTogether.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats_memories_count',
        memoriesCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats_drawings_count',
        drawingsCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats_miss_you_count',
        missYouCount.toString(),
      );

      if (daysLabel != null)
        await HomeWidget.saveWidgetData<String>('stats_days_label', daysLabel);
      if (memoriesLabel != null)
        await HomeWidget.saveWidgetData<String>(
          'stats_memories_label',
          memoriesLabel,
        );
      if (drawingsLabel != null)
        await HomeWidget.saveWidgetData<String>(
          'stats_drawings_label',
          drawingsLabel,
        );
      if (missYouLabel != null)
        await HomeWidget.saveWidgetData<String>(
          'stats_miss_you_label',
          missYouLabel,
        );

      await HomeWidget.updateWidget(
        name: 'RelationshipStatsWidgetProvider',
        androidName: 'RelationshipStatsWidgetProvider',
      );
      debugPrint('HomeWidgetService: relationship stats synced');
    } catch (e) {
      debugPrint('HomeWidgetService.syncRelationshipStats failed: $e');
    }
  }

  /// Загружает актуальную статистику из Firestore и синхронизирует виджет.
  Future<void> refreshRelationshipStats(
    String groupId, {
    DateTime? startDate,
  }) async {
    if (groupId.isEmpty) return;
    try {
      // 1. Memories count
      final memSnap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .count()
          .get();

      // 2. Drawings count
      final drawSnap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvases')
          .count()
          .get();

      // 3. Miss You count (упрощенно, если нет прямого доступа к FirebaseService здесь)
      // В идеале передать это извне или иметь централизованный доступ
      int missYouCount = 0;
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (groupDoc.exists) {
        missYouCount = groupDoc.data()?['missYouCount'] ?? 0;
      }

      // 4. Days together
      int days = 0;
      if (startDate != null) {
        days = DateTime.now().difference(startDate).inDays;
      }

      await syncRelationshipStats(
        daysTogether: days,
        memoriesCount: memSnap.count ?? 0,
        drawingsCount: drawSnap.count ?? 0,
        missYouCount: missYouCount,
      );
    } catch (e) {
      debugPrint('HomeWidgetService.refreshRelationshipStats failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  АВТОСИНХРОНИЗАЦИЯ ВСЕХ ВИДЖЕТОВ ПО ПРИВЯЗАННЫМ ГРУППАМ
  // ════════════════════════════════════════════════════════════════════════

  /// Синхронизирует каждый виджет данными из **его** привязанной группы.
  ///
  /// Если виджет привязан к группе, отличной от [activeGroupId], он **не
  /// обновляется** — на рабочем столе остаются данные, записанные последний
  /// раз, когда эта группа была активна. Это гарантирует, что переключение
  /// группы не затирает чужие виджеты.
  ///
  /// Обновляются только:
  ///  • виджеты, привязанные к [activeGroupId]
  ///  • виджеты, не привязанные ни к какой группе (null → текущая)
  Future<void> syncAllBoundWidgets({
    required String activeGroupId,
    required List<TimerItem> activeTimers,
    TimerItem? activeSysTimer,
    DateTime? activeStartDate,
    required String coupleNames,
    required String emoji,
    String myGender = '',
    String partnerGender = '',
  }) async {
    try {
      debugPrint(
        'HomeWidgetService.syncAllBoundWidgets: activeGroup=$activeGroupId',
      );

      // ── Days Counter ──
      final daysGroup = await getBoundGroup('days_counter');
      if (daysGroup == null || daysGroup == activeGroupId) {
        debugPrint('  days_counter → syncing (bound=$daysGroup)');
        await _syncDaysCounterFromMemory(
          activeSysTimer: activeSysTimer,
          activeStartDate: activeStartDate,
          coupleNames: coupleNames,
          emoji: emoji,
          myGender: myGender,
          partnerGender: partnerGender,
        );
      } else {
        debugPrint(
          '  days_counter → SKIP (bound=$daysGroup, active=$activeGroupId)',
        );
      }

      // ── Timer ──
      final timerGroup = await getBoundGroup('timer');
      if (timerGroup == null || timerGroup == activeGroupId) {
        debugPrint('  timer → syncing (bound=$timerGroup)');
        await _syncTimerFromMemory(
          activeTimers: activeTimers,
          groupId: activeGroupId,
        );
      } else {
        debugPrint('  timer → SKIP (bound=$timerGroup, active=$activeGroupId)');
      }

      // ── Photo of Day ──
      final photoGroup = await getBoundGroup('photo_day');
      if (photoGroup == null || photoGroup == activeGroupId) {
        debugPrint('  photo_day → syncing (bound=$photoGroup)');
        await refreshPhotoOfDay(activeGroupId);
      } else {
        debugPrint(
          '  photo_day → SKIP (bound=$photoGroup, active=$activeGroupId)',
        );
      }

      // ── Relationship Stats ──
      final statsGroup = await getBoundGroup('relationship_stats');
      if (statsGroup == null || statsGroup == activeGroupId) {
        debugPrint('  relationship_stats → syncing (bound=$statsGroup)');
        await refreshRelationshipStats(
          activeGroupId,
          startDate: activeSysTimer?.startDate ?? activeStartDate,
        );
      } else {
        debugPrint(
          '  relationship_stats → SKIP (bound=$statsGroup, active=$activeGroupId)',
        );
      }

      // ── Mood — привязан к пользователю, не к группе ──
      // (mood синхронизируется в WidgetService при изменении)
    } catch (e) {
      debugPrint('HomeWidgetService.syncAllBoundWidgets failed: $e');
    }
  }

  /// Синхронизирует счётчик дней из данных в памяти (текущая группа).
  Future<void> _syncDaysCounterFromMemory({
    TimerItem? activeSysTimer,
    DateTime? activeStartDate,
    required String coupleNames,
    required String emoji,
    String myGender = '',
    String partnerGender = '',
  }) async {
    if (activeSysTimer != null) {
      final start = activeSysTimer.startDate;
      await syncDaysCounter(
        daysCount: activeSysTimer.daysElapsed.abs(),
        coupleNames: coupleNames,
        emoji: activeSysTimer.emoji,
        startDate: _formatDate(start),
        myGender: myGender,
        partnerGender: partnerGender,
      );
    } else if (activeStartDate != null) {
      await syncDaysCounter(
        daysCount: DateTime.now().difference(activeStartDate).inDays,
        coupleNames: coupleNames,
        emoji: emoji,
        startDate: _formatDate(activeStartDate),
        myGender: myGender,
        partnerGender: partnerGender,
      );
    }
  }

  /// Синхронизирует таймер из данных в памяти (текущая группа).
  Future<void> _syncTimerFromMemory({
    required List<TimerItem> activeTimers,
    required String groupId,
  }) async {
    final nonSystem = activeTimers.where((t) => !t.isSystem).toList();
    if (nonSystem.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('widget_timer_id_$groupId');
    TimerItem? timer;
    if (savedId != null) {
      try {
        timer = nonSystem.firstWhere((t) => t.id == savedId);
      } catch (_) {}
    }
    timer ??= nonSystem.first;
    await syncTimer(timer);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  // ════════════════════════════════════════════════════════════════════════
  //  ВСПОМОГАТЕЛЬНЫЕ
  // ════════════════════════════════════════════════════════════════════════

  /// Обновляет ВСЕ виджеты рабочего стола (включая парный).
  Future<void> updateAllProviders() async {
    try {
      await HomeWidget.updateWidget(
        name: 'LoveWidgetProvider',
        androidName: 'LoveWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'DaysCounterWidgetProvider',
        androidName: 'DaysCounterWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'TimerWidgetProvider',
        androidName: 'TimerWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'PhotoDayWidgetProvider',
        androidName: 'PhotoDayWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'MoodWidgetProvider',
        androidName: 'MoodWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'RelationshipStatsWidgetProvider',
        androidName: 'RelationshipStatsWidgetProvider',
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

  // ════════════════════════════════════════════════════════════════════════
  //  6. НАСТРОЕНИЕ НА ЭКРАНЕ БЛОКИРОВКИ
  // ════════════════════════════════════════════════════════════════════════

  static const _lockScreenMoodEnabledKey = 'lock_screen_mood_enabled';

  Future<bool> getLockScreenMoodEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lockScreenMoodEnabledKey) ?? false;
  }

  Future<void> setLockScreenMoodEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockScreenMoodEnabledKey, enabled);
  }

  /// Синхронизирует настроение для виджета экрана блокировки.
  ///
  /// [enabled]                   — включён ли виджет.
  /// [moodEmojiAssetPath]        — путь к ассету моего эмодзи.
  /// [moodLabel]                 — моё настроение.
  /// [userName]                  — моё имя.
  /// [partnerMoodEmojiAssetPath] — путь к ассету партнёра.
  /// [partnerMoodLabel]          — настроение партнёра.
  /// [partnerUserName]           — имя партнёра.
  Future<void> syncLockScreenMood({
    required bool enabled,
    required String moodEmojiAssetPath,
    required String moodLabel,
    String userName = '',
    String partnerMoodEmojiAssetPath = '',
    String partnerMoodLabel = '',
    String partnerUserName = '',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        'lock_mood_enabled',
        enabled ? '1' : '0',
      );

      // Моё настроение
      String myLocalPath = '';
      if (enabled && moodEmojiAssetPath.isNotEmpty) {
        myLocalPath = await _copyAssetToLocal(moodEmojiAssetPath);
      }
      await HomeWidget.saveWidgetData<String>(
        'lock_mood_emoji_path',
        myLocalPath,
      );
      await HomeWidget.saveWidgetData<String>(
        'lock_mood_label',
        enabled ? moodLabel : '',
      );
      await HomeWidget.saveWidgetData<String>('lock_mood_user_name', userName);

      // Настроение партнёра
      String partnerLocalPath = '';
      if (enabled && partnerMoodEmojiAssetPath.isNotEmpty) {
        partnerLocalPath = await _copyAssetToLocal(partnerMoodEmojiAssetPath);
      }
      await HomeWidget.saveWidgetData<String>(
        'lock_partner_mood_emoji_path',
        partnerLocalPath,
      );
      await HomeWidget.saveWidgetData<String>(
        'lock_partner_mood_label',
        enabled ? partnerMoodLabel : '',
      );
      await HomeWidget.saveWidgetData<String>(
        'lock_partner_mood_user_name',
        partnerUserName,
      );

      await HomeWidget.updateWidget(
        name: 'LockScreenMoodWidgetProvider',
        androidName: 'LockScreenMoodWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: lock screen mood synced — '
        'enabled=$enabled, me=$moodLabel, partner=$partnerMoodLabel',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncLockScreenMood failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── 7. Фото-сетка ──
  // ═══════════════════════════════════════════════════════════════════════════

  /// Сохраняет количество и пути для виджета «Фото-сетка».
  /// [count] — 1, 2 или 4.
  /// [photoPaths] — локальные пути к файлам (от 1 до 4 элементов).
  Future<void> syncPhotoGrid({
    required int count,
    required List<String> photoPaths,
  }) async {
    try {
      await HomeWidget.saveWidgetData<int>('photo_grid_count', count);
      for (int i = 0; i < 4; i++) {
        final path = i < photoPaths.length ? photoPaths[i] : '';
        await HomeWidget.saveWidgetData<String>('photo_grid_$i', path);
      }
      await HomeWidget.updateWidget(
        name: 'PhotoGridWidgetProvider',
        androidName: 'PhotoGridWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService.syncPhotoGrid: count=$count, paths=$photoPaths',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncPhotoGrid failed: $e');
    }
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
