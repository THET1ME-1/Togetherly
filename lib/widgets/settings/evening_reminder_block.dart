import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show trKey;
import '../../services/notif_prefs_sync.dart';
import '../../services/pb_data_service.dart';
import '../../services/pocketbase_service.dart';
import '../settings_scaffold.dart';

/// Записать выбор: null — пункт не трогать. Уходит на сервер вместе со всем,
/// что выбрано к этому моменту ([NotifPrefsSync.saveEveningReminder]).
typedef EveningReminderSave = Future<void> Function({
  String? mood,
  String? task,
  String? at,
});

/// Свой профиль с сервера (`remindMood`, `remindTask`, `remindAt`); null —
/// сервер не ответил.
typedef EveningReminderServer = Future<Map<String, dynamic>?> Function();

/// Блок «Вечернее напоминание» в листе уведомлений (TOG-113): о чём
/// напоминать и во сколько. Пуш шлёт сервер (`evening_reminder_push.py`) и
/// только если что-то из выбранного за день не сделано.
///
/// Оба пункта по умолчанию включены (решение владельца 28.11.2026). Пишет на
/// сервер только нажатие человека; выбор сверяется с профилем при каждом
/// открытии (`reconcileEveningReminder`): побеждает сделанный позже, на любом
/// телефоне.
class EveningReminderBlock extends StatefulWidget {
  const EveningReminderBlock({
    super.key,
    required this.paired,
    this.onSave,
    this.loadServer,
    this.uid,
  });

  /// Без пары задания нет — строки задания тоже.
  final bool paired;

  final EveningReminderSave? onSave;
  final EveningReminderServer? loadServer;

  /// Чей выбор сверяем; по умолчанию — вошедший.
  final String? uid;

  @override
  State<EveningReminderBlock> createState() => _EveningReminderBlockState();
}

class _EveningReminderBlockState extends State<EveningReminderBlock> {
  /// `on`/`off` — выбор человека; null — ещё не решено.
  String? _mood;
  String? _task;

  /// `ЧЧ:ММ`, выбранное человеком; null — 21:00 по умолчанию.
  String? _at;

  /// Пока prefs не прочитаны, выключатели не нажимаются: сохранение ушло бы
  /// с умолчаниями. Сервер не ждём — без сети это секунды на каждом открытии.
  bool _loaded = false;

  /// Человек уже нажимал: поздний ответ сервера его выбор не перетирает.
  bool _touched = false;

  /// Сохранения по очереди: при быстрых нажатиях запросы иначе приходят на
  /// сервер в любом порядке, и там остаётся не последнее.
  Future<void> _chain = Future.value();

  // Не трогал — включено, как и на сервере.
  bool get _moodOn => _mood != 'off';
  bool get _taskOn => _task != 'off';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _readPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _mood = remindModeOf(prefs.getString(kRemindMoodPref));
    _task = remindModeOf(prefs.getString(kRemindTaskPref));
    _at = remindAtValid(prefs.getString(kRemindAtPref));
  }

  Future<void> _load() async {
    await _readPrefs();
    if (!mounted) return;
    // Показ ничего не пишет: не тронутое человеком сервер и так считает
    // включённым, а лишняя запись затёрла бы выбор с другого телефона.
    setState(() => _loaded = true);

    // Свериться с профилем: выбор мог быть сделан на другом телефоне.
    Map<String, dynamic>? server;
    try {
      server = await (widget.loadServer ?? _ownProfile)()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      server = null;
    }
    if (server == null || !mounted || _touched) return;
    await reconcileEveningReminder(server,
        uid: widget.uid ?? PocketBaseService().userId ?? '');
    if (!mounted || _touched) return;
    await _readPrefs();
    if (mounted) setState(() {});
  }

  static Future<Map<String, dynamic>?> _ownProfile() async {
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return null;
    return PbDataService().loadUserProfileMap(uid);
  }

  void _queueSave() {
    _touched = true;
    // Каждое сохранение читает состояние в момент отправки: последнее в
    // очереди уносит итог, сколько бы нажатий ни было.
    _chain = _chain.then((_) {
      final save = widget.onSave ?? NotifPrefsSync.saveEveningReminder;
      return save(mood: _mood, task: _task, at: _at);
    }).catchError((Object _) {});
  }

  void _setMood(bool v) {
    setState(() => _mood = v ? 'on' : 'off');
    _queueSave();
  }

  void _setTask(bool v) {
    setState(() => _task = v ? 'on' : 'off');
    _queueSave();
  }

  Future<void> _pickTime() async {
    final minutes = remindAtMinutes(_at);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: trKey('er.title'),
    );
    if (picked == null || !mounted) return;
    setState(() => _at = remindAtOf(picked.hour * 60 + picked.minute));
    _queueSave();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anyOn = _moodOn || (widget.paired && _taskOn);
    final minutes = remindAtMinutes(_at);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(trKey('er.title'), icon: Icons.nights_stay_rounded),
        SettingsGroup([
          SettingsRow(
            key: const ValueKey('er-mood'),
            icon: Icons.emoji_emotions_rounded,
            title: trKey('er.mood'),
            subtitle: trKey('er.moodSub'),
            trailing: Switch(value: _moodOn, onChanged: _loaded ? _setMood : null),
            onTap: _loaded ? () => _setMood(!_moodOn) : null,
          ),
          if (widget.paired)
            SettingsRow(
              key: const ValueKey('er-task'),
              icon: Icons.task_alt_rounded,
              title: trKey('er.task'),
              subtitle: trKey('er.taskSub'),
              trailing: Switch(value: _taskOn, onChanged: _loaded ? _setTask : null),
              onTap: _loaded ? () => _setTask(!_taskOn) : null,
            ),
          // Выключено всё — время ни к чему, строка гаснет и не нажимается.
          Opacity(
            opacity: anyOn ? 1 : 0.45,
            child: SettingsRow(
              key: const ValueKey('er-time'),
              icon: Icons.schedule_rounded,
              title: trKey('er.time'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const SettingsChevron(),
                ],
              ),
              onTap: _loaded && anyOn ? _pickTime : null,
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Text(
            trKey('er.hint'),
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
