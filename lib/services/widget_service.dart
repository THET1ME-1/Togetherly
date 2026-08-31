import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/widget_data.dart';
import '../models/memory.dart';
import '../models/mood_entry.dart';
import 'locale_service.dart';
import 'widget_photo_cache.dart';
import 'widget_photo_store.dart';
import 'widget_image_limit.dart';
import 'pair_widget_payload.dart';
import 'media_service.dart';
import 'home_widget_service.dart';
import 'level_service.dart';
import 'memory_repository.dart';
import 'mood_repository.dart';
import 'pb_auth_service.dart';
import 'pb_data_service.dart';
import 'pb_media_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';
import 'widget_anim_service.dart';

/// Сервис синхронизации виджет-данных между партнёрами — на PocketBase
/// (миграция §3): коллекция `widget_data` (live SSE, без лимитов). Авто-отправка
/// в Memory Lane / Mood Calendar идёт через мигрированные [MemoryRepository] /
/// [MoodRepository]. `FirebaseService` остаётся ТОЛЬКО под медиа (загрузка фото в
/// Storage + signed-URL для скачивания gs:///sb:// в нативный виджет) — медиа §4.
class WidgetService extends ChangeNotifier {
  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();
  bool _isDisposed = false;

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

  /// Фото на МОЕЙ половине парного виджета: только то, что я выбрал для этого
  /// виджета. Фото «для партнёра» — другая функция и сюда не протекает.
  static String pairPhotoOfMine(WidgetData? d) => pairPhotoOf(d);

  /// Фото на половине ПАРТНЁРА — только его фото парного виджета.
  ///
  /// Фолбэка на `photo_for_partner_url` больше нет (13 августа 2026). Он стоял
  /// ради 1983 записей, где своего фото не было вовсе, но чинил меньше, чем
  /// ломал: снимок, отправленный через «Фото партнёра», сам появлялся у
  /// человека в парном виджете, хотя в настройках виджета фото не прикреплено.
  /// Тестер разобрал это по шагам и сформулировал точнее всех: «работает не
  /// фото партнёра — фото партнёра, а фото партнёра — парный виджет».
  ///
  /// Старым записям фото не потеряли: `photo_for_partner_url` перенесён им в
  /// `photo_url` разовым UPDATE на сервере, поэтому у этих пар в виджете
  /// осталось ровно то же, что и было.
  ///
  /// Обратная сторона фолбэка того же поля описана ниже, у
  /// [clearPairPhotoFields]: до 7 августа фото нельзя было убрать вовсе.
  static String pairPhotoOfPartner(WidgetData? d) => pairPhotoOf(d);

  /// Поля записи, когда фото «для партнёра» ставят или убирают.
  ///
  /// Пустой список — это «убрать фото», и убрать его можно ТОЛЬКО пустой
  /// строкой: `upsertWidget` выбрасывает null-поля ради частичного апдейта,
  /// поэтому прежний `null` оставлял старую ссылку жить на сервере. Карусель
  /// при этом пустела, виджет «Фото партнёра» читал одиночное поле — и фото у
  /// партнёра не пропадало (жалоба 2026-08-07).
  static Map<String, dynamic> photoForPartnerFields(List<String> urls) => {
        'photoForPartnerUrls': urls,
        'photoForPartnerUrl': urls.isNotEmpty ? urls.first : '',
      };

