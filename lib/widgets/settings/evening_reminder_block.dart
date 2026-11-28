import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show trKey;
import '../../services/notif_prefs_sync.dart';
import '../settings_scaffold.dart';

typedef EveningReminderSave = Future<void> Function({
  required bool mood,
  required bool task,
  required int atMinutes,
  required bool custom,
});

/// Блок «Вечернее напоминание» в листе уведомлений (TOG-113): о чём
/// напоминать и во сколько. Пуш шлёт сервер (`evening_reminder_push.py`) и
/// только если что-то из выбранного за день не сделано.
class EveningReminderBlock extends StatefulWidget {
  const EveningReminderBlock({super.key, this.onSave});

  /// Куда сохранять. В приложении — prefs и профиль на сервере, в тесте свой.
  final EveningReminderSave? onSave;

  @override
  State<EveningReminderBlock> createState() => _EveningReminderBlockState();
}

class _EveningReminderBlockState extends State<EveningReminderBlock> {
  bool _mood = true;
  bool _task = true;
  int _at = remindAtMinutes(null);

  /// Человек выбрал время или включил пункт (см. [kRemindCustomPref]).
  bool _custom = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _mood = prefs.getBool(kRemindMoodPref) ?? true;
      _task = prefs.getBool(kRemindTaskPref) ?? true;
      _at = remindAtMinutes(prefs.getString(kRemindAtPref));
      _custom = prefs.getBool(kRemindCustomPref) ?? false;
    });
  }

  Future<void> _save() {
    final save = widget.onSave ?? NotifPrefsSync.saveEveningReminder;
    return save(mood: _mood, task: _task, atMinutes: _at, custom: _custom);
  }

  // Включение — знак «хочу напоминание», выключение метку не ставит: иначе
  // выключивший настроение начал бы получать задание без привычки к нему.
  void _setMood(bool v) {
    setState(() {
      _mood = v;
      _custom = _custom || v;
    });
    _save();
  }

  void _setTask(bool v) {
    setState(() {
      _task = v;
      _custom = _custom || v;
    });
    _save();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _at ~/ 60, minute: _at % 60),
      helpText: trKey('er.title'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _at = picked.hour * 60 + picked.minute;
      _custom = true;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anyOn = _mood || _task;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: _at ~/ 60, minute: _at % 60),
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
            trailing: Switch(value: _mood, onChanged: _setMood),
            onTap: () => _setMood(!_mood),
          ),
          SettingsRow(
            key: const ValueKey('er-task'),
            icon: Icons.task_alt_rounded,
            title: trKey('er.task'),
            subtitle: trKey('er.taskSub'),
            trailing: Switch(value: _task, onChanged: _setTask),
            onTap: () => _setTask(!_task),
          ),
          // Оба выключены — время ни к чему, строка гаснет и не нажимается.
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
              onTap: anyOn ? _pickTime : null,
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
