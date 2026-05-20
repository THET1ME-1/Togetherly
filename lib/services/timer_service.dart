import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timer_item.dart';
import 'firebase_service.dart';
import 'home_widget_service.dart';

/// Сервис для управления пользовательскими таймерами.
/// Хранит данные локально (SharedPreferences) и синхронизирует с Firestore
/// когда пользователь состоит в группе.
class TimerService extends ChangeNotifier {
  static const _localStorageKey = 'user_timers_local';
  final FirebaseService _fb = FirebaseService();
  List<TimerItem> _timers = [];
  String _groupId = '';
  StreamSubscription? _firestoreSub;
  bool _hasReceivedRemoteSync = false; // флаг первой синхронизации с Firestore

  // Параметры ожидающего создания системного таймера
  Map<String, dynamic>? _pendingSystemTimer;

  List<TimerItem> get timers => List.unmodifiable(_timers);
  int get count => _timers.length;

  String get _storageKey {
    final uid = _fb.uid ?? 'guest';
    return _groupId.isNotEmpty
        ? 'user_timers_${uid}_$_groupId'
        : '${_localStorageKey}_$uid';
  }

  /// Таймер, отображаемый по умолчанию в свёрнутом виде.
  TimerItem? get defaultTimer {
    try {
      return _timers.firstWhere((t) => t.isDefault);
    } catch (_) {
      return _timers.isNotEmpty ? _timers.first : null;
    }
  }

  /// Системный таймер (неудаляемый, создаётся при создании группы)
  TimerItem? get systemTimer {
    try {
      return _timers.firstWhere((t) => t.isSystem);
    } catch (_) {
      return null;
    }
  }

  // ── Инициализация ──

