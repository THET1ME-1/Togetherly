import 'dart:async';
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
import '../config/migration_config.dart';
import 'firebase_service.dart';
import 'home_widget_service.dart';
import 'supabase_service.dart';

/// Сервис для синхронизации виджет-данных между партнёрами.
///
/// Firestore path: `groups/{groupId}/widgetData/{uid}`
///
/// Поддерживает автоматическую отправку в Memory Lane и Mood Calendar.
class WidgetService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();
  final SupabaseService _sb = SupabaseService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isDisposed = false;

  /// Фаза 1: зеркалим widgetData в Supabase.
  bool get _mig =>
      MigrationConfig.isConfigured &&
      MigrationConfig.isPhase1User(_fb.currentUser?.email);
  int _bindGeneration = 0;

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

  // Дебаунс для _syncToNativeWidget. Метод копирует PNG-ассеты, скачивает
  // фото через HTTP и пишет 30+ значений в SharedPreferences. На каждом
  // snapshot widgetData (mood/status/message change) он стрелял — при цепных
  // изменениях лагало 200-500ms. Не Firestore reads, но UX-критично.
  Timer? _syncNativeDebounce;

  // Кэш профиля пользователя — чтобы не читать users/{uid} на каждую запись
  // в _updateField (mood/status/message менялись по 1 read на каждое обновление).
  // Сбрасывается в unbindFromGroup, обновляется лениво при первом запросе.
  String? _cachedProfileName;
  String? _cachedProfileAvatar;
  String? _cachedProfileGender;
  String? _cachedProfileUid;

  // Подписи photo-полей: refreshPhotoOfDay делает full-collection .get() на
  // widgetData + fallback на group doc — пересчитывать его на КАЖДЫЙ snapshot
  // (включая mood/status/message) очень дорого. Триггерим только когда реально
  // поменялись фото-поля.
  String? _myPhotoSig;
  final Map<String, String> _partnerPhotoSigs = {};

  static String _photoSigOf(WidgetData? d) {
    if (d == null) return '';
    return [
      d.photoUrl ?? '',
      d.photoForPartnerUrl ?? '',
      d.photoForPartnerUrls.join('|'),
      d.photoGridUrls.join('|'),
    ].join('§');
  }

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
    // unbindFromGroup increments _bindGeneration internally, so capture
    // the generation AFTER the call to avoid an immediate guard mismatch.
    await unbindFromGroup(clearNativeWidget: false);
    final generation = ++_bindGeneration;
    _groupId = groupId;
    await _loadSettings();
    if (_isDisposed || generation != _bindGeneration) return;
    // Persist groupId so the background isolate (onUpdate refresh) can find it
    await HomeWidget.saveWidgetData<String>('love_widget_group_id', groupId);
    _listenToMyData();
    notifyListeners();
  }

  /// Подписка на виджет-данные партнёра
  void listenToPartner(String partnerUid) {
    if (partnerUid.isEmpty || _groupId.isEmpty) return;
    // Persist partnerUid so the background isolate can fetch partner data
    HomeWidget.saveWidgetData<String>('love_widget_partner_uid', partnerUid);

    _partnerSubs.remove(partnerUid)?.cancel();
    _partnerData.remove(partnerUid);

    // Общий обработчик снимка widget_data партнёра (firestore-формат).
    void handle(Map<String, dynamic>? data) {
      if (_isDisposed) return;
      if (data != null) {
        _partnerData[partnerUid] = WidgetData.fromFirestore(data);
      } else {
        _partnerData[partnerUid] = WidgetData(uid: partnerUid);
        // Fallback: read name/avatar from group document
        _loadPartnerFallback(partnerUid);
      }
      _scheduleSyncToNative();
      // refreshPhotoOfDay делает full-collection read на widgetData — дёргаем
      // только когда реально изменились фото-поля партнёра, а не mood/status.
      final newSig = _photoSigOf(_partnerData[partnerUid]);
      if (_groupId.isNotEmpty && _partnerPhotoSigs[partnerUid] != newSig) {
        _partnerPhotoSigs[partnerUid] = newSig;
        HomeWidgetService.instance.invalidateWidgetDataCache();
        HomeWidgetService.instance.refreshPhotoOfDay(_groupId);
      }
      notifyListeners();
    }

    // Фаза 1: читаем widget_data партнёра из Supabase realtime.
    if (_mig) {
      final sub = _sb.listenWidgetData(_groupId, partnerUid, handle);
      if (sub != null) _partnerSubs[partnerUid] = sub;
      return;
    }

    final ref = _db
        .collection('groups')
        .doc(_groupId)
        .collection('widgetData')
        .doc(partnerUid);

    _partnerSubs[partnerUid] = ref.snapshots().listen(
      (snap) => handle(snap.exists ? snap.data() : null),
      onError: (e) => debugPrint('WidgetService partner listener error: $e'),
    );
  }

  Future<void> unbindFromGroup({bool clearNativeWidget = true}) async {
    _bindGeneration++;
    _mySub?.cancel();
    _mySub = null;
    for (final sub in _partnerSubs.values) {
      sub.cancel();
    }
    _partnerSubs.clear();
    _groupId = '';
    _myData = null;
    _partnerData.clear();
    _myPhotoSig = null;
    _partnerPhotoSigs.clear();

    // Clear native group/partner keys so background isolates don't
    // read stale group references after unbind.
    await HomeWidget.saveWidgetData<String>('love_widget_group_id', '');
    await HomeWidget.saveWidgetData<String>('love_widget_partner_uid', '');

    if (clearNativeWidget) {
      await _syncToNativeWidget();
    }
    notifyListeners();
  }

  void _listenToMyData() {
    final uid = _fb.currentUser?.uid;
    if (uid == null || _groupId.isEmpty) return;

    _mySub?.cancel();

    void handle(Map<String, dynamic>? data) {
      if (_isDisposed) return;
      if (data != null) {
        _myData = WidgetData.fromFirestore(data);
      } else {
        _myData = WidgetData(uid: uid);
        // Bootstrap document with profile data so widget shows name/avatar
        _initializeMyWidgetData(uid);
      }
      _scheduleSyncToNative();
      final newSig = _photoSigOf(_myData);
      if (_groupId.isNotEmpty && _myPhotoSig != newSig) {
        _myPhotoSig = newSig;
        HomeWidgetService.instance.invalidateWidgetDataCache();
        HomeWidgetService.instance.refreshPhotoOfDay(_groupId);
      }
      notifyListeners();
    }

    // Фаза 1: читаем свой widget_data из Supabase realtime.
    if (_mig) {
      _mySub = _sb.listenWidgetData(_groupId, uid, handle);
      return;
    }

    final ref = _db
        .collection('groups')
        .doc(_groupId)
        .collection('widgetData')
        .doc(uid);

    _mySub = ref.snapshots().listen(
      (snap) => handle(snap.exists ? snap.data() : null),
      onError: (e) => debugPrint('WidgetService my data listener error: $e'),
    );
  }

  /// Creates widgetData doc with profile data when it doesn't exist yet.
  Future<void> _initializeMyWidgetData(String uid) async {
    final gid = _groupId;
    if (gid.isEmpty) return;
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (!userDoc.exists || _isDisposed || _groupId != gid) return;
      final d = userDoc.data()!;
      final bootstrap = {
        'displayName': d['displayName'] ?? '',
        'avatarUrl': d['avatarUrl'] ?? '',
        'gender': d['gender'] ?? '',
      };
      // Этап 4: bootstrap-строка создаётся только в Supabase (оттуда читают
      // оба листенера); без неё новый юзер бесконечно падал бы в ветку
      // «строки нет».
      if (_mig) {
        await _sb.mirrorWidgetData(gid, uid, bootstrap);
      } else {
        await _db
            .collection('groups')
            .doc(gid)
            .collection('widgetData')
            .doc(uid)
            .set({
          'uid': uid,
          ...bootstrap,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      debugPrint('WidgetService: widgetData initialized for $uid');
    } catch (e) {
      debugPrint('WidgetService._initializeMyWidgetData failed: $e');
    }
  }

  /// Reads partner name/avatar from the group document as fallback when
  /// their widgetData document doesn't exist yet.
  void _loadPartnerFallback(String partnerUid) {
    final gid = _groupId;
    if (gid.isEmpty) return;

    // Фаза 1: имя/аватар партнёра берём из группы в Supabase, а не из Firestore.
    if (_mig) {
      final myUid = _fb.currentUser?.uid ?? '';
      _sb.loadPairById(gid, myUid).then((parsed) {
        if (_isDisposed || _groupId != gid || parsed == null) return;
        final members = (parsed['members'] as List?) ?? const [];
        String name = '';
        String avatar = '';
        for (final m in members) {
          if (m is Map && m['uid'] == partnerUid) {
            name = (m['name'] ?? '').toString();
            avatar = (m['avatar'] ?? '').toString();
            break;
          }
        }
        if (name.isEmpty && avatar.isEmpty) return;
        _partnerData[partnerUid] = WidgetData(
          uid: partnerUid,
          displayName: name,
          avatarUrl: avatar,
        );
        _syncToNativeWidget();
        notifyListeners();
      }).catchError((Object e) {
        debugPrint('WidgetService._loadPartnerFallback (sb) failed: $e');
      });
      return;
    }

    _db.collection('groups').doc(gid).get().then((groupDoc) {
      if (!groupDoc.exists || _isDisposed || _groupId != gid) return;
      final data = groupDoc.data()!;
      final names = Map<String, dynamic>.from(data['memberNames'] ?? {});
      final avatars = Map<String, dynamic>.from(data['memberAvatars'] ?? {});
      final name = names[partnerUid]?.toString() ?? '';
      final avatar = avatars[partnerUid]?.toString() ?? '';
      if (name.isEmpty && avatar.isEmpty) return;
      _partnerData[partnerUid] = WidgetData(
        uid: partnerUid,
        displayName: name,
        avatarUrl: avatar,
      );
      _syncToNativeWidget();
      notifyListeners();
    }).catchError((Object e) {
      debugPrint('WidgetService._loadPartnerFallback failed: $e');
    });
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
    final groupId = _groupId;
    await _updateField({
      'moodEmoji': emojiPath,
      'moodLabel': label,
    }, groupId: groupId);

    // Автоотправка в календарь — только если не пропускаем
    if (!skipCalendar && _autoSendMoodToCalendar && groupId.isNotEmpty) {
      try {
        final uid = _fb.currentUser?.uid ?? '';
        final now = DateTime.now();
        final id = '${uid}_${now.millisecondsSinceEpoch}';
        // Ищем корректный moodId по imagePath (во всех паках)
        final option = MoodOption.byImagePath(emojiPath);
        final entry = MoodEntry(
          id: id,
          moodId: option?.id ?? label.toLowerCase().replaceAll(' ', '_'),
          imagePath: emojiPath,
          label: label,
          timestamp: now,
        );
        await _fb.addMoodEntry(groupId: groupId, entry: entry.toFirestore());
      } catch (e) {
        debugPrint('Widget → Calendar failed: $e');
      }
    }
  }

  /// Обновить сообщение
  Future<void> updateMessage(String message) async {
    final groupId = _groupId;
    await _updateField({'message': message}, groupId: groupId);

    // Автоотправка в Memory Lane
    if (_autoSendMessageToMemory && message.isNotEmpty && groupId.isNotEmpty) {
      try {
        await _fb.addMemory(
          groupId: groupId,
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
    final groupId = _groupId;
    if (groupId.isEmpty) return;
    // Загрузка в Storage
    final uid = _fb.currentUser?.uid ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dest = 'widget/$groupId/${uid}_$ts.jpg';
    final url = await _fb.uploadFile(localPath, dest);
    if (url == null || groupId != _groupId) return;

    await _updateField({'photoUrl': url}, groupId: groupId);

    // Автоотправка в Memory Lane
    if (_autoSendPhotoToMemory && groupId.isNotEmpty) {
      try {
        await _fb.addMemory(
          groupId: groupId,
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
    await _updateField({'photoUrl': url}, groupId: _groupId);
  }

  /// Фото, которым я делюсь с партнёром для partner-widget.
  /// Заменяет карусель одним фото — используется для «живого» фото с камеры.
  Future<void> updatePhotoForPartnerUrl(String url) async {
    await _updateField({
      'photoForPartnerUrl': url,
      'photoForPartnerUrls': [url],
    }, groupId: _groupId);
  }

  Future<void> updatePhotoForPartnerCarousel(List<String> urls) async {
    await _updateField({
      'photoForPartnerUrls': urls,
      'photoForPartnerUrl': urls.isNotEmpty ? urls.first : null,
    }, groupId: _groupId);
  }

  /// Сохранить настройки сетки фото (мои фото, которые увидит партнёр)
  Future<void> updatePhotoGrid(int count, List<String> photoUrls) async {
    await _updateField({
      'photoGridCount': count,
      'photoGridUrls': photoUrls,
    }, groupId: _groupId);
  }

  /// Обновить музыку
  Future<void> updateMusic({
    required String title,
    required String artist,
    String? url,
    String? coverUrl,
  }) async {
    final groupId = _groupId;
    await _updateField({
      'musicTitle': title,
      'musicArtist': artist,
      'musicUrl': url,
      'musicCoverUrl': coverUrl,
    }, groupId: groupId);

    // Автоотправка в Memory Lane
    if (_autoSendMusicToMemory && groupId.isNotEmpty) {
      try {
        await _fb.addMemory(
          groupId: groupId,
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

  Future<void> _updateField(
    Map<String, dynamic> fields, {
    String? groupId,
    bool emitEvent = true,
  }) async {
    final uid = _fb.currentUser?.uid;
    final targetGroupId = groupId ?? _groupId;
    if (uid == null || targetGroupId.isEmpty) return;

    try {
      // Профиль кэшируется на сессию: gender/name/avatar меняются редко,
      // а _updateField вызывается на каждое изменение mood/status/message.
      // До кэша это был +1 read в users/{uid} на каждое обновление виджета.
      if (_cachedProfileUid != uid) {
        _cachedProfileUid = uid;
        _cachedProfileName = null;
        _cachedProfileAvatar = null;
        _cachedProfileGender = null;
      }
      if (_cachedProfileName == null ||
          _cachedProfileAvatar == null ||
          _cachedProfileGender == null) {
        try {
          final userDoc = await _db.collection('users').doc(uid).get();
          final d = userDoc.data();
          _cachedProfileName =
              (d?['displayName'] as String?) ?? _fb.currentUser?.displayName ?? '';
          _cachedProfileAvatar =
              (d?['avatarUrl'] as String?) ?? _fb.currentUser?.photoURL ?? '';
          _cachedProfileGender = (d?['gender'] as String?) ?? '';
        } catch (e) {
          debugPrint('WidgetService._updateField profile read failed: $e');
          _cachedProfileName ??= _fb.currentUser?.displayName ?? '';
          _cachedProfileAvatar ??= _fb.currentUser?.photoURL ?? '';
          _cachedProfileGender ??= '';
        }
      }
      final name = _cachedProfileName!;
      final avatar = _cachedProfileAvatar!;
      final gender = _cachedProfileGender!;

      // Этап 4: widget_data живёт только в Supabase (свой и партнёрский
      // листенеры читают оттуда). Firestore-док больше не пишем; событие
      // widgetDataEvents ниже остаётся — это триггер FCM-пуша.
      if (_mig) {
        await _sb.mirrorWidgetData(targetGroupId, uid, {
          'displayName': name,
          'avatarUrl': avatar,
          'gender': gender,
          ...fields,
        });
      } else {
        final ref = _db
            .collection('groups')
            .doc(targetGroupId)
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
      }

      if (targetGroupId != _groupId) return;

      // Синхронизируем нативный виджет сразу после записи,
      // не дожидаясь Firestore-листенера (Xiaomi убивает процесс слишком быстро)
      await _syncToNativeWidget();

      // Пишем лёгкий триггер для Cloud Function, которая отправит FCM-сообщение
      // партнёру с type=widget_update — это обеспечивает мгновенное обновление
      // даже когда процесс Flutter партнёра полностью убит OEM-оптимизатором.
      // Чистый рефреш профиля (аватар/имя) этого не требует — партнёр получит
      // обновление через свой live-листенер widgetData, FCM-шум не нужен.
      if (!emitEvent) return;
      final triggerFields = <String, dynamic>{
        'senderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      const widgetFields = ['status', 'moodLabel', 'message', 'musicTitle', 'musicArtist'];
      for (final entry in fields.entries) {
        if (widgetFields.contains(entry.key) && entry.value != null) {
          triggerFields[entry.key] = entry.value;
        }
      }
      unawaited(
        _db
            .collection('groups')
            .doc(targetGroupId)
            .collection('widgetDataEvents')
            .add(triggerFields)
            .catchError((Object e) {
          debugPrint('widgetDataEvents write failed: $e');
          throw e;
        }),
      );
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

  /// Планирует _syncToNativeWidget с дебаунсом 150ms — собирает каскад
  /// snapshot-событий (mood/status/message могут прилетать пачкой) в один
  /// тяжёлый sync вместо 5+ повторов.
  void _scheduleSyncToNative() {
    _syncNativeDebounce?.cancel();
    _syncNativeDebounce = Timer(const Duration(milliseconds: 150), () {
      if (_isDisposed) return;
      _syncToNativeWidget();
    });
  }

  /// Синхронизирует данные в SharedPreferences для нативного виджета Android
  Future<void> _syncToNativeWidget() async {
    final bindGeneration = _bindGeneration;
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
      // MY сторона показывает ТОЛЬКО photoUrl (фото, явно выбранное для
      // парного виджета). НЕ падаем на photoForPartnerUrl — это отдельная
      // функция «Фото партнёра» (что я отправляю партнёру), и её фото не
      // должно протекать на мою половину парного виджета.
      // PARTNER сторона: приоритет photoForPartnerUrl — это фото, которым
      // партнёр осознанно поделился, чтобы оно показывалось у меня.
      await HomeWidget.saveWidgetData<String>(
        'my_photo_url',
        my?.photoUrl ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'partner_photo_url',
        partner?.photoForPartnerUrl ?? partner?.photoUrl ?? '',
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
      if (_isDisposed || bindGeneration != _bindGeneration) return;
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
      if (_isDisposed || bindGeneration != _bindGeneration) return;

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
        if (_isDisposed || bindGeneration != _bindGeneration) return;
        try {
          await HomeWidget.updateWidget(
            name: 'LoveWidgetProvider',
            androidName: 'LoveWidgetProvider',
          );
        } catch (e) {
          debugPrint('WidgetService emoji update failed: $e');
        }
      });

      // Скачиваем фото и аватарки локально в фоне и обновляем виджет повторно.
      // MY сторона — только photoUrl (см. комментарий выше про my_photo_url):
      // фото «для партнёра» не должно попадать на мою половину парного виджета.
      _cachePhotosForWidget(
        my?.photoUrl,
        partner?.photoForPartnerUrl ?? partner?.photoUrl,
      );
      _cacheAvatarsForLoveWidget(my?.avatarUrl, partner?.avatarUrl);
      _cacheGroupAvatarsForWidget(limitedMembers);

      // PhotoDay обновляется ТОЛЬКО при изменении фото-полей (photoUrl,
      // photoForPartnerUrl, photoForPartnerUrls, photoGridUrls) через
      // проверку _photoSig() в слушателях. Не дёргаем здесь — на каждое
      // изменение mood/status/message это было бы N×collection.get() reads.
    } catch (e) {
      debugPrint('WidgetService._syncToNativeWidget failed: $e');
    }
  }

  /// Скачивает фото в локальный кэш и обновляет нативный виджет (LoveWidget).
  void _cachePhotosForWidget(String? myUrl, String? partnerUrl) {
    final bindGeneration = _bindGeneration;
    Future.wait([
      _downloadPhoto(myUrl, 'my_photo_path'),
      _downloadPhoto(partnerUrl, 'partner_photo_path'),
    ]).then((_) async {
      if (_isDisposed || bindGeneration != _bindGeneration) return;
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
    final bindGeneration = _bindGeneration;
    Future.wait([
      _downloadPhoto(myUrl, 'my_avatar_path'),
      _downloadPhoto(partnerUrl, 'partner_avatar_path'),
    ]).then((_) async {
      if (_isDisposed || bindGeneration != _bindGeneration) return;
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
    final bindGeneration = _bindGeneration;
    final futures = <Future<void>>[];
    for (int i = 0; i < members.length; i++) {
      futures.add(
        _downloadPhoto(members[i].avatarUrl, 'user_${i}_avatar_path'),
      );
    }
    Future.wait(futures).then((_) async {
      if (_isDisposed || bindGeneration != _bindGeneration) return;
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
      String httpUrl = url;

      // gs:// (Firebase) и sb:// (Supabase) не поддерживаются http.get —
      // получаем подписанный https:// URL.
      if (url.startsWith('gs://') || url.startsWith('sb://')) {
        // sb:// передаём целиком; gs:// — снимаем префикс bucket'а.
        final path = url.startsWith('sb://')
            ? url
            : url.replaceFirst(RegExp(r'^gs://[^/]+/'), '');
        final signedUrl = await FirebaseService().getSignedUrl(path);
        if (signedUrl == null || signedUrl.isEmpty) {
          debugPrint('_downloadPhoto($key): no signed URL for $url');
          await HomeWidget.saveWidgetData<String>(key, '');
          return;
        }
        httpUrl = signedUrl;
      }

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
          .get(Uri.parse(httpUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        await HomeWidget.saveWidgetData<String>(key, file.path);
        await prefs.setString('${key}_cached_url', url);
        await prefs.setString('${key}_cached_path', file.path);
        debugPrint('_downloadPhoto: $key cached at ${file.path}');
      } else {
        debugPrint('_downloadPhoto($key): HTTP ${response.statusCode} for $url');
        await HomeWidget.saveWidgetData<String>(key, '');
      }
    } catch (e) {
      debugPrint('_downloadPhoto($key) failed: $e');
      await HomeWidget.saveWidgetData<String>(key, '');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC SYNC
  // ══════════════════════════════════════════════════════════════════════════

  /// Forces an immediate re-sync of the native home-screen widget.
  /// Call this when the app comes to foreground so the widget is always fresh.
  Future<void> syncNow() => _syncToNativeWidget();

  /// Сбросить кэш профиля — вызывать после редактирования имени/аватара/пола,
  /// чтобы следующий _updateField подтянул свежие значения из users/{uid}.
  void invalidateProfileCache() {
    _cachedProfileName = null;
    _cachedProfileAvatar = null;
    _cachedProfileGender = null;
  }

  /// Проталкивает свежий профиль (имя/аватар/пол) в widgetData текущей группы
  /// и нативный виджет. Звать ПОСЛЕ смены аватара/имени.
  ///
  /// Без этого виджет показывает старый аватар до перезахода: профиль кэшируется
  /// на сессию ([_cachedProfileAvatar]), а единственный писатель аватара в
  /// widgetData — [_updateField] — берёт из кэша. Здесь сбрасываем кэш и пустым
  /// [_updateField] перечитываем профиль из users/{uid} → пишем свежий avatarUrl
  /// в widgetData (партнёр увидит через свой live-листенер) и сразу синхронизируем
  /// нативный виджет (он перекачает новую картинку — у аватара меняется URL).
  Future<void> refreshProfileOnWidget() async {
    invalidateProfileCache();
    if (_groupId.isEmpty) return;
    await _updateField(const {}, emitEvent: false);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _isDisposed = true;
    _syncNativeDebounce?.cancel();
    _mySub?.cancel();
    for (final sub in _partnerSubs.values) {
      sub.cancel();
    }
    _partnerSubs.clear();
    super.dispose();
  }
}
