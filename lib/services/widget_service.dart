import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/widget_data.dart';
import '../models/memory.dart';
import '../models/mood_entry.dart';
import 'firebase_service.dart';
import 'mood_service.dart';

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

  /// Обновить настроение (emoji)
  Future<void> updateMood(String emojiPath, String label) async {
    await _updateField({'moodEmoji': emojiPath, 'moodLabel': label});

    // Автоотправка в календарь через MoodService-совместимый формат
    if (_autoSendMoodToCalendar && _groupId.isNotEmpty) {
      try {
        final uid = _fb.currentUser?.uid ?? '';
        final now = DateTime.now();
        final id = '${uid}_${now.millisecondsSinceEpoch}';
        final entry = MoodEntry(
          id: id,
          moodId: label.toLowerCase().replaceAll(' ', '_'),
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

      final ref = _db
          .collection('groups')
          .doc(_groupId)
          .collection('widgetData')
          .doc(uid);

      await ref.set({
        'uid': uid,
        'displayName': name,
        'avatarUrl': avatar,
        'updatedAt': FieldValue.serverTimestamp(),
        ...fields,
      }, SetOptions(merge: true));
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
      await HomeWidget.saveWidgetData<String>(
        'my_name',
        my?.displayName ?? 'Я',
      );
      await HomeWidget.saveWidgetData<String>('my_mood', my?.moodEmoji ?? '');
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
        partner?.displayName ?? 'Партнёр',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_mood',
        partner?.moodEmoji ?? '',
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

      // ── Обновить виджет на рабочем столе ──
      await HomeWidget.updateWidget(
        name: 'LoveWidgetProvider',
        qualifiedAndroidName: 'com.example.love_app.LoveWidgetProvider',
      );
    } catch (e) {
      debugPrint('WidgetService._syncToNativeWidget failed: $e');
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
