import 'dart:async';
import 'dart:convert';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pair_date.dart';
import '../models/phone_calendar_plan.dart';
import '../utils/calendar_day.dart';

/// Наши даты в календаре телефона (TOG-61): Google, iCloud или местный —
/// какой человек выбрал. Каждый включает у себя; партнёру это не передаётся.
///
/// События идут без напоминаний: их шлёт сервер, иначе звонило бы дважды.
/// Правка даты — замена события целиком, выброшенные дни повтора убираются
/// из серии по одному. Связь «дата → событие» лежит в prefs, а в описании
/// события стоит метка `togetherly:<id>`: после переустановки повторное
/// включение находит свои события по ней и не плодит копий.
class PhoneCalendarSync extends ChangeNotifier {
  PhoneCalendarSync._();
  static final PhoneCalendarSync instance = PhoneCalendarSync._();

  static const String _prefsKey = 'phone_calendar_v1';

  final DeviceCalendar _plugin = DeviceCalendar.instance;

  bool _loaded = false;
  bool _enabled = false;
  String _calendarId = '';
  String _calendarLabel = '';
  Map<String, String> _links = {};
  Map<String, String> _sigs = {};

  List<PairDate> _latest = const [];
  Timer? _debounce;
  Future<void>? _running;

  /// Свои даты, виденные в этом сеансе. Пустой список на холодном старте
  /// (кэш ещё не наполнился) не должен стирать календарь: пропажу даты
  /// признаём, только если список не пуст или дату только что видели.
  final Set<String> _seenIds = {};

  bool get enabled => _enabled;
  String get calendarId => _calendarId;

  /// «Google · a•••@gmail.com» — подпись под переключателем в форме.
  String get calendarLabel => _calendarLabel;

