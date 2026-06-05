import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mood_entry.dart';
import '../models/pair_data.dart';
import 'firebase_service.dart';
import 'widget_service.dart';

/// Сервис для управления записями настроений (mood calendar).
/// Хранит данные в Firestore: groups/{groupId}/moodCalendar/{uid}/entries/{entryId}
class MoodService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();

  /// Окно истории/миграции. Покрывает горячие пути (home, mini-calendar,
  /// mood-виджет, year-view текущего/прошлого года и streak до 365 дней).
  /// Ограничивает объём разовых чтений (история + legacy-fallback + миграция).
  static const Duration _listenWindow = Duration(days: 400);

  /// Сколько month-документов истории грузим разово (≈ окно в месяцах + запас).
  static const int _historyMonths = 14;

  /// Префикс ключа SharedPreferences «свои данные мигрированы в month-доки».
  static const String _migratedPrefix = 'mood_migrated_v2_';

  DateTime get _listenSince =>
      DateTime.now().subtract(_listenWindow);

  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}';

  Map<String, MoodEntry> _toById(List<Map<String, dynamic>> raw) {
    final m = <String, MoodEntry>{};
    for (final r in raw) {
      final e = MoodEntry.fromFirestore(r);
      if (e.id.isNotEmpty) m[e.id] = e;
    }
    return m;
  }

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

  // ── Настройка: несколько настроений в день ───────────────────────────────
  // false (по умолчанию) — одно настроение в день: setMoodForToday/ForDate
  // удаляют прежние записи дня перед добавлением. true — каждое настроение
  // сохраняется отдельной записью (как было в ранних версиях).
  static const String _kMultiplePerDayKey = 'mood_allow_multiple_per_day';
  bool _settingsLoaded = false;
  bool _allowMultiplePerDay = false;
  bool get allowMultipleMoodsPerDay => _allowMultiplePerDay;

  /// Загружает настройки из SharedPreferences (идемпотентно).
  Future<void> loadSettings() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _allowMultiplePerDay = prefs.getBool(_kMultiplePerDayKey) ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setAllowMultipleMoodsPerDay(bool value) async {
    _settingsLoaded = true;
    _allowMultiplePerDay = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMultiplePerDayKey, value);
    } catch (_) {}
    notifyListeners();
  }

  /// Мои записи настроений (плоский отсортированный список — публичный API).
  List<MoodEntry> _myEntries = [];
  List<MoodEntry> get myEntries => List.unmodifiable(_myEntries);

  /// Записи партнёров: uid → entries (плоский список).
  final Map<String, List<MoodEntry>> _partnerEntries = {};
  List<MoodEntry> partnerEntries(String uid) =>
      List.unmodifiable(_partnerEntries[uid] ?? []);

  // ── Источники моих записей (склеиваются с дедупом по id в _rebuildMine) ──
  // _myHistory — старые месяцы (разовая cache-first загрузка month-доков),
  // _myLiveMonth — текущий месяц (live-подписка на 1 документ → real-time).
  Map<String, MoodEntry> _myLegacy = {};
  Map<String, MoodEntry> _myHistory = {};
  Map<String, MoodEntry> _myLiveMonth = {};
  StreamSubscription? _myMonthSub;

  // ── Источники записей партнёра (по uid) ──
  // _partnerLegacy — fallback для НЕ мигрированного партнёра (v1-записи),
  // _partnerHistory — month-доки истории, _partnerLiveMonth — текущий месяц live.
  final Map<String, Map<String, MoodEntry>> _partnerLegacy = {};
  final Map<String, Map<String, MoodEntry>> _partnerHistory = {};
  final Map<String, Map<String, MoodEntry>> _partnerLiveMonth = {};
  final Map<String, StreamSubscription?> _partnerMonthSubs = {};

  Timer? _rolloverTimer;

  /// Пересобрать мой плоский список из источников (дедуп по id, live > history).
  void _rebuildMine() {
    final m = <String, MoodEntry>{}
      ..addAll(_myLegacy)
      ..addAll(_myHistory)
      ..addAll(_myLiveMonth);
    _myEntries = m.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();
  }

  /// Пересобрать список партнёра (дедуп по id, live > history > legacy).
  void _rebuildPartner(String uid) {
    final m = <String, MoodEntry>{}
      ..addAll(_partnerLegacy[uid] ?? const {})
      ..addAll(_partnerHistory[uid] ?? const {})
      ..addAll(_partnerLiveMonth[uid] ?? const {});
    _partnerEntries[uid] = m.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();
  }

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
    loadSettings();
    if (groupId == _groupId && groupId.isNotEmpty) return;
    unbindFromGroup(notify: false);
    _groupId = groupId;
    _startListening();
  }

  /// Однократно мигрировать СВОИ legacy-записи в month-доки (под prefs-флагом,
  /// идемпотентно). Партнёрские мигрировать нельзя (правила: пишем только своё).
  Future<void> _ensureMigrated(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_migratedPrefix${_groupId}_$uid';
      if (prefs.getBool(key) == true) return;
      final ok = await _fb.migrateMoodToMonthly(
        groupId: _groupId,
        uid: uid,
        since: _listenSince,
      );
      if (ok) await prefs.setBool(key, true);
    } catch (_) {}
  }

  /// Начать слушать мои записи: миграция → история (cache-first) → live текущий
  /// месяц (1 документ). Без always-on слушателя всей коллекции.
  Future<void> _startListening() async {
    _myMonthSub?.cancel();
    _myMonthSub = null;
    final uid = _fb.uid;
    if (_groupId.isEmpty || uid == null) return;
    final boundGroup = _groupId;

    // Legacy свои (cache-first, ≈0 серверных чтений) — страховка, пока миграция
    // не прошла (напр. первый запуск после апдейта в оффлайне). После миграции
    // дублируется с month-доками, дедуп по id в _rebuildMine убирает дубли.
    final myLegacy = await _fb.loadLegacyMoodEntries(
      groupId: _groupId,
      uid: uid,
      since: _listenSince,
    );
    if (_groupId != boundGroup) return;
    _myLegacy = _toById(myLegacy);
    _rebuildMine();

    await _ensureMigrated(uid);
    if (_groupId != boundGroup) return;

    final hist = await _fb.loadMoodMonths(
      groupId: _groupId,
      uid: uid,
      months: _historyMonths,
    );
    if (_groupId != boundGroup) return;
    _myHistory = _toById(hist);
    _rebuildMine();

    _myMonthSub = _fb.listenMoodMonth(
      groupId: _groupId,
      uid: uid,
      monthKey: _monthKey(DateTime.now()),
      onData: (raw) {
        _myLiveMonth = _toById(raw);
        _rebuildMine();
      },
    );
    _scheduleRollover();
  }

  /// Подписаться на записи конкретного партнёра: история (cache-first) +
  /// legacy-fallback (если партнёр ещё не мигрировал) + live текущий месяц.
  Future<void> listenToPartner(String partnerUid) async {
    if (_groupId.isEmpty) return;
    _partnerMonthSubs[partnerUid]?.cancel();
    _partnerMonthSubs[partnerUid] = null;
    final boundGroup = _groupId;

    final hist = await _fb.loadMoodMonths(
      groupId: _groupId,
      uid: partnerUid,
      months: _historyMonths,
    );
    if (_groupId != boundGroup) return;
    _partnerHistory[partnerUid] = _toById(hist);

    // Fallback: партнёр на старой версии пишет в v1 — подхватываем его историю
    // окна разово (cache-first). После миграции партнёра данные продублируются
    // в month-доках, но дедуп по id в _rebuildPartner убирает дубли.
    final legacy = await _fb.loadLegacyMoodEntries(
      groupId: _groupId,
      uid: partnerUid,
      since: _listenSince,
    );
    if (_groupId != boundGroup) return;
    _partnerLegacy[partnerUid] = _toById(legacy);
    _rebuildPartner(partnerUid);

    _partnerMonthSubs[partnerUid] = _fb.listenMoodMonth(
      groupId: _groupId,
      uid: partnerUid,
      monthKey: _monthKey(DateTime.now()),
      onData: (raw) {
        _partnerLiveMonth[partnerUid] = _toById(raw);
        _rebuildPartner(partnerUid);
      },
    );
  }

  /// В полночь 1-го числа текущий месяц «застывает» в историю, а live-подписка
  /// переезжает на новый месяц — иначе после смены месяца настроения дня
  /// перестали бы обновляться.
  void _scheduleRollover() {
    _rolloverTimer?.cancel();
    final now = DateTime.now();
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    final dur = nextMonth.difference(now) + const Duration(seconds: 5);
    _rolloverTimer = Timer(dur, () {
      if (_groupId.isEmpty) return;
      // Перенести «живой» месяц в историю и переподписаться на новый.
      _myHistory.addAll(_myLiveMonth);
      _myLiveMonth = {};
      _startListening();
      for (final p in _partnerMonthSubs.keys.toList()) {
        _partnerHistory.putIfAbsent(p, () => {}).addAll(_partnerLiveMonth[p] ?? const {});
        _partnerLiveMonth[p] = {};
        listenToPartner(p);
      }
    });
  }

  void unbindFromGroup({bool notify = true}) {
    _myMonthSub?.cancel();
    _myMonthSub = null;
    _rolloverTimer?.cancel();
    _rolloverTimer = null;
    for (final sub in _partnerMonthSubs.values) {
      sub?.cancel();
    }
    _partnerMonthSubs.clear();
    _groupId = '';
    _myEntries = [];
    _myLegacy = {};
    _myHistory = {};
    _myLiveMonth = {};
    _partnerEntries.clear();
    _partnerLegacy.clear();
    _partnerHistory.clear();
    _partnerLiveMonth.clear();
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

    // 1. В одиночном режиме удаляем все существующие записи на сегодня —
    // параллельно, чтобы listener не успел показать несогласованное состояние.
    // В мультирежиме записи дня сохраняются, новое настроение добавляется
    // отдельной записью.
    if (!_allowMultiplePerDay) {
      final existing = myEntriesForDay(today);
      await Future.wait(
        existing
            .map((e) => _fb.deleteMoodEntry(
                groupId: _groupId, entryId: e.id, timestamp: e.timestamp)),
      );
    }

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

    // Прошлая дата — только календарь. В одиночном режиме заменяем запись дня,
    // в мультирежиме добавляем ещё одну.
    if (!_allowMultiplePerDay) {
      final existing = myEntriesForDay(date);
      await Future.wait(
        existing
            .map((e) => _fb.deleteMoodEntry(
                groupId: _groupId, entryId: e.id, timestamp: e.timestamp)),
      );
    }
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
    DateTime? ts;
    for (final e in _myEntries) {
      if (e.id == entryId) {
        ts = e.timestamp;
        break;
      }
    }
    await _fb.deleteMoodEntry(
        groupId: _groupId, entryId: entryId, timestamp: ts);
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