  /// Поля записи, когда убирают фото ПАРНОГО виджета.
  ///
  /// В диалоге отправки оба тумблера включены по умолчанию, поэтому у многих
  /// пар `photo_url` и `photo_for_partner_url` — один и тот же снимок. Стирая
  /// только своё поле, мы отдавали половине партнёра тот же кадр фолбэком
  /// (`pairPhotoOfPartner`), и удаление выглядело несработавшим. Такой снимок
  /// снимается разом с обоих направлений.
  ///
  /// Осознанно собранную карусель «для партнёра» это не трогает: там фото
  /// выбирали отдельно, и удаление своей половины его не отменяет.
  static Map<String, dynamic> clearPairPhotoFields(WidgetData? d) {
    const cleared = {'photoUrl': ''};
    final mine = d?.photoUrl ?? '';
    final forPartner = d?.photoForPartnerUrl ?? '';
    if (mine.isEmpty || forPartner != mine) return cleared;

    final carousel = d?.photoForPartnerUrls ?? const <String>[];
    final sameShot = carousel.isEmpty ||
        (carousel.length == 1 && carousel.first == mine);
    if (!sameShot) return cleared;

    return {...cleared, ...photoForPartnerFields(const [])};
  }

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

    _partnerSubs[partnerUid] = _rt.watchWidgetOne(_groupId, partnerUid).listen(
      (rec) {
        if (_isDisposed) return;
        if (rec != null) {
          _partnerData[partnerUid] = WidgetData.fromPb(rec);
        } else {
          _partnerData[partnerUid] = WidgetData(uid: partnerUid);
          // Fallback: имя/аватар из group-дока (member_names/member_avatars).
          _loadPartnerFallback(partnerUid);
        }
        _scheduleSyncToNative();
        // refreshPhotoOfDay перечитывает виджет-данные — дёргаем только когда
        // реально изменились фото-поля партнёра, а не mood/status.
        final newSig = _photoSigOf(_partnerData[partnerUid]);
        if (_groupId.isNotEmpty && _partnerPhotoSigs[partnerUid] != newSig) {
          _partnerPhotoSigs[partnerUid] = newSig;
          HomeWidgetService.instance.invalidateWidgetDataCache();
          HomeWidgetService.instance.refreshPhotoOfDay(_groupId);
        }
        notifyListeners();
      },
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

    // Признак пары держим до тех пор, пока пара действительно не распалась.
    // Раньше он затирался на каждом техническом переподключении — а их случается
    // много, — и виджет успевал показать «Подключите партнёра» при живой паре.
    // Закрыли приложение в эту секунду, и надпись оставалась насовсем: обновить
    // её на iPhone некому, фонового обновления там нет. Отвязка таким признаком
    // тоже не является: экран зовёт её и при переключении между связями.

    // Стирать тут НЕЛЬЗЯ. Отвязка — это ещё и обычное переключение между
    // связями: экран зовёт её перед привязкой к другой паре, и очистка
    // затирала имена с настроениями у человека с двумя связями (18.08.2026).
    // Распад пары чистит `clearPairWidgetData` по правилу
    // `shouldClearPairWidget`, выход из аккаунта — `HomeWidgetService`.
    notifyListeners();
  }

