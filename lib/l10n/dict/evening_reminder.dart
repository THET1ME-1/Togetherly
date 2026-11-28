// Вечернее напоминание (TOG-113, 28.11.2026): блок в листе уведомлений —
// два выключателя, время и подсказка. Украинский и китайский — в
// `../uk/evening_reminder.dart` и `../zh/evening_reminder.dart`. Полноту
// сверяет test/l10n/evening_reminder_strings_test.dart.

const Map<String, Map<String, String>> eveningReminderStrings = {
  'er.title': {'ru': 'Вечернее напоминание', 'en': 'Evening reminder', 'pt': 'Lembrete da noite', 'it': 'Promemoria serale', 'es': 'Recordatorio de la noche', 'fr': 'Rappel du soir', 'de': 'Abenderinnerung'},
  'er.mood': {'ru': 'Настроение', 'en': 'Mood', 'pt': 'Humor', 'it': 'Umore', 'es': 'Ánimo', 'fr': 'Humeur', 'de': 'Stimmung'},
  'er.moodSub': {'ru': 'Если за день не отмечено', 'en': 'If you haven’t logged it today', 'pt': 'Se não marcou hoje', 'it': 'Se oggi non l’hai segnato', 'es': 'Si hoy no lo has marcado', 'fr': 'Si tu ne l’as pas notée aujourd’hui', 'de': 'Wenn du sie heute nicht eingetragen hast'},
  'er.task': {'ru': 'Задание дня', 'en': 'Today’s task', 'pt': 'Tarefa do dia', 'it': 'Sfida del giorno', 'es': 'Tarea del día', 'fr': 'Mission du jour', 'de': 'Aufgabe des Tages'},
  'er.taskSub': {'ru': 'Если вы его ещё не выполнили', 'en': 'If you haven’t done it yet', 'pt': 'Se vocês ainda não fizeram', 'it': 'Se non l’avete ancora fatta', 'es': 'Si aún no la habéis hecho', 'fr': 'Si vous ne l’avez pas encore faite', 'de': 'Wenn ihr sie noch nicht erledigt habt'},
  'er.time': {'ru': 'Время', 'en': 'Time', 'pt': 'Horário', 'it': 'Ora', 'es': 'Hora', 'fr': 'Heure', 'de': 'Uhrzeit'},
  'er.hint': {'ru': 'Придёт, только если что-то из этого ещё не сделано.', 'en': 'It only comes if something here is still left to do.', 'pt': 'Só chega se algo daqui ainda não foi feito.', 'it': 'Arriva solo se qualcosa qui non è ancora fatto.', 'es': 'Solo llega si algo de esto aún está pendiente.', 'fr': 'Il n’arrive que s’il reste quelque chose à faire.', 'de': 'Sie kommt nur, wenn hier noch etwas offen ist.'},
};
