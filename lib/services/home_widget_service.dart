import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';
import '../models/timer_item.dart';

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

  /// Последний известный статус группы — для обратной совместимости.
  String _lastRelationshipStatusId = '';

  /// Последний известный флаг романтической темы — fallback в syncTimer.
  bool _lastIsRomantic = true;

  /// Последний известный индекс темы приложения — fallback в syncTimer.
  int _lastThemeIndex = 0;

  // ════════════════════════════════════════════════════════════════════════
  //  ПРИВЯЗКА ВИДЖЕТОВ К ГРУППАМ
  // ════════════════════════════════════════════════════════════════════════

  static const _boundGroupPrefix = 'widget_bound_group_';
  static const _photoSaveMemoryPrefix = 'photo_day_save_memory_';
  static const _photoRefreshSeedPrefix = 'photo_day_refresh_seed_';
  static const _photoDayPendingConfigsKey = 'photo_day_pending_configs';
  static const _widgetChannel = MethodChannel('love_app/widgets');

  /// Привязать тип виджета к группе (вызывается при пине).
  Future<void> bindWidgetToGroup(String widgetType, String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_boundGroupPrefix$widgetType', groupId);

    debugPrint('HomeWidgetService: $widgetType bound to group $groupId');
  }

  Future<List<int>> getPhotoDayWidgetIds() async {
    if (!Platform.isAndroid) return const [];
    try {
      final ids = await _widgetChannel.invokeListMethod<dynamic>(
        'getPhotoDayWidgetIds',
      );
      return ids
              ?.map((id) => id is int ? id : int.tryParse(id.toString()))
              .whereType<int>()
              .toList() ??
          const [];
    } catch (e) {
      debugPrint('HomeWidgetService.getPhotoDayWidgetIds failed: $e');
      return const [];
    }
  }

  Future<List<int>> getPhotoGridWidgetIds() async {
    if (!Platform.isAndroid) return const [];
    try {
      final ids = await _widgetChannel.invokeListMethod<dynamic>(
        'getPhotoGridWidgetIds',
      );
      return ids
              ?.map((id) => id is int ? id : int.tryParse(id.toString()))
              .whereType<int>()
              .toList() ??
          const [];
    } catch (e) {
      debugPrint('HomeWidgetService.getPhotoGridWidgetIds failed: $e');
      return const [];
    }
  }

  String _photoDayWidgetKey(int widgetId, String suffix) =>
      'photo_day_widget_${widgetId}_$suffix';

  Future<void> enqueuePhotoDayWidgetConfig({
    required String groupId,
    required String mode,
    String kind = 'self',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_photoDayPendingConfigsKey);
    final List<dynamic> pending = current == null || current.isEmpty
        ? []
        : (jsonDecode(current) as List<dynamic>);
    pending.add({
      'groupId': groupId,
      'mode': mode,
      'kind': kind,
      'path': '',
      'caption': '',
      'memoryId': '',
      'authorName': '',
      'authorUid': '',
      'viewerUid': '',
      'viewerName': '',
      'refreshSeed': 0,
    });
    await prefs.setString(_photoDayPendingConfigsKey, jsonEncode(pending));
  }

  Future<String> getPhotoDayWidgetMode(
    int widgetId, {
    String? fallbackGroupId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final widgetMode = prefs.getString(_photoDayWidgetKey(widgetId, 'mode'));
    if (widgetMode != null && widgetMode.isNotEmpty) return widgetMode;
    return 'custom';
  }

  Future<void> setPhotoDayWidgetMode(int widgetId, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoDayWidgetKey(widgetId, 'mode'), mode);
  }

  Future<String> getPhotoDayWidgetKind(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_photoDayWidgetKey(widgetId, 'kind'));
    if (stored != null && stored.isNotEmpty) return stored;
    final homeWidgetStored = await HomeWidget.getWidgetData<String>(
      _photoDayWidgetKey(widgetId, 'kind'),
    );
    if (homeWidgetStored != null && homeWidgetStored.isNotEmpty) {
      await prefs.setString(_photoDayWidgetKey(widgetId, 'kind'), homeWidgetStored);
      return homeWidgetStored;
    }
    final legacyDisplay = prefs.getString(
      _photoDayWidgetKey(widgetId, 'display'),
    );
    return legacyDisplay == 'partner' ? 'partner' : 'self';
  }

  Future<String?> getPhotoDayWidgetStoredKind(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_photoDayWidgetKey(widgetId, 'kind'));
    if (stored == null || stored.isEmpty) return null;
    return stored;
  }

  Future<String> getPhotoDayWidgetDisplay(int widgetId) async {
    final kind = await getPhotoDayWidgetKind(widgetId);
    return kind == 'partner' ? 'partner' : 'mine';
  }

  Future<Map<String, String>?> _getPartnerWidgetData(
    String groupId,
    String currentUserUid,
  ) async {
    if (groupId.isEmpty || currentUserUid.isEmpty) return null;

    final snap = await _db
        .collection('groups')
        .doc(groupId)
        .collection('widgetData')
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final uid = data['uid'] as String? ?? '';
      if (uid.isNotEmpty && uid != currentUserUid) {
        final sharedUrls = List<String>.from(
          data['photoForPartnerUrls'] ?? data['photoDayUrls'] ?? [],
        );
        return {
          'photoUrl':
              data['photoForPartnerUrl'] as String? ??
              data['photoDayUrl'] as String? ??
              '',
          'photoUrls': sharedUrls.join(','),
          'authorName': data['displayName'] as String? ?? '',
          'authorUid': uid,
        };
      }
    }

    // Партнёр ещё не открывал настройки виджетов — его документ widgetData
    // не существует. Берём UID из массива members группы, чтобы random-fallback
    // мог фильтровать Memory Lane по автору.
    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return null;
      final members = List<String>.from(groupDoc.data()?['members'] ?? []);
      final memberNames = Map<String, dynamic>.from(
        groupDoc.data()?['memberNames'] ?? {},
      );
      final partnerUid = members.firstWhere(
        (uid) => uid != currentUserUid,
        orElse: () => '',
      );
      if (partnerUid.isEmpty) return null;
      return {
        'photoUrl': '',
        'photoUrls': '',
        'authorName': memberNames[partnerUid] as String? ?? '',
        'authorUid': partnerUid,
      };
    } catch (e) {
      debugPrint('_getPartnerWidgetData group fallback failed: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _getMyWidgetData(
    String groupId,
    String currentUserUid,
  ) async {
    if (groupId.isEmpty || currentUserUid.isEmpty) return null;

    final doc = await _db
        .collection('groups')
        .doc(groupId)
        .collection('widgetData')
        .doc(currentUserUid)
        .get();

    if (!doc.exists || doc.data() == null) return null;

    return {
      'authorName': (doc.data()!)['displayName'] as String? ?? '',
      'authorUid': currentUserUid,
    };
  }

  Future<void> _clearPhotoOfDay({
    required int widgetId,
    String? groupId,
    String authorName = '',
    String authorUid = '',
  }) async {
    await _savePhotoDayWidgetData(widgetId, {
      'path': '',
      'caption': '',
      'memory_id': '',
      'author': authorName,
      'author_uid': authorUid,
      if (groupId != null) 'group_id': groupId,
    });

    await HomeWidget.updateWidget(
      name: 'PhotoDayWidgetProvider',
      androidName: 'PhotoDayWidgetProvider',
    );
  }

  Future<void> clearPhotoDayWidget(int widgetId, String groupId) async {
    await _clearPhotoOfDay(widgetId: widgetId, groupId: groupId);
  }

  Future<List<int>> getPhotoDayWidgetIdsByKind(String kind) async {
    final ids = await getPhotoDayWidgetIds();
    final filtered = <int>[];
    for (final id in ids) {
      if (await getPhotoDayWidgetKind(id) == kind) {
        filtered.add(id);
      }
    }
    return filtered;
  }

  Future<String?> getPhotoDayWidgetName(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_photoDayWidgetKey(widgetId, 'name'));
  }

  Future<void> setPhotoDayWidgetName(int widgetId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoDayWidgetKey(widgetId, 'name'), name);
  }

  Future<String?> getPhotoDayWidgetGroupId(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_photoDayWidgetKey(widgetId, 'group_id'));
    if (stored != null && stored.isNotEmpty) return stored;

    final homeWidgetStored = await HomeWidget.getWidgetData<String>(
      _photoDayWidgetKey(widgetId, 'group_id'),
    );
    if (homeWidgetStored != null && homeWidgetStored.isNotEmpty) {
      await prefs.setString(
        _photoDayWidgetKey(widgetId, 'group_id'),
        homeWidgetStored,
      );
      return homeWidgetStored;
    }

    return stored;
  }

  Future<String?> getPhotoDayWidgetCustomPath(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_photoDayWidgetKey(widgetId, 'custom_path'));
  }

  Future<void> setPhotoDayWidgetCustomPath(int widgetId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoDayWidgetKey(widgetId, 'custom_path'), path);
  }

  Future<int> getPhotoDayWidgetRefreshSeed(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_photoDayWidgetKey(widgetId, 'refresh_seed')) ?? 0;
  }

  Future<int> incrementPhotoDayWidgetRefreshSeed(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final next =
        (prefs.getInt(_photoDayWidgetKey(widgetId, 'refresh_seed')) ?? 0) + 1;
    await prefs.setInt(_photoDayWidgetKey(widgetId, 'refresh_seed'), next);
    return next;
  }

  Future<String> getPhotoDayWidgetRotationType(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_photoDayWidgetKey(widgetId, 'rotation_type')) ??
        'unlock';
  }

  Future<void> setPhotoDayWidgetRotationType(int widgetId, String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoDayWidgetKey(widgetId, 'rotation_type'), type);
    // Дублируем в HomeWidgetPreferences, чтобы нативный PhotoDayRotationReceiver мог прочитать.
    await HomeWidget.saveWidgetData<String>(
      _photoDayWidgetKey(widgetId, 'rotation_type'),
      type,
    );
  }

  Future<int> getPhotoDayWidgetRotationInterval(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_photoDayWidgetKey(widgetId, 'rotation_interval')) ??
        60;
  }

  Future<void> setPhotoDayWidgetRotationInterval(
    int widgetId,
    int minutes,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _photoDayWidgetKey(widgetId, 'rotation_interval'),
      minutes,
    );
    // Дублируем в HomeWidgetPreferences, чтобы нативный PhotoDayRotationReceiver мог прочитать.
    await HomeWidget.saveWidgetData<int>(
      _photoDayWidgetKey(widgetId, 'rotation_interval'),
      minutes,
    );
  }

  /// URL-ы фото конкретного виджета (независимо от других экземпляров).
  /// Хранится в SharedPreferences под ключом `photo_day_widget_{id}_urls`.
  Future<List<String>> getPhotoDayWidgetUrls(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_photoDayWidgetKey(widgetId, 'urls'));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> setPhotoDayWidgetUrls(int widgetId, List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _photoDayWidgetKey(widgetId, 'urls'),
      jsonEncode(urls),
    );
  }

  Future<void> clearPhotoDayWidgetUrls(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_photoDayWidgetKey(widgetId, 'urls'));
  }

  Future<Map<String, String?>> getPhotoDayWidgetPreview(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'path': prefs.getString(_photoDayWidgetKey(widgetId, 'path')),
      'memoryId': prefs.getString(_photoDayWidgetKey(widgetId, 'memory_id')),
      'authorName': prefs.getString(_photoDayWidgetKey(widgetId, 'author')),
      'authorUid': prefs.getString(_photoDayWidgetKey(widgetId, 'author_uid')),
      'mode': prefs.getString(_photoDayWidgetKey(widgetId, 'mode')),
      'kind': prefs.getString(_photoDayWidgetKey(widgetId, 'kind')),
      'groupId': prefs.getString(_photoDayWidgetKey(widgetId, 'group_id')),
    };
  }

  Future<void> _savePhotoDayWidgetData(
    int widgetId,
    Map<String, String> values,
  ) async {
    for (final entry in values.entries) {
      final key = _photoDayWidgetKey(widgetId, entry.key);
      if (entry.key == 'refresh_seed' || entry.key == 'rotation_interval') {
        await HomeWidget.saveWidgetData<int>(
          key,
          int.tryParse(entry.value) ?? 0,
        );
      } else {
        await HomeWidget.saveWidgetData<String>(key, entry.value);
      }
    }
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
  /// [groupId]    — идентификатор группы (обязательный).
  /// [daysCount]  — количество дней (int).
  /// [coupleNames] — «Алекс & Юля».
  /// [emoji]       — эмодзи отношений (❤️).
  /// [startDate]   — дата начала в читаемом формате (01.06.2024).
  Future<void> syncDaysCounter({
    required String groupId,
    required int daysCount,
    required String coupleNames,
    String emoji = '❤️',
    String startDate = '',
    String myGender = '',
    String partnerGender = '',
  }) async {
    try {
      final g = groupId;
      await HomeWidget.saveWidgetData<String>(
        'days_${g}_count',
        daysCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>('days_${g}_couple_names', coupleNames);
      await HomeWidget.saveWidgetData<String>('days_${g}_relationship_emoji', emoji);
      await HomeWidget.saveWidgetData<String>('days_${g}_start_date', startDate);
      await HomeWidget.saveWidgetData<String>('days_${g}_my_gender', myGender);
      await HomeWidget.saveWidgetData<String>('days_${g}_partner_gender', partnerGender);
      // Save latest group for fallback binding
      await HomeWidget.saveWidgetData<String>('days_latest_group', groupId);
      await HomeWidget.updateWidget(
        name: 'DaysCounterWidgetProvider',
        androidName: 'DaysCounterWidgetProvider',
      );
      debugPrint('HomeWidgetService: days counter synced — $daysCount days (group=$groupId)');
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
  /// [groupId] — идентификатор группы (обязательный).
  Future<void> syncTimer(
    TimerItem timer, {
    required String groupId,
    bool isRomantic = true,
    int themeIndex = 0,
  }) async {
    try {
      final g = groupId;
      debugPrint(
        'HomeWidgetService.syncTimer: START title=${timer.title} startMs=${timer.startDate.millisecondsSinceEpoch} group=$g',
      );
      if (isRomantic) _lastIsRomantic = true;
      _lastThemeIndex = themeIndex;

      await HomeWidget.saveWidgetData<String>('timer_${g}_title', timer.title);
      await HomeWidget.saveWidgetData<String>(
        'timer_${g}_days',
        timer.daysElapsed.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'timer_${g}_is_countdown',
        timer.isCountdown ? '1' : '0',
      );
      await HomeWidget.saveWidgetData<String>(
        'timer_${g}_date',
        timer.formattedStartDate,
      );
      // Дата старта в мс — нужна PetalTimerWidgetProvider для вычисления лепестков
      await HomeWidget.saveWidgetData<String>(
        'timer_${g}_start_ms',
        timer.startDate.millisecondsSinceEpoch.toString(),
      );
      // Флаг темы: 1 = романтическая (сердце/розовый), 0 = нейтральная (звезда/жёлтый)
      await HomeWidget.saveWidgetData<String>(
        'timer_${g}_is_romantic',
        isRomantic ? '1' : '0',
      );
      // Индекс темы приложения (0=pink,1=purple,2=blue,3=orange,4=green) для лепесткового виджета
      await HomeWidget.saveWidgetData<String>(
        'timer_${g}_petal_theme',
        themeIndex.toString(),
      );
      // Save latest group for fallback binding
      await HomeWidget.saveWidgetData<String>('timer_latest_group', groupId);
      await HomeWidget.saveWidgetData<String>('petal_timer_latest_group', groupId);
      await HomeWidget.updateWidget(
        name: 'TimerWidgetProvider',
        androidName: 'TimerWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'PetalTimerWidgetProvider',
        androidName: 'PetalTimerWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: timer synced — ${timer.title}, days=${timer.daysElapsed}, startMs=${timer.startDate.millisecondsSinceEpoch}, group=$g',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncTimer failed: $e');
    }
  }

  /// Очистить данные таймера в виджете
  Future<void> clearTimerWidget() async {
    try {
      await HomeWidget.saveWidgetData<String>('timer_title', '');
      await HomeWidget.saveWidgetData<String>('timer_days', '0');
      await HomeWidget.saveWidgetData<String>('timer_emoji', '❤️');
      await HomeWidget.saveWidgetData<String>('timer_is_countdown', '0');
      await HomeWidget.saveWidgetData<String>('timer_date', '');
      await HomeWidget.saveWidgetData<String>('timer_start_ms', '0');
      await HomeWidget.updateWidget(
        name: 'TimerWidgetProvider',
        androidName: 'TimerWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'PetalTimerWidgetProvider',
        androidName: 'PetalTimerWidgetProvider',
      );
      debugPrint('HomeWidgetService: timer widget cleared');
    } catch (e) {
      debugPrint('HomeWidgetService.clearTimerWidget failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  3. ФОТО ДНЯ  (Memory Lane)
  // ════════════════════════════════════════════════════════════════════════

  Future<void> syncPhotoOfDayCarousel({
    required List<String> photoUrls, // can be network URLs or local file paths
    String authorName = '',
    String authorUid = '',
    int? widgetId,
    String? groupId,
  }) async {
    try {
      final viewerUid = FirebaseService().uid ?? '';
      String viewerName = '';
      if (viewerUid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(viewerUid).get();
        viewerName = userDoc.data()?['displayName'] ?? '';
      }

      List<String> localPaths = [];
      final dir = await getApplicationSupportDirectory();

      for (int i = 0; i < photoUrls.length; i++) {
        final url = photoUrls[i];
        if (url.startsWith('http')) {
          final p = await _cachePhotoFromUrl(
            url,
            'photo_day_carousel_${widgetId}_$i',
          );
          if (p.isNotEmpty) localPaths.add(p);
        } else {
          final file = File(url);
          if (file.existsSync()) {
            final suffix = widgetId != null ? '_${widgetId}_$i' : '_$i';
            final target = File('${dir.path}/widget_photo_day$suffix.jpg');
            await file.copy(target.path);
            localPaths.add(target.path);
          }
        }
      }

      final pathsJson = jsonEncode(localPaths);

      if (widgetId != null) {
        // Determine kind from widgetId
        final kind = await getPhotoDayWidgetKind(widgetId);
        await _savePhotoDayWidgetData(widgetId, {
          'paths': pathsJson,
          // for backward compatibility or the first image
          'path': localPaths.isNotEmpty ? localPaths.first : '',
          'author': authorName,
          'author_uid': authorUid,
          'viewer_uid': viewerUid,
          'viewer_name': viewerName,
          'kind': kind,
          if (groupId != null) 'group_id': groupId,
        });

        // Ensure rotation mechanism is initialized in Kotlin
        await _widgetChannel.invokeMethod('updatePhotoDayCarousel', {
          'widgetId': widgetId,
          'paths': localPaths,
        });
      }

      await HomeWidget.updateWidget(
        name: 'PhotoDayWidgetProvider',
        androidName: 'PhotoDayWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: carousel synced — ${localPaths.length} photos',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.syncPhotoOfDayCarousel failed: $e');
    }
  }

  Future<void> syncPhotoOfDay({
    required String photoUrl,
    String caption = '',
    String memoryId = '',
    String authorName = '',
    String authorUid = '',
    File? localFile,
    int? widgetId,
    String? groupId,
    int? refreshSeed,
  }) async {
    try {
      String localPath = '';
      if (localFile != null) {
        // Если передали файл напрямую (с устройства) — копируем его в кэш виджета
        final dir = await getApplicationSupportDirectory();
        final suffix = widgetId != null ? '_$widgetId' : '';
        final file = File('${dir.path}/widget_photo_day$suffix.jpg');
        await localFile.copy(file.path);
        localPath = file.path;
      } else {
        localPath = await _cachePhotoFromUrl(
          photoUrl,
          widgetId != null ? 'photo_day_$widgetId' : 'photo_day',
        );
      }

      final viewerUid = FirebaseService().uid ?? '';
      String viewerName = '';
      if (viewerUid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(viewerUid).get();
        viewerName = userDoc.data()?['displayName'] ?? '';
      }

      if (widgetId != null) {
        // Determine kind from widgetId
        final kind = await getPhotoDayWidgetKind(widgetId);
        await _savePhotoDayWidgetData(widgetId, {
          'path': localPath,
          'caption': caption,
          'memory_id': memoryId,
          'author': authorName,
          'author_uid': authorUid,
          'viewer_uid': viewerUid,
          'viewer_name': viewerName,
          'kind': kind,
          if (groupId != null) 'group_id': groupId,
          if (refreshSeed != null) 'refresh_seed': refreshSeed.toString(),
        });
      } else {
        await HomeWidget.saveWidgetData<String>('photo_day_path', localPath);
        await HomeWidget.saveWidgetData<String>('photo_day_caption', caption);
        await HomeWidget.saveWidgetData<String>(
          'photo_day_memory_id',
          memoryId,
        );
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
      }
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

  /// Выбирает фото для виджета "Фото дня" и синхронизирует его.
  ///
  /// [forceNext] — если true, инкрементирует seed, чтобы выбрать следующее фото.
  /// [widgetId] — конкретный ID виджета (null = все виджеты этого groupId).
  /// Works for both group mode and single user mode (no group).
  Future<void> refreshPhotoOfDay(
    String groupId, {
    bool forceNext = false,
    int? widgetId,
  }) async {
    try {
      // If no widgetId specified, refresh all photo day widgets for this group
      if (widgetId == null) {
        final allIds = await getPhotoDayWidgetIds();
        for (final id in allIds) {
          final widgetGroupId = await getPhotoDayWidgetGroupId(id);
          // Sync if: no group bound, or bound to current group, or no groupId at all (single user)
          if (widgetGroupId == null ||
              widgetGroupId.isEmpty ||
              widgetGroupId == groupId) {
            await refreshPhotoOfDay(
              groupId,
              widgetId: id,
              forceNext: forceNext,
            );
          }
        }
        return;
      }

      // Single user mode (no group): use widget's own stored URLs
      if (groupId.isEmpty) {
        await _syncPhotoDayWidgetSingleUser(widgetId, forceNext: forceNext);
        return;
      }

      final selectedKind = await getPhotoDayWidgetKind(widgetId);

      // Сохраняем текущий профиль (viewer) для различения моего/партнёрского фото
      final currentUserUid = FirebaseService().uid ?? '';
      String currentUserName = '';
      if (currentUserUid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(currentUserUid).get();
        currentUserName = userDoc.data()?['displayName'] ?? '';
      }

      await _savePhotoDayWidgetData(widgetId, {
        'viewer_uid': currentUserUid,
        'viewer_name': currentUserName,
        'mode': 'custom',
        'kind': selectedKind,
        'group_id': groupId,
      });

      final List<String> ownWidgetUrls = await getPhotoDayWidgetUrls(widgetId);

      Map<String, String>? targetData;
      if (selectedKind == 'partner') {
        targetData = await _getPartnerWidgetData(groupId, currentUserUid);
      } else {
        targetData = await _getMyWidgetData(groupId, currentUserUid);
      }

      final targetPhotoUrl = targetData?['photoUrl'] ?? '';
      final targetPhotoUrlsRaw = targetData?['photoUrls'] ?? '';
      List<String> targetPhotoUrls = targetPhotoUrlsRaw.isNotEmpty
          ? targetPhotoUrlsRaw.split(',')
          : [];

      if (selectedKind != 'partner' && ownWidgetUrls.isNotEmpty) {
        targetPhotoUrls = ownWidgetUrls;
      }

      final bool targetHasCustomPhoto = selectedKind == 'partner'
          ? (targetPhotoUrl.isNotEmpty || targetPhotoUrls.isNotEmpty)
          : ownWidgetUrls.isNotEmpty;

      if (targetHasCustomPhoto) {
        debugPrint(
          'HomeWidgetService: showing photo '
          '(kind=$selectedKind) '
          'author=${targetData?['authorName']} uid=${targetData?['authorUid']}',
        );

        if (targetPhotoUrls.length > 1) {
          await syncPhotoOfDayCarousel(
            photoUrls: targetPhotoUrls,
            authorName: targetData?['authorName'] ?? '',
            authorUid: targetData?['authorUid'] ?? '',
            widgetId: widgetId,
            groupId: groupId,
          );
        } else {
          await syncPhotoOfDay(
            photoUrl: targetPhotoUrls.isNotEmpty
                ? targetPhotoUrls.first
                : targetPhotoUrl,
            caption: '',
            memoryId: '',
            authorName: targetData?['authorName'] ?? '',
            authorUid: targetData?['authorUid'] ?? '',
            widgetId: widgetId,
            groupId: groupId,
          );
        }
        return;
      }

      await _clearPhotoOfDay(
        widgetId: widgetId,
        groupId: groupId,
        authorName: targetData?['authorName'] ?? '',
        authorUid: targetData?['authorUid'] ?? '',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.refreshPhotoOfDay failed: $e');
    }
  }

  /// Синхронизация фото виджета для одиночного режима (без группы).
  /// Использует собственные URL-ы виджета.
  Future<void> _syncPhotoDayWidgetSingleUser(
    int widgetId, {
    bool forceNext = false,
  }) async {
    try {
      final currentUserUid = FirebaseService().uid ?? '';
      String currentUserName = '';
      if (currentUserUid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(currentUserUid).get();
        currentUserName = userDoc.data()?['displayName'] ?? '';
      }

      final selectedKind = await getPhotoDayWidgetKind(widgetId);
      final widgetName = await getPhotoDayWidgetName(widgetId);

      await _savePhotoDayWidgetData(widgetId, {
        'viewer_uid': currentUserUid,
        'viewer_name': currentUserName,
        'mode': 'custom',
        'kind': selectedKind,
        'group_id': '',
      });

      // For single user, use widget's own stored URLs
      final ownUrls = await getPhotoDayWidgetUrls(widgetId);
      final customPath = await getPhotoDayWidgetCustomPath(widgetId);

      if (ownUrls.isNotEmpty) {
        // Select photo based on seed
        final seed = forceNext
            ? await incrementPhotoDayWidgetRefreshSeed(widgetId)
            : await getPhotoDayWidgetRefreshSeed(widgetId);
        final index = seed % ownUrls.length;
        final selectedUrl = ownUrls[index];

        await _savePhotoDayWidgetData(widgetId, {
          'photo_url': selectedUrl,
          'refresh_seed': seed.toString(),
          'author_name': currentUserName,
          'author_uid': currentUserUid,
        });
      } else if (customPath != null && customPath.isNotEmpty) {
        // Use custom local photo
        await _savePhotoDayWidgetData(widgetId, {
          'path': customPath,
          'refresh_seed': '0',
          'author_name': currentUserName,
          'author_uid': currentUserUid,
        });
      } else {
        // No photos - clear
        await _savePhotoDayWidgetData(widgetId, {
          'photo_url': '',
          'refresh_seed': '0',
        });
      }

      await HomeWidget.updateWidget(
        name: 'PhotoDayWidgetProvider',
        androidName: 'PhotoDayWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService: photo day (single user) synced for widget $widgetId',
      );
    } catch (e) {
      debugPrint('HomeWidgetService._syncPhotoDayWidgetSingleUser failed: $e');
    }
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

        // Временно очищаем виджет
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
  /// [moodColor]                 — цвет моего настроения (hex).
  /// [userName]                  — моё имя.
  /// [partnerMoodEmojiAssetPath] — путь к ассету эмодзи партнёра.
  /// [partnerMoodLabel]          — текстовое название настроения партнёра.
  /// [partnerMoodColor]          — цвет настроения партнёра (hex).
  /// [partnerUserName]           — имя партнёра.
  /// [noMoodText]                — локализованный текст «нет настроения».
  /// [nameFallbackMe]            — локализованный «Я/Me».
  /// [nameFallbackPartner]       — локализованный «Партнёр/Partner».
  /// [ratingPrefix]              — локализованный «Оценка/Rating».
  Future<void> syncMood({
    required String groupId,
    required String moodEmojiAssetPath,
    required String moodLabel,
    required int moodScore,
    String moodColor = '',
    String userName = '',
    String partnerMoodEmojiAssetPath = '',
    String partnerMoodLabel = '',
    String partnerMoodColor = '',
    required int partnerMoodScore,
    String partnerUserName = '',
    String noMoodText = '',
    String nameFallbackMe = '',
    String nameFallbackPartner = '',
    String ratingPrefix = '',
  }) async {
    if (moodEmojiAssetPath.isEmpty &&
        moodLabel.isEmpty &&
        moodScore == 0 &&
        partnerMoodEmojiAssetPath.isEmpty &&
        partnerMoodLabel.isEmpty &&
        partnerMoodScore == 0) {
      debugPrint('HomeWidgetService.syncMood skipped: no mood data to save');
      return;
    }

    try {
      final g = groupId;
      // ── Моё настроение ──
      String myLocalPath = '';
      if (moodEmojiAssetPath.isNotEmpty) {
        myLocalPath = await _copyAssetToLocal(moodEmojiAssetPath);
      }
      await HomeWidget.saveWidgetData<String>('mood_emoji_path', myLocalPath);
      await HomeWidget.saveWidgetData<String>('mood_label', moodLabel);
      await HomeWidget.saveWidgetData<String>('mood_user_name', userName);
      await HomeWidget.saveWidgetData<int>('mood_score', moodScore);
      await HomeWidget.saveWidgetData<String>('mood_color', moodColor);
      await HomeWidget.saveWidgetData<int>('user_count', 2);
      await HomeWidget.saveWidgetData<String>('user_0_emoji_path', myLocalPath);
      await HomeWidget.saveWidgetData<String>('user_0_name', userName);
      await HomeWidget.saveWidgetData<String>('user_0_label', moodLabel);
      // Group-prefixed score, color and label keys (read by MoodWidgetProvider)
      await HomeWidget.saveWidgetData<int>('mood_${g}_user_0_score', moodScore);
      await HomeWidget.saveWidgetData<String>('mood_${g}_user_0_color', moodColor);
      await HomeWidget.saveWidgetData<String>('mood_${g}_user_0_label', moodLabel);

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
      await HomeWidget.saveWidgetData<String>(
        'user_1_emoji_path',
        partnerLocalPath,
      );
      await HomeWidget.saveWidgetData<String>('user_1_name', partnerUserName);
      await HomeWidget.saveWidgetData<String>('user_1_label', partnerMoodLabel);
      // Group-prefixed score, color and label keys (read by MoodWidgetProvider)
      await HomeWidget.saveWidgetData<int>('mood_${g}_user_1_score', partnerMoodScore);
      await HomeWidget.saveWidgetData<String>('mood_${g}_user_1_color', partnerMoodColor);
      await HomeWidget.saveWidgetData<String>('mood_${g}_user_1_label', partnerMoodLabel);
      await HomeWidget.saveWidgetData<int>(
        'partner_mood_score',
        partnerMoodScore,
      );
      // Save latest group for fallback binding
      await HomeWidget.saveWidgetData<String>('mood_latest_group', groupId);

      // ── Локализованные строки для нативного виджета ──
      await HomeWidget.saveWidgetData<String>(
        'no_mood_text',
        noMoodText.isNotEmpty ? noMoodText : 'Пока нет данных',
      );
      await HomeWidget.saveWidgetData<String>(
        'name_fallback_me',
        nameFallbackMe.isNotEmpty ? nameFallbackMe : 'Вы',
      );
      await HomeWidget.saveWidgetData<String>(
        'name_fallback_partner',
        nameFallbackPartner.isNotEmpty ? nameFallbackPartner : 'Партнёр',
      );
      await HomeWidget.saveWidgetData<String>(
        'rating_prefix',
        ratingPrefix.isNotEmpty ? ratingPrefix : 'Оценка',
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
  /// [groupId] — идентификатор группы (обязательный).
  Future<void> syncRelationshipStats({
    required String groupId,
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
      final g = groupId;
      await HomeWidget.saveWidgetData<String>(
        'stats_${g}_days',
        daysTogether.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats_${g}_memories',
        memoriesCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats_${g}_drawings',
        drawingsCount.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats_${g}_miss_you',
        missYouCount.toString(),
      );

      if (daysLabel != null)
        await HomeWidget.saveWidgetData<String>('stats_${g}_days_label', daysLabel);
      if (memoriesLabel != null)
        await HomeWidget.saveWidgetData<String>(
          'stats_${g}_memories_label',
          memoriesLabel,
        );
      if (drawingsLabel != null)
        await HomeWidget.saveWidgetData<String>(
          'stats_${g}_drawings_label',
          drawingsLabel,
        );
      if (missYouLabel != null)
        await HomeWidget.saveWidgetData<String>(
          'stats_${g}_miss_you_label',
          missYouLabel,
        );

      // Save latest group for fallback binding
      await HomeWidget.saveWidgetData<String>('stats_latest_group', groupId);

      await HomeWidget.updateWidget(
        name: 'RelationshipStatsWidgetProvider',
        androidName: 'RelationshipStatsWidgetProvider',
      );
      debugPrint('HomeWidgetService: relationship stats synced (group=$groupId)');
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
        groupId: groupId,
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
    String relationshipStatusId = '',
    bool isRomantic = true,
    int themeIndex = 0,
  }) async {
    try {
      debugPrint(
        'HomeWidgetService.syncAllBoundWidgets: activeGroup=$activeGroupId',
      );

      // ── Days Counter ──
      debugPrint('  days_counter → syncing (activeGroup=$activeGroupId)');
      await _syncDaysCounterFromMemory(
        activeGroupId: activeGroupId,
        activeSysTimer: activeSysTimer,
        activeStartDate: activeStartDate,
        coupleNames: coupleNames,
        emoji: emoji,
        myGender: myGender,
        partnerGender: partnerGender,
      );

      // ── Timer ──
      debugPrint('  timer → syncing (activeGroup=$activeGroupId)');
      await _syncTimerFromMemory(
        activeTimers: activeTimers,
        groupId: activeGroupId,
        relationshipStatusId: relationshipStatusId,
        isRomantic: isRomantic,
        themeIndex: themeIndex,
      );

      // ── Photo of Day ──
      final widgetIds = await getPhotoDayWidgetIds();
      if (widgetIds.isEmpty) {
        await refreshPhotoOfDay(activeGroupId);
      } else {
        for (final widgetId in widgetIds) {
          final widgetGroupId = await getPhotoDayWidgetGroupId(widgetId);
          // For solo mode (empty activeGroupId), sync widgets without bound group or with empty group
          final shouldSync = activeGroupId.isEmpty
              ? (widgetGroupId == null || widgetGroupId.isEmpty)
              : (widgetGroupId == null || widgetGroupId == activeGroupId);
          if (shouldSync) {
            debugPrint(
              '  photo_day#$widgetId → syncing (group=$widgetGroupId)',
            );
            await refreshPhotoOfDay(activeGroupId, widgetId: widgetId);
          }
        }
      }

      // ── Relationship Stats ──
      debugPrint('  relationship_stats → syncing (activeGroup=$activeGroupId)');
      await refreshRelationshipStats(
        activeGroupId,
        startDate: activeSysTimer?.startDate ?? activeStartDate,
      );

      // ── Mood — привязан к пользователю, не к группе ──
      // (mood синхронизируется в WidgetService при изменении)
    } catch (e) {
      debugPrint('HomeWidgetService.syncAllBoundWidgets failed: $e');
    }
  }

  /// Синхронизирует счётчик дней из данных в памяти (текущая группа).
  Future<void> _syncDaysCounterFromMemory({
    required String activeGroupId,
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
        groupId: activeGroupId,
        daysCount: activeSysTimer.daysElapsed.abs(),
        coupleNames: coupleNames,
        emoji: activeSysTimer.emoji,
        startDate: _formatDate(start),
        myGender: myGender,
        partnerGender: partnerGender,
      );
    } else if (activeStartDate != null) {
      await syncDaysCounter(
        groupId: activeGroupId,
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
    String relationshipStatusId = '',
    bool isRomantic = true,
    int themeIndex = 0,
  }) async {
    if (activeTimers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('widget_timer_id_$groupId');
    TimerItem? timer;
    if (savedId != null) {
      try {
        timer = activeTimers.firstWhere((t) => t.id == savedId);
      } catch (_) {}
    }
    // Fallback: default timer first (includes system/relationship timer),
    // then first non-system, then any timer.
    timer ??= activeTimers.firstWhere(
      (t) => t.isDefault,
      orElse: () => activeTimers.firstWhere(
        (t) => !t.isSystem,
        orElse: () => activeTimers.first,
      ),
    );
    await syncTimer(timer, groupId: groupId, isRomantic: isRomantic, themeIndex: themeIndex);
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

  /// Читает настройки ПАРТНЁРА из Firestore (photoGridCount + photoGridUrls),
  /// скачивает/кэширует фото и отправляет их в нативный виджет.
  /// Данные сохраняются per-widgetId, чтобы каждый экземпляр был уникальным.
  Future<void> refreshPhotoGrid(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      final currentUserUid = FirebaseService().uid ?? '';

      // Ищем документ партнёра в widgetData
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('widgetData')
          .get();

      Map<String, dynamic>? partnerRaw;
      for (final doc in snap.docs) {
        final uid = doc.data()['uid'] as String? ?? '';
        if (uid.isNotEmpty && uid != currentUserUid) {
          partnerRaw = doc.data();
          break;
        }
      }

      if (partnerRaw == null) {
        debugPrint('HomeWidgetService.refreshPhotoGrid: no partner data');
        return;
      }

      final count = (partnerRaw['photoGridCount'] as int?) ?? 1;
      final urls = List<String>.from(partnerRaw['photoGridUrls'] ?? []);

      // Кэшируем фото один раз (одинаковые для всех экземпляров)
      final List<String> localPaths = [];
      for (int i = 0; i < 4; i++) {
        final url = i < urls.length ? urls[i] : '';
        if (url.isNotEmpty) {
          final localPath = await _cachePhotoFromUrl(url, 'photo_grid_$i');
          localPaths.add(localPath);
        } else {
          localPaths.add('');
        }
      }

      // Сохраняем per-widget ключи для каждого экземпляра
      final widgetIds = await getPhotoGridWidgetIds();
      if (widgetIds.isEmpty) {
        // Fallback: глобальные ключи (если виджетов нет ещё — для совместимости)
        await HomeWidget.saveWidgetData<int>('photo_grid_count', count);
        for (int i = 0; i < 4; i++) {
          await HomeWidget.saveWidgetData<String>(
            'photo_grid_$i',
            localPaths[i],
          );
        }
      } else {
        for (final widgetId in widgetIds) {
          await HomeWidget.saveWidgetData<int>(
            'photo_grid_${widgetId}_count',
            count,
          );
          for (int i = 0; i < 4; i++) {
            await HomeWidget.saveWidgetData<String>(
              'photo_grid_${widgetId}_$i',
              localPaths[i],
            );
          }
        }
      }

      await HomeWidget.updateWidget(
        name: 'PhotoGridWidgetProvider',
        androidName: 'PhotoGridWidgetProvider',
      );
      debugPrint(
        'HomeWidgetService.refreshPhotoGrid: count=$count, urls=$urls, widgets=$widgetIds',
      );
    } catch (e) {
      debugPrint('HomeWidgetService.refreshPhotoGrid failed: $e');
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