  /// Сколько дат уже лежит в календаре.
  int get count => _links.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _enabled = m['enabled'] == true;
      _calendarId = '${m['calendar'] ?? ''}';
      _calendarLabel = '${m['label'] ?? ''}';
      _links = Map<String, String>.from(m['links'] as Map? ?? const {});
      _sigs = Map<String, String>.from(m['sigs'] as Map? ?? const {});
    } catch (e) {
      debugPrint('PhoneCalendarSync: настройки не прочитались — $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _prefsKey,
        jsonEncode({
          'enabled': _enabled,
          'calendar': _calendarId,
          'label': _calendarLabel,
          'links': _links,
          'sigs': _sigs,
        }),
      );
    } catch (e) {
      debugPrint('PhoneCalendarSync: настройки не сохранились — $e');
    }
  }

  /// Даты изменились — догнать календарь телефона пачкой через пару секунд.
  void mirror(List<PairDate> dates) {
    _latest = dates;
    _seenIds.addAll([for (final d in dates) if (!d.isAuto) d.id]);
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(_run()));
  }

  /// Есть ли полный доступ к календарю, без вопроса человеку.
  Future<bool> hasAccess() async {
    try {
      return await _plugin.hasPermissions() == CalendarPermissionStatus.granted;
    } catch (_) {
      return false;
    }
  }

  /// Спросить доступ. Правке и удалению нужен полный, «только добавлять» мало.
  Future<bool> askAccess() async {
    try {
      return await _plugin.requestPermissions() == CalendarPermissionStatus.granted;
    } catch (e) {
      debugPrint('PhoneCalendarSync: доступ не спросился — $e');
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _plugin.openAppSettings();
    } catch (_) {}
  }

  /// Календари, куда можно писать: свои, не только для чтения.
  Future<List<Calendar>> writableCalendars() async {
    try {
      final all = await _plugin.listCalendars();
      final out = [for (final c in all) if (!c.readOnly) c]
        ..sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));
      return out;
    } catch (e) {
      debugPrint('PhoneCalendarSync: календари не прочитались — $e');
      return const [];
    }
  }

  /// Включить и писать в [calendar]. Свои события, оставшиеся с прошлого
  /// раза (метка в описании), подхватываются и заменяются, а не копятся.
  Future<void> enable(Calendar calendar, String label) async {
    await load();
    final moved = _enabled && _calendarId != calendar.id;
    if (moved) await _removeAll();
    _enabled = true;
    _calendarId = calendar.id;
    _calendarLabel = label;
    await _save();
    notifyListeners();
    await _adopt();
    await _run();
  }

  /// Выключить; [removeAdded] — заодно убрать уже добавленные даты.
  Future<void> disable({required bool removeAdded}) async {
    await load();
    if (removeAdded) await _removeAll();
    _enabled = false;
    if (!removeAdded) {
      // Оставленные события больше не наши: при следующем включении их
      // подхватит метка, а не связь.
      _links = {};
      _sigs = {};
    }
    await _save();
    notifyListeners();
  }

  Future<void> _run() async {
    // Один проход за раз: правки, пришедшие во время прохода, догонит следующий.
    final previous = _running;
    if (previous != null) await previous;
    final job = _sync();
    _running = job;
    try {
      await job;
    } finally {
      if (identical(_running, job)) _running = null;
    }
  }

  Future<void> _sync() async {
    await load();
    if (!_enabled || _calendarId.isEmpty || !await hasAccess()) return;
    final plan = phoneCalendarPlan(dates: _latest, links: _links, sigs: _sigs);
    final hasOwn = _latest.any((d) => !d.isAuto);
    final remove = {
      for (final e in plan.remove.entries)
        if (hasOwn || _seenIds.contains(e.key)) e.key: e.value,
    };
    if (plan.create.isEmpty && plan.replace.isEmpty && remove.isEmpty) return;

    for (final e in remove.entries) {
      await _deleteEvent(e.value);
      _links.remove(e.key);
      _sigs.remove(e.key);
    }
    for (final d in plan.replace) {
      await _deleteEvent(_links[d.id]!);
      _links.remove(d.id);
    }
    for (final d in [...plan.replace, ...plan.create]) {
      final id = await _createEvent(d);
      if (id == null) continue;
      _links[d.id] = id;
      _sigs[d.id] = phoneCalendarSig(d);
    }
    await _save();
    notifyListeners();
  }

  Future<String?> _createEvent(PairDate d) async {
    final day = d.day!;
    final start = d.startAt ?? day;
    final end = d.allDay ? calendarDay(day, 1) : start.add(const Duration(hours: 1));
    try {
      final id = await _plugin.createEvent(
        calendarId: _calendarId,
        title: d.title,
        startDate: start,
        endDate: end,
        isAllDay: d.allDay,
        description: phoneCalendarNote(d),
        timeZone: d.allDay || d.tz.isEmpty ? null : d.tz,
        recurrenceRule: d.repeats ? RecurrenceRule.fromRruleString(d.rrule) : null,
      );
      if (d.repeats && d.exdates.isNotEmpty) await _dropDays(id, d);
      return id;
    } catch (e) {
      debugPrint('PhoneCalendarSync: событие «${d.title}» не создалось — $e');
      return null;
    }
  }

  /// Выброшенные дни повтора — из серии по одному: RRULE их не выражает.
  Future<void> _dropDays(String eventId, PairDate d) async {
    for (final key in d.exdates) {
      final parts = key.split('-').map(int.parse).toList();
      final authorDay = DateTime(parts[0], parts[1], parts[2]);
      final moment = d.momentOn(authorDay);
      try {
        final around = await _plugin.listEvents(
          calendarDay(moment, -1),
          calendarDay(moment, 2),
          calendarIds: [_calendarId],
        );
        for (final ev in around) {
          final same = d.allDay
              ? calendarDay(ev.startDate, 0) == calendarDay(moment, 0)
              : ev.startDate.difference(moment).inMinutes.abs() < 1;
          if (ev.eventId == eventId && same && ev.instanceId != ev.eventId) {
            await _plugin.deleteEvent(instanceId: ev.instanceId);
          }
        }
      } catch (e) {
        debugPrint('PhoneCalendarSync: день $key не убрался — $e');
      }
    }
  }

  Future<void> _deleteEvent(String eventId) async {
    try {
      await _plugin.deleteRecurring(eventId, EventSpan.allEvents);
    } catch (_) {
      // Не серия или уже нет — пробуем как одиночное.
      try {
        await _plugin.deleteEvent(instanceId: eventId);
      } catch (_) {}
    }
  }

  Future<void> _removeAll() async {
    for (final id in _links.values) {
      await _deleteEvent(id);
    }
    _links = {};
    _sigs = {};
  }

  /// Свои события в выбранном календаре по метке в описании: одно на дату
  /// становится связью (и при проходе заменяется свежим), лишние копии уходят.
  Future<void> _adopt() async {
    if (!await hasAccess()) return;
    try {
      final now = DateTime.now();
      final events = await _plugin.listEvents(
        DateTime(now.year - 3, 1, 1),
        DateTime(now.year + 3, 12, 31),
        calendarIds: [_calendarId],
      );
      final seen = <String>{};
      for (final ev in events) {
        final dateId = dateIdFromNote(ev.description);
        if (dateId == null || !seen.add(ev.eventId)) continue;
        if (_links[dateId] == null) {
          _links[dateId] = ev.eventId;
          _sigs[dateId] = '';
        } else if (_links[dateId] != ev.eventId) {
          await _deleteEvent(ev.eventId);
        }
      }
      await _save();
    } catch (e) {
      debugPrint('PhoneCalendarSync: свои события не нашлись — $e');
    }
  }
}