  Future<void> init() async {
    await _loadLocal();
    // Sync widget after loading timers (for solo mode on first app launch)
    await _syncWidgetTimer();
    notifyListeners();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _timers = TimerItem.decodeList(raw);
        return;
      } catch (_) {}
    }
    _timers = [];
  }

  /// Привязать к группе — начинает синхронизацию с Firestore.
  /// Вызывается когда пользователь входит в группу.
  Future<void> bindToGroup(String groupId) async {
    if (_groupId == groupId && groupId.isNotEmpty) return;
    _firestoreSub?.cancel();
    _groupId = groupId;
    _hasReceivedRemoteSync = false;
    _pendingSystemTimer = null;
    _timers = [];
    await _loadLocal();
    notifyListeners();
    if (groupId.isEmpty) return;

    // Слушаем изменения таймеров в Firestore
    _firestoreSub = _fb.listenToTimers(
      groupId: groupId,
      onData: (remoteTimers) {
        _mergeRemoteTimers(remoteTimers);
      },
    );
  }

  /// Отвязать от группы (при unpair или переключении на соло)
  Future<void> unbindFromGroup() async {
    _firestoreSub?.cancel();
    _firestoreSub = null;
    _groupId = '';
    _hasReceivedRemoteSync = false;
    _pendingSystemTimer = null;
    await _loadLocal();
    // Sync widget for solo mode after unbind
    await _syncWidgetTimer();
    notifyListeners();
  }

  /// Слияние remote таймеров с локальными.
  /// Remote таймеры имеют приоритет.
  void _mergeRemoteTimers(List<TimerItem> remote) {
    // Очищаем устаревшие локальные пути (не URL) — они не синхронизируются
    bool hadStalePaths = false;
    _timers = remote.map((t) {
      final path = t.backgroundImagePath;
      if (path != null && !path.startsWith('http')) {
        // Локальный путь от другого устройства — удаляем
        debugPrint(
          'TimerService: очищаю устаревший локальный путь у таймера ${t.id}',
        );
        hadStalePaths = true;
        return t.copyWith()..backgroundImagePath = null;
      }
      return t;
    }).toList();

    debugPrint(
      'TimerService: _mergeRemoteTimers: получено ${_timers.length} таймеров, '
      'backgroundImagePaths: ${_timers.map((t) => t.backgroundImagePath ?? "null").join(", ")}',
    );

    // Гарантируем что хотя бы один default
    if (_timers.isNotEmpty && !_timers.any((t) => t.isDefault)) {
      // Системный таймер будет default
      final sys = systemTimer;
      if (sys != null) {
        sys.isDefault = true;
      } else {
        _timers.first.isDefault = true;
      }
    }

    _hasReceivedRemoteSync = true;

    // Если был устаревший путь — сохраняем чистые данные обратно в Firestore
    if (hadStalePaths) {
      _saveToFirestore();
    }

    // Если был ожидающий системный таймер — создаём его сейчас (если ещё нет)
    if (_pendingSystemTimer != null && systemTimer == null) {
      final p = _pendingSystemTimer!;
      _pendingSystemTimer = null;
      debugPrint('TimerService: создаю отложенный системный таймер');
      addTimer(
        title: p['title'] as String,
        startDate: p['startDate'] as DateTime,
        emoji: p['emoji'] as String,
        isDefault: true,
        isSystem: true,
      );
      return; // addTimer вызовет notifyListeners сам
    }

    _saveLocal();
    notifyListeners();
  }

  void _ensureDefaultFlag() {
    if (_timers.isNotEmpty && !_timers.any((t) => t.isDefault)) {
      final sys = systemTimer;
      if (sys != null) {
        sys.isDefault = true;
      } else {
        _timers.first.isDefault = true;
      }
    }
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, TimerItem.encodeList(_timers));
  }

  Future<void> _saveToFirestore() async {
    if (_groupId.isEmpty) {
      debugPrint('TimerService: не могу сохранить в Firestore - groupId пуст');
      return;
    }
    debugPrint(
      'TimerService: сохраняю ${_timers.length} таймеров в Firestore для группы $_groupId',
    );
    await _fb.saveTimers(
      groupId: _groupId,
      timers: _timers.map((t) => t.toJson()).toList(),
    );
    debugPrint('TimerService: таймеры успешно сохранены');
  }

  // ── CRUD ──

  /// Создать новый таймер.
  Future<void> addTimer({
    required String title,
    required DateTime startDate,
    String emoji = '❤️',
    bool isDefault = false,
    bool isSystem = false,
    bool isCountdown = false,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    if (isDefault) {
      for (final t in _timers) {
        t.isDefault = false;
      }
    }
    _timers.add(
      TimerItem(
        id: id,
        title: title,
        startDate: startDate,
        isDefault: isDefault || _timers.isEmpty,
        emoji: emoji,
        isSystem: isSystem,
        isCountdown: isCountdown,
      ),
    );
    _ensureDefaultFlag();
    await _saveLocal();
    if (_groupId.isNotEmpty) {
      await _fb.upsertGroupTimer(
        groupId: _groupId,
        timer: _timers.last.toJson(),
      );
    }
    // Sync widget immediately after creating timer (single user mode)
    await _syncWidgetTimer();
    notifyListeners();
  }

  Future<void> _syncWidgetTimer() async {
    if (_timers.isEmpty) {
      debugPrint('TimerService._syncWidgetTimer: нет таймеров, очищаю виджет');
      await HomeWidgetService.instance.clearTimerWidget();
      return;
    }
    final timer = defaultTimer ?? _timers.first;
    debugPrint('TimerService._syncWidgetTimer: syncing timer ${timer.id} title=${timer.title} startDate=${timer.startDate} groupId=$_groupId');
    await HomeWidgetService.instance.syncTimer(timer, groupId: _groupId);
  }

  /// Обновить существующий таймер.
  Future<void> updateTimer(TimerItem updated) async {
    final idx = _timers.indexWhere((t) => t.id == updated.id);
    if (idx == -1) return;
    if (updated.isDefault) {
      for (final t in _timers) {
        t.isDefault = false;
      }
    }
    _timers[idx] = updated;
    _ensureDefaultFlag();
    await _saveLocal();
    if (_groupId.isNotEmpty) {
      await _fb.upsertGroupTimer(groupId: _groupId, timer: updated.toJson());
    }
    await _syncWidgetTimer();
    notifyListeners();
  }

  /// Удалить таймер по id. Системные таймеры удалить нельзя.
  Future<void> deleteTimer(String id) async {
    final timer = _timers.firstWhere(
      (t) => t.id == id,
      orElse: () => TimerItem(id: '', title: '', startDate: DateTime.now()),
    );
    if (timer.isSystem) return; // нельзя удалить системный таймер

    debugPrint('TimerService.deleteTimer: удаляю таймер $id (${timer.title}), groupId=$_groupId');
    
    _timers.removeWhere((t) => t.id == id);
    // Если удалили дефолтный — ставим первый
    if (_timers.isNotEmpty && !_timers.any((t) => t.isDefault)) {
      _timers.first.isDefault = true;
    }
    await _saveLocal();
    debugPrint('TimerService.deleteTimer: сохранено в local, таймеров: ${_timers.length}');
    
    if (_groupId.isNotEmpty) {
      await _fb.deleteGroupTimer(groupId: _groupId, timerId: id);
      debugPrint('TimerService.deleteTimer: удалено из Firestore');
    }
    
    await _syncWidgetTimer();
    notifyListeners();
    debugPrint('TimerService.deleteTimer: завершено, синхронизировано с виджетом');
  }

  /// Назначить таймер «показываемым по умолчанию».
  Future<void> setDefault(String id) async {
    for (final t in _timers) {
      t.isDefault = t.id == id;
    }
    _ensureDefaultFlag();
    await _saveLocal();
    if (_groupId.isNotEmpty) {
      await _fb.setDefaultGroupTimer(groupId: _groupId, timerId: id);
    }
    await _syncWidgetTimer();
    notifyListeners();
  }

  /// Создать системный таймер при создании группы.
  /// Если системный уже есть — не создаёт повторно.
  /// Если Firestore ещё не синхронизировался — откладывает создание.
  Future<void> createSystemTimer({
    required DateTime startDate,
    required String relationshipLabel,
    required String relationshipEmoji,
    required String partnerName,
  }) async {
    // Не создаём дубликат
    if (systemTimer != null) return;

    final title = '$relationshipLabel with $partnerName';

    // Если группа привязана, но Firestore ещё не ответил — откладываем.
    // _mergeRemoteTimers создаст таймер как только получит первый снимок.
    if (_groupId.isNotEmpty && !_hasReceivedRemoteSync) {
      debugPrint(
        'TimerService: createSystemTimer — ждём первую синхронизацию с Firestore',
      );
      _pendingSystemTimer = {
        'title': title,
        'startDate': startDate,
        'emoji': relationshipEmoji,
      };
      return;
    }

    await addTimer(
      title: title,
      startDate: startDate,
      emoji: relationshipEmoji,
      isDefault: true,
      isSystem: true,
    );
  }

  /// Обновить название системного таймера при смене статуса/типа отношений.
  Future<void> updateSystemTimerTitle({
    required String relationshipLabel,
    required String relationshipEmoji,
    required String partnerName,
  }) async {
    final sys = systemTimer;
    if (sys == null) return;

    final newTitle = '$relationshipLabel with $partnerName';
    if (sys.title == newTitle && sys.emoji == relationshipEmoji) return;

    sys.title = newTitle;
    sys.emoji = relationshipEmoji;
    _ensureDefaultFlag();
    await _saveLocal();
    if (_groupId.isNotEmpty) {
      await _fb.upsertGroupTimer(groupId: _groupId, timer: sys.toJson());
    }
    await _syncWidgetTimer();
    notifyListeners();
  }

  /// Создать «стартовый» таймер из PairData, если таймеров ещё нет.
  Future<void> ensureDefaultFromPair({
    required DateTime startDate,
    required String partnerName,
    required String relationshipLabel,
  }) async {
    if (_timers.isNotEmpty) return;
    await addTimer(
      title: '$relationshipLabel with $partnerName',
      startDate: startDate,
      emoji: '❤️',
      isDefault: true,
    );
  }

  /// Загружает изображение в Firebase Storage и устанавливает его фоном таймера.
  /// Возвращает true при успехе. Старый фон (если был URL) удаляется из Storage.
  Future<bool> uploadTimerBackground(
    TimerItem timer,
    String localFilePath,
  ) async {
    if (_groupId.isEmpty) {
      debugPrint('TimerService: uploadTimerBackground — groupId пуст');
      return false;
    }
    try {
      // Удаляем старый фон из Storage, если это был URL
      final old = timer.backgroundImagePath;
      if (old != null && old.startsWith('http')) {
        try {
          await _fb.deleteFileByUrl(old);
        } catch (_) {}
      }

      final ext = localFilePath.split('.').last.toLowerCase();
      final storagePath = 'timer_backgrounds/$_groupId/${timer.id}.$ext';
      final url = await _fb.uploadFile(localFilePath, storagePath);
      if (url == null) return false;

      // Удаляем локальную копию — больше не нужна
      try {
        final f = File(localFilePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      await updateTimer(timer.copyWith(backgroundImagePath: url));
      return true;
    } catch (e) {
      debugPrint('TimerService: uploadTimerBackground error: $e');
      return false;
    }
  }

  /// Удаляет фоновое изображение таймера (из Storage и локально).
  Future<void> removeTimerBackground(TimerItem timer) async {
    final path = timer.backgroundImagePath;
    if (path == null) return;
    // Удаляем из Firebase Storage, если это URL
    if (path.startsWith('http')) {
      try {
        await _fb.deleteFileByUrl(path);
      } catch (_) {}
    } else {
      // Локальный файл (legacy)
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await updateTimer(timer.copyWith()..backgroundImagePath = null);
  }

  /// Полная очистка всех таймеров — при выходе или новой регистрации.
  Future<void> clearAll() async {
    _timers.clear();
    _firestoreSub?.cancel();
    _firestoreSub = null;
    _groupId = '';
    _hasReceivedRemoteSync = false;
    _pendingSystemTimer = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }
}
