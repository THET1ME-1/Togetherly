// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> miniMoodCalendarStrings = {
  'todayLabel': {
    'ru': 'Сегодня',
    'en': 'Today',
    'pt': 'Hoje',
    'it': 'Oggi',
    'es': 'Hoy',
    'fr': 'Aujourd’hui',
    'de': 'Heute',
  },
  // ── Год клетками ─────────────────────────────────────────────────────────
  'moodYearNoMark': {
    'ru': 'дня нет в отметках',
    'en': 'no entry that day',
    'pt': 'sem registo nesse dia',
    'it': 'nessun segno quel giorno',
    'es': 'sin registro ese día',
    'fr': 'pas de note ce jour-là',
    'de': 'kein Eintrag an dem Tag',
  },
  'moodYearWorse': {
    'ru': 'хуже',
    'en': 'worse',
    'pt': 'pior',
    'it': 'peggio',
    'es': 'peor',
    'fr': 'moins bien',
    'de': 'schlechter',
  },
  'moodYearBetter': {
    'ru': 'лучше',
    'en': 'better',
    'pt': 'melhor',
    'it': 'meglio',
    'es': 'mejor',
    'fr': 'mieux',
    'de': 'besser',
  },
  'moodYearAverage': {
    'ru': 'в среднем {avg} из 5',
    'en': '{avg} out of 5 on average',
    'pt': 'em média {avg} de 5',
    'it': 'in media {avg} su 5',
    'es': 'en promedio {avg} de 5',
    'fr': '{avg} sur 5 en moyenne',
    'de': 'im Schnitt {avg} von 5',
  },
  'moodYearMissing': {
    'ru': '{days} без отметки',
    'en': '{days} with no entry',
    'pt': '{days} sem registo',
    'it': '{days} senza segno',
    'es': '{days} sin registro',
    'fr': '{days} sans note',
    'de': '{days} ohne Eintrag',
  },
  'moodYearEmpty': {
    'ru': 'За этот год отметок пока нет',
    'en': 'No entries this year yet',
    'pt': 'Ainda sem registos este ano',
    'it': 'Ancora nessun segno quest’anno',
    'es': 'Aún no hay registros este año',
    'fr': 'Pas encore de notes cette année',
    'de': 'Dieses Jahr noch keine Einträge',
  },
};
