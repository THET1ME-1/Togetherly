import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chest_pending.dart';

/// Недоделанное открытие сундука на диске, своё у каждой пары.
class ChestPendingStore {
  const ChestPendingStore._();

  static String _key(String groupId) => 'chest_pending_$groupId';

  static Future<ChestPending?> read(String groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(groupId));
      if (raw == null) return null;
      final item = ChestPending.fromJson(jsonDecode(raw), now: DateTime.now());
      if (item == null) await prefs.remove(_key(groupId));
      return item;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String groupId, ChestPending item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(groupId), jsonEncode(item.toJson()));
    } catch (_) {}
  }

  static Future<void> clear(String groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(groupId));
    } catch (_) {}
  }
}
