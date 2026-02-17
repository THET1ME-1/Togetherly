import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timer_item.dart';

/// Сервис для управления пользовательскими таймерами.
/// Хранит данные в SharedPreferences.
class TimerService extends ChangeNotifier {
  static const _storageKey = 'user_timers';
  List<TimerItem> _timers = [];

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

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, TimerItem.encodeList(_timers));
  }

  // ── CRUD ──

  /// Создать новый таймер.
  Future<void> addTimer({
    required String title,
    required DateTime startDate,
    String emoji = '❤️',
    bool isDefault = false,
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
      ),
    );
    await _save();
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
    await _save();
    notifyListeners();
  }

  /// Удалить таймер по id.
  Future<void> deleteTimer(String id) async {
    _timers.removeWhere((t) => t.id == id);
    // Если удалили дефолтный — ставим первый
    if (_timers.isNotEmpty && !_timers.any((t) => t.isDefault)) {
      _timers.first.isDefault = true;
    }
    await _save();
    notifyListeners();
  }

  /// Назначить таймер «показываемым по умолчанию».
  Future<void> setDefault(String id) async {
    for (final t in _timers) {
      t.isDefault = t.id == id;
    }
    await _save();
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
}
