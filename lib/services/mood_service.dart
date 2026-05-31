import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/mood_entry.dart';
import '../models/pair_data.dart';
import 'firebase_service.dart';
import 'widget_service.dart';

/// Сервис для управления записями настроений (mood calendar).
/// Хранит данные в Firestore: groups/{groupId}/moodCalendar/{uid}/entries/{entryId}
class MoodService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();

  /// Окно live-слушателя mood-истории. Покрывает все горячие пути
  /// (home, mini-calendar, mood-виджет, year-view текущего года и streak до
  /// 365 дней), но обрезает бесконечный рост чтений у долгосрочных пар.
  /// Записи старше окна догружаются по требованию в mood_calendar_screen.
  static const Duration _listenWindow = Duration(days: 400);

  DateTime get _listenSince =>
      DateTime.now().subtract(_listenWindow);

  String _groupId = '';
  String get groupId => _groupId;

  /// Сервисы для атомарного апдейта всех трёх источников настроения
  /// (calendar entries + group memberMoods + widgetData). Заполняются один раз
  /// при старте через [bindServices]; без них setMoodForToday работает только
  /// с календарём.
  PairData? _pairData;
  WidgetService? _widgetService;

  void bindServices({
    required PairData pairData,
    required WidgetService widgetService,
  }) {
    _pairData = pairData;
    _widgetService = widgetService;
  }

  /// Мои записи настроений
  List<MoodEntry> _myEntries = [];
  List<MoodEntry> get myEntries => List.unmodifiable(_myEntries);

  /// Записи партнёров: uid → entries
  final Map<String, List<MoodEntry>> _partnerEntries = {};
  List<MoodEntry> partnerEntries(String uid) =>
      List.unmodifiable(_partnerEntries[uid] ?? []);

  StreamSubscription? _myMoodSub;
  final Map<String, StreamSubscription?> _partnerMoodSubs = {};

  // ── Единый источник правды для «сегодняшнего» настроения ─────────────────
  // Все UI (home_header, mini_mood_calendar, mood_calendar_screen, widget_screen)
  // должны читать через myMoodToday вместо отдельных источников
  // (pairData.myMood / widgetService._myData.moodEmoji). Иначе три источника
  // расходятся и пользователь видит разные эмодзи в разных местах.

  /// Текущее настроение пользователя на сегодня — самая свежая запись
  /// календаря, или null если ещё не выбрано.
  MoodEntry? get myMoodToday {
    final today = DateTime.now();
    final entries = myEntriesForDay(today);
    return entries.isNotEmpty ? entries.first : null;
  }

  /// Текущее настроение партнёра на сегодня.
  MoodEntry? partnerMoodToday(String uid) {
    final entries = partnerEntriesForDay(uid, DateTime.now());
    return entries.isNotEmpty ? entries.first : null;
  }

  /// Привязаться к группе и начать слушать.
  void bindToGroup(String groupId) {
    if (groupId == _groupId && groupId.isNotEmpty) return;
    unbindFromGroup(notify: false);
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
      since: _listenSince,
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
    _partnerEntries.remove(partnerUid);
    _partnerMoodSubs[partnerUid] = _fb.listenToMoodEntries(
      groupId: _groupId,
      uid: partnerUid,
      since: _listenSince,
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

  void unbindFromGroup({bool notify = true}) {
    _myMoodSub?.cancel();
    _myMoodSub = null;
    for (final sub in _partnerMoodSubs.values) {
      sub?.cancel();
    }
    _partnerMoodSubs.clear();
    _groupId = '';
    _myEntries = [];
    _partnerEntries.clear();
    if (notify) {
      notifyListeners();
    }
  }

  /// Добавить настроение.
  /// [date] — если указана, настроение записывается на эту дату (в полдень),
  /// иначе — на текущий момент.
  Future<void> addMood({
    required String moodId,
    required String imagePath,
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
      imagePath: imagePath,
      label: label,
      timestamp: ts,
    );
    await _fb.addMoodEntry(groupId: _groupId, entry: entry.toFirestore());
  }

  /// Установить настроение на сегодня атомарно во всех источниках.
  /// Удаляет старые записи за сегодня (чтобы mini_mood_calendar не циклил
  /// между старыми и новыми эмодзи), пишет новую запись в календарь,
  /// обновляет group memberMoods и widgetData. Единая точка входа для всех
  /// пикеров — гарантирует согласованность header/calendar/widget.
  Future<void> setMoodForToday({
    required String moodId,
    required String imagePath,
    required String label,
  }) async {
    if (_groupId.isEmpty) return;
    final today = DateTime.now();

    // 1. Удаляем все существующие записи на сегодня — параллельно, чтобы
    // listener не успел показать несогласованное промежуточное состояние.
    final existing = myEntriesForDay(today);
    await Future.wait(
      existing.map((e) => _fb.deleteMoodEntry(groupId: _groupId, entryId: e.id)),
    );

    // 2. Календарь — каноничный источник.
    await addMood(moodId: moodId, imagePath: imagePath, label: label);

    // 3. Group memberMoods — для шапки и партнёра.
    await _pairData?.setMood(imagePath, label);

    // 4. WidgetData — для нативного виджета. skipCalendar: уже добавили выше.
    await _widgetService?.updateMood(imagePath, label, skipCalendar: true);
  }

  /// Установить настроение на конкретную дату. Для прошлых дат обновляется
  /// только календарь; для сегодня — все три источника через setMoodForToday.
  Future<void> setMoodForDate({
    required DateTime date,
    required String moodId,
    required String imagePath,
    required String label,
  }) async {
    if (_groupId.isEmpty) return;
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (isToday) {
      await setMoodForToday(moodId: moodId, imagePath: imagePath, label: label);
      return;
    }

    // Прошлая дата — только календарь.
    final existing = myEntriesForDay(date);
    await Future.wait(
      existing.map((e) => _fb.deleteMoodEntry(groupId: _groupId, entryId: e.id)),
    );
    await addMood(
      moodId: moodId,
      imagePath: imagePath,
      label: label,
      date: date,
    );
  }

  /// Очистить настроение на сегодня атомарно во всех источниках.
  Future<void> clearMoodForToday() async {
    if (_groupId.isEmpty) return;
    final today = DateTime.now();
    final existing = myEntriesForDay(today);
    await Future.wait(
      existing.map((e) => _fb.deleteMoodEntry(groupId: _groupId, entryId: e.id)),
    );
    await _pairData?.clearMood();
    await _widgetService?.clearMood();
  }

  /// Очистить настроение на конкретную дату (для прошлых — только календарь).
  Future<void> clearMoodForDate(DateTime date) async {
    if (_groupId.isEmpty) return;
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (isToday) {
      await clearMoodForToday();
      return;
    }

    final existing = myEntriesForDay(date);
    await Future.wait(
      existing.map((e) => _fb.deleteMoodEntry(groupId: _groupId, entryId: e.id)),
    );
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

  /// Количество последовательных дней, когда И я, И все известные партнёры
  /// заполняли настроение подряд (считается назад от сегодня).
  int get bothPartnersStreakDays {
    if (_partnerEntries.isEmpty) return 0;
    final myDays = _myEntries.map((e) => e.dayKey).toSet();
    // Берём дни всех партнёров — если несколько, нужно пересечение
    Set<String>? partnerDays;
    for (final entries in _partnerEntries.values) {
      final days = entries.map((e) => e.dayKey).toSet();
      partnerDays = partnerDays == null ? days : partnerDays.intersection(days);
    }
    if (partnerDays == null || partnerDays.isEmpty) return 0;
    final bothDays = myDays.intersection(partnerDays);
    int streak = 0;
    var day = DateTime.now();
    for (var i = 0; i < 365; i++) {
      final key = _dayKey(day);
      if (!bothDays.contains(key)) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
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
    unbindFromGroup(notify: false);
    super.dispose();
  }
}
