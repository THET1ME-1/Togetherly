оба человекimport 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/widget_data.dart';
import '../models/memory.dart';
import '../models/mood_entry.dart';
import 'firebase_service.dart';
import 'home_widget_service.dart';

/// Сервис для синхронизации виджет-данных между партнёрами.
///
/// Firestore path: `groups/{groupId}/widgetData/{uid}`
///
/// Поддерживает автоматическую отправку в Memory Lane и Mood Calendar.
class WidgetService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  String _groupId = '';
  String get groupId => _groupId;

  // ── Данные виджетов ──
  WidgetData? _myData;
  final Map<String, WidgetData> _partnerData = {};

  WidgetData? get myData => _myData;
  WidgetData? partnerDataOf(String uid) => _partnerData[uid];

  /// Первый партнёр (для пары) — удобный геттер
  WidgetData? get firstPartnerData =>
      _partnerData.isNotEmpty ? _partnerData.values.first : null;

  // ── Подписки ──
  StreamSubscription? _mySub;
  final Map<String, StreamSubscription> _partnerSubs = {};

  // ── Настройки автоотправки ──
  bool _autoSendPhotoToMemory = true;
  bool _autoSendMessageToMemory = true;
  bool _autoSendMusicToMemory = true;
  bool _autoSendMoodToCalendar = true;

  bool get autoSendPhotoToMemory => _autoSendPhotoToMemory;
  bool get autoSendMessageToMemory => _autoSendMessageToMemory;
  bool get autoSendMusicToMemory => _autoSendMusicToMemory;
  bool get autoSendMoodToCalendar => _autoSendMoodToCalendar;

  // ══════════════════════════════════════════════════════════════════════════
  // INIT
  // ══════════════════════════════════════════════════════════════════════════

  /// Привязка к группе. Начинает слушать свой виджет.
  Future<void> bindToGroup(String groupId) async {
    if (groupId.isEmpty || groupId == _groupId) return;
    _groupId = groupId;
    await _loadSettings();
    _listenToMyData();
    notifyListeners();
  }

  /// Подписка на виджет-данные партнёра
  void listenToPartner(String partnerUid) {
    if (partnerUid.isEmpty || _groupId.isEmpty) return;
    if (_partnerSubs.containsKey(partnerUid)) return;

    final ref = _db
        .collection('groups')
        .doc(_groupId)
        .collection('widgetData')
        .doc(partnerUid);

    _partnerSubs[partnerUid] = ref.snapshots().listen((snap) {
      if (_isDisposed) return;
      if (snap.exists && snap.data() != null) {
        _partnerData[partnerUid] = WidgetData.fromFirestore(snap.data()!);
      } else {
        _partnerData[partnerUid] = WidgetData(uid: partnerUid);
      }
      _syncToNativeWidget();
      notifyListeners();
    }, onError: (e) => debugPrint('WidgetService partner listener error: $e'));
  }

  void _listenToMyData() {
    final uid = _fb.currentUser?.uid;
    if (uid == null || _groupId.isEmpty) return;

    _mySub?.cancel();
    final ref = _db
        .collection('groups')
        .doc(_groupId)
        .collection('widgetData')
        .doc(uid);

    _mySub = ref.snapshots().listen((snap) {
      if (_isDisposed) return;
      if (snap.exists && snap.data() != null) {
        _myData = WidgetData.fromFirestore(snap.data()!);
      } else {
        _myData = WidgetData(uid: uid);
      }
      _syncToNativeWidget();
      notifyListeners();
    }, onError: (e) => debugPrint('WidgetService my data listener error: $e'));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UPDATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Обновить статус
  Future<void> updateStatus(String status) async {
    await _updateField({'status': status});
  }

  /// Обновить настроение (emoji).
  /// [skipCalendar] — передай true если moodService.addMood уже добавил запись,
  /// чтобы не создавать дубль.
  Future<void> updateMood(
    String emojiPath,
    String label, {
    bool skipCalendar = false,
  }) async {
    await _updateField({'moodEmoji': emojiPath, 'moodLabel': label});

    // Автоотправка в календарь — только если не пропускаем
    if (!skipCalendar && _autoSendMoodToCalendar && _groupId.isNotEmpty) {
      try {
        final uid = _fb.currentUser?.uid ?? '';
        final now = DateTime.now();
        final id = '${uid}_${now.millisecondsSinceEpoch}';
        // Ищем корректный moodId по imagePath
        final option = MoodOption.all.cast<MoodOption?>().firstWhere(
          (m) => m!.imagePath == emojiPath,
          orElse: () => null,
        );
        final entry = MoodEntry(
          id: id,
          moodId: option?.id ?? label.toLowerCase().replaceAll(' ', '_'),
          imagePath: emojiPath,
          label: label,
          timestamp: now,
        );
        await _fb.addMoodEntry(groupId: _groupId, entry: entry.toFirestore());
      } catch (e) {
        debugPrint('Widget → Calendar failed: $e');
      }
    }
  }

  /// Обновить сообщение
  Future<void> updateMessage(String message) async {
    await _updateField({'message': message});

    // Автоотправка в Memory Lane
    if (_autoSendMessageToMemory && message.isNotEmpty && _groupId.isNotEmpty) {
      try {
        await _fb.addMemory(
          groupId: _groupId,
          type: MemoryType.text,
          caption: '💬 $message',
        );
      } catch (e) {
        debugPrint('Widget → Memory (msg) failed: $e');
      }
    }
  }

  /// Обновить фото
  Future<void> updatePhoto(String localPath) async {
    // Загрузка в Storage
    final uid = _fb.currentUser?.uid ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dest = 'widget/$_groupId/${uid}_$ts.jpg';
    final url = await _fb.uploadFile(localPath, dest);
    if (url == null) return;

    await _updateField({'photoUrl': url});

    // Автоотправка в Memory Lane
    if (_autoSendPhotoToMemory && _groupId.isNotEmpty) {
      try {
        await _fb.addMemory(
          groupId: _groupId,
          type: MemoryType.photo,
          imageUrl: url,
          caption: '📸 Виджет',
        );
      } catch (e) {
        debugPrint('Widget → Memory (photo) failed: $e');
      }
    }
  }

  /// Обновить фото по URL (уже загружено)
  Future<void> updatePhotoUrl(String url) async {
    await _updateField({'photoUrl': url});
  }

  /// Обновить режим PhotoDay (random/custom)
  Future<void> setPhotoDayMode(String mode) async {
    await _updateField({'photoDayMode': mode});
  }

  /// Обновить музыку
  Future<void> updateMusic({
    required String title,
    required String artist,
    String? url,
    String? coverUrl,
  }) async {
    await _updateField({
      'musicTitle': title,
      'musicArtist': artist,
      'musicUrl': url,
      'musicCoverUrl': coverUrl,
    });

    // Автоотправка в Memory Lane
    if (_autoSendMusicToMemory && _groupId.isNotEmpty) {
      try {
        await _fb.addMemory(
          groupId: _groupId,
          type: MemoryType.music,
          musicTitle: title,
          musicArtist: artist,
          musicUrl: url,
          musicCoverUrl: coverUrl,
        );
      } catch (e) {
        debugPrint('Widget → Memory (music) failed: $e');
      }
    }
  }

  /// Очистить конкретный слот
  Future<void> clearStatus() => _updateField({'status': ''});
  Future<void> clearMood() => _updateField({'moodEmoji': '', 'moodLabel': ''});
  Future<void> clearMessage() => _updateField({'message': ''});
  Future<void> clearPhoto() => _updateField({'photoUrl': null});
  Future<void> clearMusic() => _updateField({
    'musicTitle': null,
    'musicArtist': null,
    'musicUrl': null,
    'musicCoverUrl': null,
  });

  /// Очистить все данные виджета
  Future<void> clearAll() async {
    await _updateField({
      'status': '',
      'moodEmoji': '',
      'moodLabel': '',
      'message': '',
      'photoUrl': null,
      'musicTitle': null,
      'musicArtist': null,
      'musicUrl': null,
      'musicCoverUrl': null,
    });
  }

  Future<void> _updateField(Map<String, dynamic> fields) async {
    final uid = _fb.currentUser?.uid;
    if (uid == null || _groupId.isEmpty) return;

    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      final name =
          userDoc.data()?['displayName'] ?? _fb.currentUser?.displayName ?? '';
      final avatar =
          userDoc.data()?['avatarUrl'] ?? _fb.currentUser?.photoURL ?? '';
      final gender = userDoc.data()?['gender'] ?? '';

      final ref = _db
          .collection('groups')
          .doc(_groupId)
          .collection('widgetData')
          .doc(uid);

      await ref.set({
        'uid': uid,
        'displayName': name,
        'avatarUrl': avatar,
        'gender': gender,
        'updatedAt': FieldValue.serverTimestamp(),
        ...fields,
      }, SetOptions(merge: true));

      // Синхронизируем нативный виджет сразу после записи,
      // не дожидаясь Firestore-листенера (Xiaomi убивает процесс слишком быстро)
      await _syncToNativeWidget();
    } catch (e) {
      debugPrint('WidgetService._updateField failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> setAutoSendPhotoToMemory(bool value) async {
    _autoSendPhotoToMemory = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setAutoSendMessageToMemory(bool value) async {
    _autoSendMessageToMemory = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setAutoSendMusicToMemory(bool value) async {
    _autoSendMusicToMemory = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setAutoSendMoodToCalendar(bool value) async {
    _autoSendMoodToCalendar = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoSendPhotoToMemory =
          prefs.getBool('widget_autoSendPhotoToMemory') ?? true;
      _autoSendMessageToMemory =
          prefs.getBool('widget_autoSendMessageToMemory') ?? true;
      _autoSendMusicToMemory =
          prefs.getBool('widget_autoSendMusicToMemory') ?? true;
      _autoSendMoodToCalendar =
          prefs.getBool('widget_autoSendMoodToCalendar') ?? true;
    } catch (e) {
      debugPrint('WidgetService._loadSettings failed: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'widget_autoSendPhotoToMemory',
        _autoSendPhotoToMemory,
      );
      await prefs.setBool(
        'widget_autoSendMessageToMemory',
        _autoSendMessageToMemory,
      );
      await prefs.setBool(
        'widget_autoSendMusicToMemory',
        _autoSendMusicToMemory,
      );
      await prefs.setBool(
        'widget_autoSendMoodToCalendar',
        _autoSendMoodToCalendar,
      );
    } catch (e) {
      debugPrint('WidgetService._saveSettings failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NATIVE HOME SCREEN WIDGET SYNC
  // ══════════════════════════════════════════════════════════════════════════

  /// Синхронизирует данные в SharedPreferences для нативного виджета Android
  Future<void> _syncToNativeWidget() async {
    try {
      // ── Мои данные ──
      final my = _myData;
      // moodEmoji хранит путь к asset-файлу — для нативного виджета
      // используем moodLabel (текстовая метка: «Счастлив», «Грустный» и т.д.)
      await HomeWidget.saveWidgetData<String>(
        'my_name',
        my?.displayName.isNotEmpty == true ? my!.displayName : 'Я',
      );
      await HomeWidget.saveWidgetData<String>('my_mood', my?.moodLabel ?? '');
      await HomeWidget.saveWidgetData<String>('my_status', my?.status ?? '');
      await HomeWidget.saveWidgetData<String>('my_message', my?.message ?? '');
      await HomeWidget.saveWidgetData<String>(
        'my_music_title',
        my?.musicTitle ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'my_music_artist',
        my?.musicArtist ?? '',
      );

      // ── Данные партнёра ──
      final partner = firstPartnerData;
      await HomeWidget.saveWidgetData<String>(
        'partner_name',
        partner?.displayName.isNotEmpty == true
            ? partner!.displayName
            : 'Партнёр',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_mood',
        partner?.moodLabel ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_status',
        partner?.status ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_message',
        partner?.message ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_music_title',
        partner?.musicTitle ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_music_artist',
        partner?.musicArtist ?? '',
      );

      // ── Фото: сохраняем URL, кэшируем локально фоново ──
      await HomeWidget.saveWidgetData<String>(
        'my_photo_url',
        my?.photoUrl ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_photo_url',
        partner?.photoUrl ?? '',
      );

      // ── Аватарки для 2-человечного виджета (LoveWidget) ──
      // LoveWidget всё ещё использует старые ключи для 2 людей
      await HomeWidget.saveWidgetData<String>(
        'my_avatar_url',
        my?.avatarUrl ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_avatar_url',
        partner?.avatarUrl ?? '',
      );

      // ── Обновить виджет на рабочем столе (текстовые данные сразу) ──
      await HomeWidget.updateWidget(
        name: 'LoveWidgetProvider',
        androidName: 'LoveWidgetProvider',
      );
      debugPrint(
        'NativeWidget: synced — my=${my?.displayName}, partner=${partner?.displayName}',
      );

      // ── Синхронизируем виджет настроения для группы (до 4 человек) ──
      // Фильтруем текущего пользователя из partnerData, чтобы не было дублирования аватарок
      final myUid = _fb.currentUser?.uid ?? '';
      final membersForWidget = <WidgetData>[];
      if (my != null) membersForWidget.add(my);
      membersForWidget.addAll(_partnerData.values.where((d) => d.uid != myUid));
      final limitedMembers = membersForWidget.take(4).toList();

      final membersData = limitedMembers
          .map(
            (m) => {
              'name': m.displayName.isNotEmpty ? m.displayName : 'Участник',
              'emojiPath': m.moodEmoji,
            },
          )
          .toList();
      await HomeWidgetService.instance.syncGroupMood(membersData);

      for (int i = 0; i < limitedMembers.length; i++) {
        await HomeWidget.saveWidgetData<String>(
          'user_${i}_avatar_url',
          limitedMembers[i].avatarUrl,
        );
      }

      // Кэшируем эмодзи из assets → локальные файлы для нативного виджета (фоново)
      Future.wait([
        _cacheEmojiForWidget(my?.moodEmoji, 'my_mood_emoji_path'),
        _cacheEmojiForWidget(partner?.moodEmoji, 'partner_mood_emoji_path'),
      ]).then((_) async {
        try {
          await HomeWidget.updateWidget(
            name: 'LoveWidgetProvider',
            androidName: 'LoveWidgetProvider',
          );
        } catch (e) {
          debugPrint('WidgetService emoji update failed: $e');
        }
      });

      // Скачиваем фото и аватарки локально в фоне и обновляем виджет повторно
      _cachePhotosForWidget(my?.photoUrl, partner?.photoUrl);
      _cacheAvatarsForLoveWidget(my?.avatarUrl, partner?.avatarUrl);
      _cacheGroupAvatarsForWidget(limitedMembers);

      // Если PhotoDay в custom режиме, пересинхронизируем его, чтобы показать фото партнёра
      try {
        final mode = await HomeWidgetService.instance.getPhotoDayMode(_groupId);
        if (mode == 'custom' && _groupId.isNotEmpty) {
          await HomeWidgetService.instance.refreshPhotoOfDay(_groupId);
        }
      } catch (e) {
        debugPrint('WidgetService: refresh PhotoDay on custom mode failed: $e');
      }
    } catch (e) {
      debugPrint('WidgetService._syncToNativeWidget failed: $e');
    }
  }

  /// Скачивает фото в локальный кэш и обновляет нативный виджет (LoveWidget).
  void _cachePhotosForWidget(String? myUrl, String? partnerUrl) {
    Future.wait([
      _downloadPhoto(myUrl, 'my_photo_path'),
      _downloadPhoto(partnerUrl, 'partner_photo_path'),
    ]).then((_) async {
      try {
        await HomeWidget.updateWidget(
          name: 'LoveWidgetProvider',
          androidName: 'LoveWidgetProvider',
        );
      } catch (e) {
        debugPrint('WidgetService._cachePhotosForWidget update failed: $e');
      }
    });
  }

  /// Скачивает аватарки для парного виджета (LoveWidget) в локальный кэш.
  void _cacheAvatarsForLoveWidget(String? myUrl, String? partnerUrl) {
    Future.wait([
      _downloadPhoto(myUrl, 'my_avatar_path'),
      _downloadPhoto(partnerUrl, 'partner_avatar_path'),
    ]).then((_) async {
      try {
        await HomeWidget.updateWidget(
          name: 'LoveWidgetProvider',
          androidName: 'LoveWidgetProvider',
        );
      } catch (e) {
        debugPrint(
          'WidgetService._cacheAvatarsForLoveWidget update failed: $e',
        );
      }
    });
  }

  /// Скачивает аватарки группы в локальный кэш и обновляет MoodWidget.
  void _cacheGroupAvatarsForWidget(List<WidgetData> members) {
    final futures = <Future<void>>[];
    for (int i = 0; i < members.length; i++) {
      futures.add(
        _downloadPhoto(members[i].avatarUrl, 'user_${i}_avatar_path'),
      );
    }
    Future.wait(futures).then((_) async {
      try {
        await HomeWidget.updateWidget(
          name: 'MoodWidgetProvider',
          androidName: 'MoodWidgetProvider',
        );
      } catch (e) {
        debugPrint(
          'WidgetService._cacheGroupAvatarsForWidget update failed: $e',
        );
      }
    });
  }

  /// Копирует Flutter asset с эмодзи в файловый кэш и сохраняет путь
  /// под ключом [key] в SharedPreferences нативного виджета.
  Future<void> _cacheEmojiForWidget(String? assetPath, String key) async {
    if (assetPath == null || assetPath.isEmpty) {
      await HomeWidget.saveWidgetData<String>(key, '');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAsset = prefs.getString('${key}_cached_asset') ?? '';
      final cachedPath = prefs.getString('${key}_cached_path') ?? '';

      if (cachedAsset == assetPath &&
          cachedPath.isNotEmpty &&
          File(cachedPath).existsSync()) {
        await HomeWidget.saveWidgetData<String>(key, cachedPath);
        return;
      }

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$key.png');
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await HomeWidget.saveWidgetData<String>(key, file.path);
      await prefs.setString('${key}_cached_asset', assetPath);
      await prefs.setString('${key}_cached_path', file.path);
      debugPrint('_cacheEmojiForWidget: $key cached at ${file.path}');
    } catch (e) {
      debugPrint('_cacheEmojiForWidget($key) failed: $e');
      await HomeWidget.saveWidgetData<String>(key, '');
    }
  }

  /// Скачивает изображение по [url] в файловый кэш и сохраняет путь
  /// под ключом [key] в SharedPreferences нативного виджета.
  Future<void> _downloadPhoto(String? url, String key) async {
    if (url == null || url.isEmpty) {
      await HomeWidget.saveWidgetData<String>(key, '');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('${key}_cached_url') ?? '';
      final cachedPath = prefs.getString('${key}_cached_path') ?? '';

      // Если URL не изменился и файл существует — не скачиваем повторно
      if (cachedUrl == url &&
          cachedPath.isNotEmpty &&
          File(cachedPath).existsSync()) {
        await HomeWidget.saveWidgetData<String>(key, cachedPath);
        return;
      }

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$key.jpg');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        await HomeWidget.saveWidgetData<String>(key, file.path);
        await prefs.setString('${key}_cached_url', url);
        await prefs.setString('${key}_cached_path', file.path);
        debugPrint('_downloadPhoto: $key cached at ${file.path}');
      } else {
        await HomeWidget.saveWidgetData<String>(key, '');
      }
    } catch (e) {
      debugPrint('_downloadPhoto($key) failed: $e');
      await HomeWidget.saveWidgetData<String>(key, '');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _isDisposed = true;
    _mySub?.cancel();
    for (final sub in _partnerSubs.values) {
      sub.cancel();
    }
    _partnerSubs.clear();
    super.dispose();
  }
}
