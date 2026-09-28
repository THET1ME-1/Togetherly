// Карточка «Задания дня» на главной. Строки жили в самой карточке парами
// ru/en, и пять языков из семи видели английский (переезд 28.09.2026, вместе с
// бонусным заданием).
//
// Тексты самих заданий по-прежнему лежат в каталоге `models/daily_task.dart`.

const Map<String, Map<String, String>> dailyTasksStrings = {
  'tasks_title': {
    'ru': 'Задания дня',
    'en': 'Today’s tasks',
    'de': 'Tagesaufgaben',
    'fr': 'Défis du jour',
    'es': 'Retos del día',
    'it': 'Sfide del giorno',
    'pt': 'Desafios do dia',
  },
  'tasks_tap_hint': {
    'ru': 'Нажмите на задание, и откроется то, что для него нужно',
    'en': 'Tap a task to open what it needs',
    'de': 'Tippe auf eine Aufgabe, um sie zu öffnen',
    'fr': 'Touche un défi pour l’ouvrir',
    'es': 'Toca un reto para abrirlo',
    'it': 'Tocca una sfida per aprirla',
    'pt': 'Toque num desafio para abri-lo',
  },
  'tasks_add_hint': {
    'ru': 'Добавьте пин в ленту, и задание закроется само',
    'en': 'Add a pin to the feed and the task closes itself',
    'de': 'Füge eine Erinnerung hinzu, dann ist die Aufgabe erledigt',
    'fr': 'Ajoute un souvenir et le défi se valide tout seul',
    'es': 'Añade un recuerdo y el reto se completa solo',
    'it': 'Aggiungi un ricordo e la sfida si completa da sola',
    'pt': 'Adicione uma lembrança e o desafio se conclui sozinho',
  },
  // Все три основных закрыты, открылось бонусное.
  'tasks_bonus_hint': {
    'ru': 'Все три готовы. Вот бонусное, без монеты',
    'en': 'All three done. Here’s a bonus one, no coin',
    'de': 'Alle drei erledigt. Hier ist eine Bonusaufgabe, ohne Münze',
    'fr': 'Les trois sont faits. Voici un bonus, sans pièce',
    'es': 'Los tres listos. Aquí va uno extra, sin moneda',
    'it': 'Tutte e tre fatte. Ecco un bonus, senza moneta',
    'pt': 'Os três feitos. Aqui vai um bônus, sem moeda',
  },
  'tasks_all_done': {
    'ru': 'На сегодня всё, до завтра',
    'en': 'All done for today, see you tomorrow',
    'de': 'Für heute alles erledigt, bis morgen',
    'fr': 'Tout est fait pour aujourd’hui, à demain',
    'es': 'Todo listo por hoy, hasta mañana',
    'it': 'Tutto fatto per oggi, a domani',
    'pt': 'Tudo feito por hoje, até amanhã',
  },
  // Ярлык на строке бонусного задания.
  'tasks_bonus_label': {
    'ru': 'Бонус',
    'en': 'Bonus',
    'de': 'Bonus',
    'fr': 'Bonus',
    'es': 'Extra',
    'it': 'Bonus',
    'pt': 'Bônus',
  },
};
