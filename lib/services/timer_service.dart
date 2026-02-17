import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timer_item.dart';
import 'firebase_service.dart';

/// Сервис для управления пользовательскими таймерами.
/// Хранит данные локально (SharedPreferences) и синхронизирует с Firestore
/// когда пользователь состоит в группе.
class TimerService extends ChangeNotifier {
  static const _storageKey = 'user_timers';
  final FirebaseService _fb = FirebaseService();
  List<TimerItem> _timers = [];
  String _groupId = '';
  StreamSubscription? _firestoreSub;

  List<TimerItem> get timers => List.unmodifiable(_timers);
  int get count => _timers.length;

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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _timers = TimerItem.decodeList(raw);
      } catch (_) {
        _timers = [];
      }
    }
    notifyListeners();
  }

  /// Привязать к группе — начинает синхронизацию с Firestore.
  /// Вызывается когда пользователь входит в группу.
  void bindToGroup(String groupId) {
    if (_groupId == groupId && groupId.isNotEmpty) return;
    _firestoreSub?.cancel();
    _groupId = groupId;
    if (groupId.isEmpty) return;

    // Слушаем изменения таймеров в Firestore
    _firestoreSub = _fb.listenToTimers(
      groupId: groupId,
      onData: (remoteTimers) {
        _mergeRemoteTimers(remoteTimers);
      },
    );
  }

  /// Отвязать от группы (при unpair)
  void unbindFromGroup() {
    _firestoreSub?.cancel();
    _firestoreSub = null;
    _groupId = '';
  }

  /// Слияние remote таймеров с локальными.
  /// Remote таймеры имеют приоритет.
  void _mergeRemoteTimers(List<TimerItem> remote) {
    // Заменяем полностью на remote, но сохраняем локальные таймеры
    // которых нет в remote (только если нет groupId — значит локальные)
    _timers = remote;

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

    _saveLocal();
    notifyListeners();
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
    await _saveLocal();
    await _saveToFirestore();
    notifyListeners();
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
    await _saveLocal();
    await _saveToFirestore();
    notifyListeners();
  }

  /// Удалить таймер по id. Системные таймеры удалить нельзя.
  Future<void> deleteTimer(String id) async {
    final timer = _timers.firstWhere(
      (t) => t.id == id,
      orElse: () => TimerItem(id: '', title: '', startDate: DateTime.now()),
    );
    if (timer.isSystem) return; // нельзя удалить системный таймер

    _timers.removeWhere((t) => t.id == id);
    // Если удалили дефолтный — ставим первый
    if (_timers.isNotEmpty && !_timers.any((t) => t.isDefault)) {
      _timers.first.isDefault = true;
    }
    await _saveLocal();
    await _saveToFirestore();
    notifyListeners();
  }

  /// Назначить таймер «показываемым по умолчанию».
  Future<void> setDefault(String id) async {
    for (final t in _timers) {
      t.isDefault = t.id == id;
    }
    await _saveLocal();
    await _saveToFirestore();
    notifyListeners();
  }

  /// Создать системный таймер при создании группы.
  /// Если системный уже есть — не создаёт повторно.
  Future<void> createSystemTimer({
    required DateTime startDate,
    required String relationshipLabel,
    required String relationshipEmoji,
    required String partnerName,
  }) async {
    // Не создаём дубликат
    if (systemTimer != null) return;

    final title = '$relationshipLabel with $partnerName';
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
    await _saveLocal();
    await _saveToFirestore();
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

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }
}
