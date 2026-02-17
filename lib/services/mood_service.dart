import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/mood_entry.dart';
import 'firebase_service.dart';

/// Сервис для управления записями настроений (mood calendar).
/// Хранит данные в Firestore: groups/{groupId}/moodCalendar/{uid}/entries/{entryId}
class MoodService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();

  String _groupId = '';
  String get groupId => _groupId;

  /// Мои записи настроений
  List<MoodEntry> _myEntries = [];
  List<MoodEntry> get myEntries => List.unmodifiable(_myEntries);

  /// Записи партнёров: uid → entries
  final Map<String, List<MoodEntry>> _partnerEntries = {};
  List<MoodEntry> partnerEntries(String uid) =>
      List.unmodifiable(_partnerEntries[uid] ?? []);

  StreamSubscription? _myMoodSub;
  final Map<String, StreamSubscription?> _partnerMoodSubs = {};

  /// Привязаться к группе и начать слушать.
  void bindToGroup(String groupId) {
    if (groupId == _groupId && groupId.isNotEmpty) return;
    _groupId = groupId;
    _startListening();
  }

  /// Начать слушать мои записи.
  void _startListening() {
    _myMoodSub?.cancel();
    final uid = _fb.uid;
    if (_groupId.isEmpty || uid == null) return;

    _myMoodSub = _fb.listenToMoodEntries(
      groupId: _groupId,
      uid: uid,
      onData: (entries) {
        _myEntries = entries.map((e) => MoodEntry.fromFirestore(e)).toList();
        _myEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        notifyListeners();
      },
    );
  }

  /// Подписаться на записи конкретного партнёра.
  void listenToPartner(String partnerUid) {
    if (_groupId.isEmpty) return;
    _partnerMoodSubs[partnerUid]?.cancel();
    _partnerMoodSubs[partnerUid] = _fb.listenToMoodEntries(
      groupId: _groupId,
      uid: partnerUid,
      onData: (entries) {
        _partnerEntries[partnerUid] = entries
            .map((e) => MoodEntry.fromFirestore(e))
            .toList();
        _partnerEntries[partnerUid]!.sort(
          (a, b) => b.timestamp.compareTo(a.timestamp),
        );
        notifyListeners();
      },
    );
  }

  /// Добавить настроение.
  /// [date] — если указана, настроение записывается на эту дату (в полдень),
  /// иначе — на текущий момент.
  Future<void> addMood({
    required String moodId,
    required String emoji,
    required String label,
    DateTime? date,
  }) async {
    if (_groupId.isEmpty) return;
    final now = DateTime.now();
    final ts = date != null
        ? DateTime(
            date.year,
            date.month,
            date.day,
            now.hour,
            now.minute,
            now.second,
          )
        : now;
    final id = '${_fb.uid}_${ts.millisecondsSinceEpoch}';
    final entry = MoodEntry(
      id: id,
      moodId: moodId,
      emoji: emoji,
      label: label,
      timestamp: ts,
    );
    await _fb.addMoodEntry(groupId: _groupId, entry: entry.toFirestore());
  }

  /// Удалить запись настроения.
  Future<void> deleteMoodEntry(String entryId) async {
    if (_groupId.isEmpty) return;
    await _fb.deleteMoodEntry(groupId: _groupId, entryId: entryId);
  }

  /// Получить записи за конкретный день (мои).
  List<MoodEntry> myEntriesForDay(DateTime date) {
    final key = _dayKey(date);
    return _myEntries.where((e) => e.dayKey == key).toList();
  }

  /// Получить записи партнёра за конкретный день.
  List<MoodEntry> partnerEntriesForDay(String uid, DateTime date) {
    final key = _dayKey(date);
    final entries = _partnerEntries[uid] ?? [];
    return entries.where((e) => e.dayKey == key).toList();
  }

  /// Группировка по дням (мои записи).
  Map<String, List<MoodEntry>> get myEntriesByDay {
    final map = <String, List<MoodEntry>>{};
    for (final e in _myEntries) {
      map.putIfAbsent(e.dayKey, () => []).add(e);
    }
    return map;
  }

  /// Статистика за период: {moodId: count}
  Map<String, int> myStats({required DateTime from, required DateTime to}) {
    final counts = <String, int>{};
    for (final e in _myEntries) {
      if (e.timestamp.isAfter(from) &&
          e.timestamp.isBefore(to.add(const Duration(days: 1)))) {
        counts[e.moodId] = (counts[e.moodId] ?? 0) + 1;
      }
    }
    return counts;
  }

  Map<String, int> partnerStats(
    String uid, {
    required DateTime from,
    required DateTime to,
  }) {
    final entries = _partnerEntries[uid] ?? [];
    final counts = <String, int>{};
    for (final e in entries) {
      if (e.timestamp.isAfter(from) &&
          e.timestamp.isBefore(to.add(const Duration(days: 1)))) {
        counts[e.moodId] = (counts[e.moodId] ?? 0) + 1;
      }
    }
    return counts;
  }

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  void dispose() {
    _myMoodSub?.cancel();
    for (final sub in _partnerMoodSubs.values) {
      sub?.cancel();
    }
    super.dispose();
  }
}
