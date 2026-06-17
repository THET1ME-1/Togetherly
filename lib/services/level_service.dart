import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/level.dart';
import 'firebase_service.dart';

/// Действия, дающие XP. Добавить источник = строка в [_rules] + вызов
/// `LevelService.instance.award(...)` в нужном месте.
enum XpAction { dailyStreak, addMemory, watchTogether, setWidget, changeMood }

class _XpRule {
  final int amount;

  /// Макс. раз в день (0 = без дневного лимита).
  final int dailyCap;

  /// Выдать один раз навсегда (для разовых ачивок вроде «поставил виджет»).
  final bool onceEver;

  const _XpRule(this.amount, {this.dailyCap = 0, this.onceEver = false});
}

const Map<XpAction, _XpRule> _rules = {
  XpAction.dailyStreak: _XpRule(20, dailyCap: 1),
  XpAction.addMemory: _XpRule(15, dailyCap: 3),
  XpAction.watchTogether: _XpRule(25, dailyCap: 2),
  XpAction.setWidget: _XpRule(30, onceEver: true),
  XpAction.changeMood: _XpRule(5, dailyCap: 1),
};

/// Уровень ПАРЫ. XP — общий групповой счётчик (растёт как memoriesCount,
/// дуал-райт Firebase↔Supabase). Сам xp приходит из стрима групп-состояния
/// (MascotService.setXp); [award] начисляет с антифарм-лимитами.
class LevelService extends ChangeNotifier {
  LevelService._();
  static final LevelService _instance = LevelService._();
  static LevelService get instance => _instance;

  final FirebaseService _fb = FirebaseService();

  String _groupId = '';
  int _xp = 0;

  int get xp => _xp;
  int get level => levelForXp(_xp);
  LevelProgress get progress => LevelProgress.fromXp(_xp);

  void bind(String groupId) {
    _groupId = groupId;
  }

  /// Актуальный xp с сервера (из стрима групп-состояния). Идемпотентно.
  void setXp(int xp) {
    if (xp == _xp) return;
    _xp = xp;
    notifyListeners();
  }

  /// Начислить XP за [action] с учётом дневного лимита/разовости. Безопасно
  /// звать часто — лишние вызовы просто ничего не делают.
  Future<void> award(XpAction action) async {
    if (_groupId.isEmpty) return;
    final rule = _rules[action];
    if (rule == null) return;
    final allowed = await _consume(action, rule);
    if (!allowed) return;

    // Оптимистично двигаем локально; авторитетное значение придёт стримом.
    _xp += rule.amount;
    notifyListeners();
    await _fb.addGroupXp(_groupId, rule.amount);
  }

  /// Проверить и «потратить» дневной/разовый лимит. true — можно начислять.
  Future<bool> _consume(XpAction action, _XpRule rule) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final a = action.name;
      if (rule.onceEver) {
        final key = 'xp_once_${a}_$_groupId';
        if (prefs.getBool(key) ?? false) return false;
        await prefs.setBool(key, true);
        return true;
      }
      if (rule.dailyCap > 0) {
        final now = DateTime.now();
        final day =
            '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        final key = 'xp_day_${a}_${_groupId}_$day';
        final count = prefs.getInt(key) ?? 0;
        if (count >= rule.dailyCap) return false;
        await prefs.setInt(key, count + 1);
        return true;
      }
      return true; // без лимита
    } catch (_) {
      return false; // при сбое prefs не рискуем двойным начислением
    }
  }

  // ── Для экрана «Уровень и задания» ──────────────────────────────────────────

  /// Все действия-задания в порядке отображения.
  List<XpAction> get actions => XpAction.values;

  /// Награда XP за действие.
  int rewardFor(XpAction a) => _rules[a]?.amount ?? 0;

  /// Дневной лимит (0 = без лимита).
  int dailyCapFor(XpAction a) => _rules[a]?.dailyCap ?? 0;

  /// Разовое ли действие (ачивка навсегда).
  bool isOnceEver(XpAction a) => _rules[a]?.onceEver ?? false;

  /// Прогресс за сегодня: для дневных — сколько раз зачтено; для разовых — 1/0.
  /// Ключи prefs совпадают с [_consume]. Для UI заданий.
  Future<int> progressToday(XpAction action) async {
    final rule = _rules[action];
    if (rule == null || _groupId.isEmpty) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final a = action.name;
      if (rule.onceEver) {
        return (prefs.getBool('xp_once_${a}_$_groupId') ?? false) ? 1 : 0;
      }
      final now = DateTime.now();
      final day =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      return prefs.getInt('xp_day_${a}_${_groupId}_$day') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Сбросить привязку (выход из группы).
  void unbind() {
    _groupId = '';
    _xp = 0;
  }
}