  /// Стереть с виджета всё, что осталось от распавшейся пары.
  ///
  /// Раньше это делала обычная синхронизация: модель пуста, значит во все ключи
  /// уходили пустые строки. С 17–18.08.2026 половина без данных не трогается
  /// (иначе фото стиралось на каждом холодном старте), поэтому распад пары
  /// приходится отрабатывать отдельно. Список ключей — в
  /// pair_widget_payload.dart, сторож — test/services/pair_widget_clear_test.dart.
  Future<void> clearPairWidgetData() async {
    try {
      for (final e in pairWidgetClearPayload().entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      // Привязка к паре тоже уходит: пары больше нет, и виджет обязан это
      // показать («Подключите партнёра»), а не держать прежнюю подпись.
      await HomeWidget.saveWidgetData<String>('love_widget_group_id', '');
      await HomeWidget.saveWidgetData<String>('love_widget_partner_uid', '');
      // Записи мало: картинки лежат файлами в общем контейнере и переживают её.
      for (final key in kPairWidgetFileKeys) {
        await HomeWidgetService.instance.clearAppGroupMedia(key);
      }
      for (final name in const [
        'LoveWidgetProvider',
        'MoodWidgetProvider',
        'SelfPhotoWidgetProvider',
        'PartnerPhotoWidgetProvider',
      ]) {
        await HomeWidget.updateWidget(name: name, androidName: name);
      }
    } catch (e) {
      debugPrint('WidgetService.clearPairWidgetData failed: $e');
    }
  }

  void _listenToMyData() {
    final uid = PocketBaseService().userId;
    if (uid == null || _groupId.isEmpty) return;

    _mySub?.cancel();
    _mySub = _rt.watchWidgetOne(_groupId, uid).listen(
      (rec) {
        if (_isDisposed) return;
        if (rec != null) {
          _myData = WidgetData.fromPb(rec);
        } else {
          _myData = WidgetData(uid: uid);
          // Bootstrap record with profile data so widget shows name/avatar
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
      },
      onError: (e) => debugPrint('WidgetService my data listener error: $e'),
    );
  }

  /// Creates the widget_data record with profile data when it doesn't exist yet.
  Future<void> _initializeMyWidgetData(String uid) async {
    final gid = _groupId;
    if (gid.isEmpty) return;
    try {
      final p = PbAuthService().currentProfile() ?? const {};
      if (_isDisposed || _groupId != gid) return;
      await _data.upsertWidget(gid, uid, {
        'displayName': p['displayName'] ?? '',
        'avatarUrl': p['avatarUrl'] ?? '',
        'gender': p['gender'] ?? '',
      });
      debugPrint('WidgetService: widget_data initialized for $uid');
    } catch (e) {
      debugPrint('WidgetService._initializeMyWidgetData failed: $e');
    }
  }

  /// Reads partner name/avatar from the group record (member_names/member_avatars)
  /// as fallback when their widget_data record doesn't exist yet.
  Future<void> _loadPartnerFallback(String partnerUid) async {
    final gid = _groupId;
    if (gid.isEmpty) return;
    try {
      final g = await _data.loadGroupById(gid);
      if (g == null || _isDisposed || _groupId != gid) return;
      final names = g.data['member_names'];
      final avatars = g.data['member_avatars'];
      final name = (names is Map ? names[partnerUid] : null)?.toString() ?? '';
      final avatar =
          (avatars is Map ? avatars[partnerUid] : null)?.toString() ?? '';
      if (name.isEmpty && avatar.isEmpty) return;
      _partnerData[partnerUid] = WidgetData(
        uid: partnerUid,
        displayName: name,
        avatarUrl: avatar,
      );
      _syncToNativeWidget();
      notifyListeners();
    } catch (e) {
      debugPrint('WidgetService._loadPartnerFallback failed: $e');
    }
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

    unawaited(LevelService.instance.award(XpAction.changeMood));

    // Автоотправка в календарь — только если не пропускаем. Через мигрированный
    // MoodRepository (PB), id генерит сервер, личность — текущий PB-юзер.
    if (!skipCalendar && _autoSendMoodToCalendar && groupId.isNotEmpty) {
      try {
        final option = MoodOption.byImagePath(emojiPath);
        await MoodRepository().add(
          groupId: groupId,
          moodId: option?.id ?? label.toLowerCase().replaceAll(' ', '_'),
          imagePath: emojiPath,
          label: label,
          timestamp: DateTime.now(),
        );
      } catch (e) {
        debugPrint('Widget → Calendar failed: $e');
      }
    }
  }

  /// Имя/аватар автора для авто-воспоминаний (из профиля PB).
  ({String name, String avatar}) _memoryAuthor() {
    final p = PbAuthService().currentProfile() ?? const {};
    return (
      name: (p['displayName'] as String?) ?? '',
      avatar: (p['avatarUrl'] as String?) ?? '',
    );
  }

  /// Обновить сообщение
  Future<void> updateMessage(String message) async {
    final groupId = _groupId;
    await _updateField({'message': message}, groupId: groupId);

    // Автоотправка в Memory Lane
    if (_autoSendMessageToMemory && message.isNotEmpty && groupId.isNotEmpty) {
      try {
        final a = _memoryAuthor();
        await MemoryRepository().add(
          groupId: groupId,
          authorName: a.name,
          authorAvatar: a.avatar,
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
    // Загрузка в Storage (медиа §4 — пока Firebase Storage).
    final uid = PocketBaseService().userId ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dest = 'widget/$groupId/${uid}_$ts.jpg';
    final url = await MediaService().uploadFile(localPath, dest);
    if (url == null || groupId != _groupId) return;

    await _updateField({'photoUrl': url}, groupId: groupId);
    // Живое фото лежит отдельными ключами и перекрывает снимок, поэтому новая
    // фотография обязана его снять — иначе виджет остаётся с прежним видео.
    await WidgetAnimService.instance.clear();

    // Автоотправка в Memory Lane
    if (_autoSendPhotoToMemory && groupId.isNotEmpty) {
      try {
        final a = _memoryAuthor();
        await MemoryRepository().add(
          groupId: groupId,
          authorName: a.name,
          authorAvatar: a.avatar,
          type: MemoryType.photo,
          imageUrl: url,
          caption: LocaleService.current.widgetPhotoCaption,
        );
      } catch (e) {
        debugPrint('Widget → Memory (photo) failed: $e');
      }
    }
  }

  /// Обновить фото по URL (уже загружено)
  Future<void> updatePhotoUrl(String url) async {
    await _updateField({'photoUrl': url}, groupId: _groupId);
    await WidgetAnimService.instance.clear();
  }

  /// Фото, которым я делюсь с партнёром для partner-widget.
  /// Заменяет карусель одним фото — используется для «живого» фото с камеры.
  Future<void> updatePhotoForPartnerUrl(String url) async {
    await _updateField(photoForPartnerFields([url]), groupId: _groupId);
  }

  Future<void> updatePhotoForPartnerCarousel(List<String> urls) async {
    await _updateField(photoForPartnerFields(urls), groupId: _groupId);
  }

  /// Убрать фото, которое видит партнёр в виджете «Фото партнёра».
  Future<void> clearPhotoForPartner() =>
      _updateField(photoForPartnerFields(const []), groupId: _groupId);

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
        final a = _memoryAuthor();
        await MemoryRepository().add(
          groupId: groupId,
          authorName: a.name,
          authorAvatar: a.avatar,
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
  // Очистка пишет ПУСТУЮ строку (не null): upsertWidget отбрасывает null-поля
  // ради частичного апдейта, поэтому null не стёр бы значение. fromPb коэрсит
  // '' обратно в null при чтении.
  Future<void> clearStatus() => _updateField({'status': ''});
  Future<void> clearMood() => _updateField({'moodEmoji': '', 'moodLabel': ''});
  Future<void> clearMessage() => _updateField({'message': ''});
  Future<void> clearPhoto() => _updateField(clearPairPhotoFields(_myData));
  Future<void> clearMusic() => _updateField({
    'musicTitle': '',
    'musicArtist': '',
    'musicUrl': '',
    'musicCoverUrl': '',
  });

  /// Очистить все данные виджета
  Future<void> clearAll() async {
    await _updateField({
      'status': '',
      'moodEmoji': '',
      'moodLabel': '',
      'message': '',
      // Фото снимается тем же правилом, что и по кнопке «убрать»: снимок,
      // ушедший разом на оба направления, уходит с обоих.
      ...clearPairPhotoFields(_myData),
      'musicTitle': '',
      'musicArtist': '',
      'musicUrl': '',
      'musicCoverUrl': '',
    });
  }

  Future<void> _updateField(
    Map<String, dynamic> fields, {
    String? groupId,
    bool emitEvent = true, // legacy-параметр (FCM-триггер убран); сохранён для API
  }) async {
    final uid = PocketBaseService().userId;
    final targetGroupId = groupId ?? _groupId;
    if (uid == null || targetGroupId.isEmpty) return;

    try {
      // Профиль кэшируется на сессию (currentProfile() и так читает кэш-rec PB,
      // но держим локальный кэш ради invalidateProfileCache/refreshProfileOnWidget).
      if (_cachedProfileUid != uid) {
        _cachedProfileUid = uid;
        _cachedProfileName = null;
        _cachedProfileAvatar = null;
        _cachedProfileGender = null;
      }
      if (_cachedProfileName == null ||
          _cachedProfileAvatar == null ||
          _cachedProfileGender == null) {
        final p = PbAuthService().currentProfile() ?? const {};
        _cachedProfileName = (p['displayName'] as String?) ?? '';
        _cachedProfileAvatar = (p['avatarUrl'] as String?) ?? '';
        _cachedProfileGender = (p['gender'] as String?) ?? '';
      }
      final name = _cachedProfileName!;
      final avatar = _cachedProfileAvatar!;
      final gender = _cachedProfileGender!;

      // Запись в PB widget_data (upsert по group+uid). Партнёр видит изменение
      // через свой live SSE-листенер; фоновый пуш (убитый процесс) — через
      // PbPushService по SSE-дельте (мигрирует в §5), НЕ через Firebase-триггер.
      await _data.upsertWidget(targetGroupId, uid, {
        'displayName': name,
        'avatarUrl': avatar,
        'gender': gender,
        ...fields,
      });

      if (targetGroupId != _groupId) return;

      // Синхронизируем нативный виджет сразу после записи, не дожидаясь
      // SSE-листенера (Xiaomi убивает процесс слишком быстро).
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
      // Текстовые поля обеих половин. Половину, про которую данных нет, не
      // трогаем: подписка на свои данные идёт по uid из сессии, и пока сессия не
      // восстановилась, `_myData` равно null — прежний код записывал пустые
      // строки и обнулял свою половину виджета. Правило — в
      // pair_widget_payload.dart, под тестами.
      final my = _myData;
      final partner = firstPartnerData;

      // Привязка к паре идёт вместе с данными. `bindToGroup` пишет её один раз
      // и при той же группе выходит первой строкой, поэтому промах записи
      // оставался навсегда: имена обновлялись, а виджет рисовал «Подключите
      // партнёра» (19 таких iPhone в отчётах за 23.08.2026).
      for (final e in pairBindingPayload(
        groupId: _groupId,
        partnerUid: partner?.uid ?? '',
      ).entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }

      final keys = pairWidgetPayload(
        my: my,
        partner: partner,
        myFallbackName: 'Я',
        partnerFallbackName: 'Партнёр',
      );
      for (final e in keys.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }

      // ── Фото: сохраняем URL, кэшируем локально фоново ──
      // Правило выбора — в pairPhotoOfMine/pairPhotoOfPartner (под тестами
      // test/services/pair_widget_photo_test.dart).
      if (my != null) {
        await HomeWidget.saveWidgetData<String>(
          'my_photo_url',
          pairPhotoOfMine(my),
        );
      }
      if (partner != null) {
        await HomeWidget.saveWidgetData<String>(
          'partner_photo_url',
          pairPhotoOfPartner(partner),
        );
      }

      // ── Аватарки для 2-человечного виджета (LoveWidget) ──
      // LoveWidget всё ещё использует старые ключи для 2 людей
      if (my != null) {
        await HomeWidget.saveWidgetData<String>('my_avatar_url', my.avatarUrl);
      }
      if (partner != null) {
        await HomeWidget.saveWidgetData<String>(
          'partner_avatar_url',
          partner.avatarUrl,
        );
      }

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
      final myUid = PocketBaseService().userId ?? '';
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

      // Картинки половины без данных не трогаем — как и её тексты выше.
      // Правило и причина в pair_widget_payload.dart, сторож
      // test/services/pair_widget_media_test.dart.
      final media = pairWidgetMedia(my: my, partner: partner);

      // Кэшируем эмодзи из assets → локальные файлы для нативного виджета (фоново)
      Future.wait([
        _cacheEmojiForWidget(media.myMoodEmoji, 'my_mood_emoji_path'),
        _cacheEmojiForWidget(media.partnerMoodEmoji, 'partner_mood_emoji_path'),
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
      _cachePhotosForWidget(media.myPhoto, media.partnerPhoto);

      // iPhone: у фото-виджетов свои ключи и свой каталог выбора. Пока их никто
      // не писал, «Моё фото», «Фото партнёра», «Фото дня» и «Сетка» стояли на
      // рабочем столе пустыми белыми прямоугольниками.
      unawaited(HomeWidgetService.instance.syncIosPhotoWidgets(
        myPhotos: media.myIosPhotos,
        partnerPhotos: media.partnerIosPhotos,
        partnerName: partner?.displayName ?? '',
        gridPhotos: partner?.photoGridUrls,
      ));
      _cacheAvatarsForLoveWidget(media.myAvatar, media.partnerAvatar);
      _cacheGroupAvatarsForWidget(limitedMembers);

      // PhotoDay обновляется ТОЛЬКО при изменении фото-полей (photoUrl,
      // photoForPartnerUrl, photoForPartnerUrls, photoGridUrls) через
      // проверку _photoSig() в слушателях. Не дёргаем здесь — на каждое
      // изменение mood/status/message это было бы N×collection.get() reads.
    } catch (e) {
      debugPrint('WidgetService._syncToNativeWidget failed: $e');
    }
  }

  /// Какие снимки показывать в фото-виджетах iPhone.
  ///
  /// «Моё фото» — то, чем делюсь я: сначала своя карусель «для партнёра»,
  /// потом снимок парного виджета. «Фото партнёра» — зеркально его выбор.

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
    // null — данных о половине нет вовсе, ключ не трогаем (правило в
    // pair_widget_payload.dart). Пустая строка — настроение сняли осознанно.
    if (assetPath == null) return;
    if (assetPath.isEmpty) {
      await HomeWidget.saveWidgetData<String>(key, '');
      return;
    }
    // Удалённое настроение из каталога (публичный URL) — нативный виджет умеет
    // только локальные файлы, поэтому скачиваем картинку в файл (кэш по URL).
    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      await _cacheEmojiUrlForWidget(assetPath, key);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAsset = prefs.getString('${key}_cached_asset') ?? '';
      final cachedPath = prefs.getString('${key}_cached_path') ?? '';

      if (cachedAsset == assetPath &&
          cachedPath.isNotEmpty &&
          File(cachedPath).existsSync()) {
        await HomeWidget.saveWidgetData<String>(
            key, await HomeWidgetService.instance.appGroupReadablePath(cachedPath, key));
        return;
      }

      // Грузим ассет; если его нет в этой сборке (партнёр прислал эмодзи из
      // пака, которого у нас нет — постепенный раскат) — падаем на эквивалент
      // из классического пака, чтобы показать смайлик, а не пустоту с одной
      // лишь текстовой меткой.
      ByteData? byteData;
      try {
        byteData = await rootBundle.load(assetPath);
      } catch (_) {
        final fallback = MoodOption.classicFallbackFor(assetPath);
        if (fallback != null) byteData = await rootBundle.load(fallback);
      }
      if (byteData == null) {
        await HomeWidget.saveWidgetData<String>(key, '');
        return;
      }

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$key.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await HomeWidget.saveWidgetData<String>(
          key, await HomeWidgetService.instance.appGroupReadablePath(file.path, key));
      await prefs.setString('${key}_cached_asset', assetPath);
      await prefs.setString('${key}_cached_path', file.path);
      debugPrint('_cacheEmojiForWidget: $key cached at ${file.path}');
    } catch (e) {
      debugPrint('_cacheEmojiForWidget($key) failed: $e');
      await HomeWidget.saveWidgetData<String>(key, '');
    }
  }

  /// Скачать удалённую картинку настроения (URL каталога) в локальный файл для
  /// нативного виджета. При сбое сети — классический бандл-ассет по id.
  Future<void> _cacheEmojiUrlForWidget(String url, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAsset = prefs.getString('${key}_cached_asset') ?? '';
      final cachedPath = prefs.getString('${key}_cached_path') ?? '';
      if (cachedAsset == url &&
          cachedPath.isNotEmpty &&
          File(cachedPath).existsSync()) {
        await HomeWidget.saveWidgetData<String>(
            key, await HomeWidgetService.instance.appGroupReadablePath(cachedPath, key));
        return;
      }
      // Картинку настроения просят оба виджет-сервиса — берём со склада.
      final resp = await WidgetPhotoStore.instance.bytesFor(url, url);
      if (resp != null && resp.isNotEmpty) {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/$key.webp');
        await file.writeAsBytes(resp);
        await HomeWidget.saveWidgetData<String>(
            key, await HomeWidgetService.instance.appGroupReadablePath(file.path, key));
        await prefs.setString('${key}_cached_asset', url);
        await prefs.setString('${key}_cached_path', file.path);
        return;
      }
    } catch (e) {
      debugPrint('_cacheEmojiUrlForWidget($key) failed: $e');
    }
    // Фолбэк: классический ассет по id (имя файла URL = id настроения).
    final fallback = MoodOption.classicFallbackFor(url);
    if (fallback != null) {
      await _cacheEmojiForWidget(fallback, key);
    } else {
      await HomeWidget.saveWidgetData<String>(key, '');
    }
  }

  /// Скачивает изображение по [url] в файловый кэш и сохраняет путь
  /// под ключом [key] в SharedPreferences нативного виджета.
  Future<void> _downloadPhoto(String? url, String key) async {
    // null — половина не загружена, трогать её картинку нельзя: иначе каждый
    // холодный старт и каждый тихий пуш стирают фото с рабочего стола вместе с
    // файлом в общем контейнере (правило в pair_widget_payload.dart).
    if (url == null) return;
    if (url.isEmpty) {
      await HomeWidget.saveWidgetData<String>(key, '');
      // Фото убрали → чистим старые файлы этого ключа в контейнере, иначе iOS
      // держал бы закэшированную картинку по прежнему пути.
      await HomeWidgetService.instance.clearAppGroupMedia(key);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${key}_cached_url');
      await prefs.remove('${key}_cached_wpath');
      return;
    }
    try {
      String httpUrl = url;

      // pb:// (PocketBase protected media) → HTTPS с file-токеном. Токена нет —
      // качать нечего: без него сервер отвечает 404, а прежний снимок на
      // рабочем столе лучше пустоты.
      if (PbMediaService().isPbRef(url)) {
        final resolved = await PbMediaService().resolveUrlAuthed(url);
        if (resolved == null || resolved.isEmpty) return;
        httpUrl = resolved;
      }
      // Легаси gs:// (Firebase) / sb:// (Supabase) больше не резолвим — Firebase
      // убран. Такие старые ссылки в виджет не подгрузятся.
      else if (url.startsWith('gs://') || url.startsWith('sb://')) {
        await HomeWidget.saveWidgetData<String>(key, '');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('${key}_cached_url') ?? '';
      final cachedWPath = prefs.getString('${key}_cached_wpath') ?? '';

      // Кэш годится только если файл реально на месте: записи переживают
      // очистку контейнера, а файл — нет, и виджет оставался с путём в пустоту.
      // Правило — в widget_photo_cache.dart, под тестами.
      final cachedExists =
          cachedWPath.isNotEmpty && File(cachedWPath).existsSync();
      // Размер важнее существования: оборванная запись оставляет нулевой файл,
      // и он залипал навсегда — «файл на месте» значило «в сеть не идём».
      final cachedSize = cachedExists ? File(cachedWPath).lengthSync() : 0;
      if (photoCacheDecision(
            url: url,
            cachedUrl: cachedUrl,
            cachedPath: cachedWPath,
            cachedFileExists: cachedExists,
            cachedFileSize: cachedSize,
          ) ==
          PhotoCacheAction.useCached) {
        await HomeWidget.saveWidgetData<String>(key, cachedWPath);
        return;
      }

      // Уникальное имя = ключ + хэш ссылки. iOS WidgetKit кэширует картинку по
      // ПУТИ файла: при записи каждого нового фото в ОДИН и тот же файл виджет
      // держит старое изображение и не перерисовывается (баг «фото не
      // обновляется, пока стоит другое; уберёшь одно — второе оживает»). Меняя
      // путь при каждой смене фото, заставляем WidgetKit грузить свежее.
      final sig = url.hashCode.toUnsigned(32).toRadixString(16);
      final uniqueName = '${key}_$sig';

      // Один склад на всё приложение: экран и второй виджет-сервис берут ту же
      // картинку отсюда же, поэтому в сеть идёт только первый (widget_photo_store).
      final bytes = await WidgetPhotoStore.instance.bytesFor(url, httpUrl);

      if (bytes == null || bytes.length < kMinWidgetPhotoBytes) {
        debugPrint('_downloadPhoto($key): на складе пусто для $url');
        // Прежнее живое фото лучше пустоты: один неудачный запрос не должен
        // стирать снимок с рабочего стола.
        await HomeWidget.saveWidgetData<String>(
          key,
          photoFallbackOnFailure(
            cachedPath: cachedWPath,
            cachedFileExists: cachedExists,
            cachedFileSize: cachedSize,
          ),
        );
        return;
      }

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$uniqueName.jpg');
      // Ужимаем ДО записи: расширению виджета отводят около 30 МБ, а снимок с
      // камеры в разжатом виде занимает под пятьдесят — расширение убивают, и
      // вместо фотографии остаётся серый прямоугольник. Предел зависит от
      // ключа: фото 1200 точек, аватарка 400 (widget_image_limit.dart).
      await file.writeAsBytes(
        await HomeWidgetService.instance
            .shrinkForWidget(bytes, widgetImageMaxSide(key)),
      );

      // Старые файлы этого ключа (контейнер + локальные) убираем ДО записи нового
      // пути, чтобы не копились и не оставалось «залипшего» кэша по старому пути.
      await HomeWidgetService.instance.clearAppGroupMedia(key);
      _cleanupOldLocalPhotos(dir, key, '$uniqueName.jpg');

      final widgetPath = await HomeWidgetService.instance
          .appGroupReadablePath(file.path, uniqueName);
      await HomeWidget.saveWidgetData<String>(key, widgetPath);
      await prefs.setString('${key}_cached_url', url);
      await prefs.setString('${key}_cached_wpath', widgetPath);
      debugPrint('_downloadPhoto: $key → $widgetPath');
    } catch (e) {
      // Сюда попадает и недоступный мост App Group (MissingPluginException в
      // фоновом изоляте): затирать путь пустотой нельзя, иначе фото исчезает.
      debugPrint('_downloadPhoto($key) failed: $e');
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString('${key}_cached_wpath') ?? '';
      await HomeWidget.saveWidgetData<String>(
        key,
        photoFallbackOnFailure(
          cachedPath: prev,
          cachedFileExists: prev.isNotEmpty && File(prev).existsSync(),
          cachedFileSize:
              prev.isNotEmpty && File(prev).existsSync() ? File(prev).lengthSync() : 0,
        ),
      );
    }
  }

  /// Удаляет старые локальные файлы `<key>_*.jpg` (кроме [keepName]) из [dir] —
  /// чтобы уникальные имена фото не копились на диске.
  void _cleanupOldLocalPhotos(Directory dir, String key, String keepName) {
    try {
      for (final f in dir.listSync()) {
        if (f is! File) continue;
        final name = f.path.split(Platform.pathSeparator).last;
        if (name.startsWith('${key}_') &&
            name.endsWith('.jpg') &&
            name != keepName) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
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
