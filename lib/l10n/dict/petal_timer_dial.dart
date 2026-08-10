// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> petalTimerDialStrings = {
  'yearsLabel': {
    'ru': 'Лет',
    'en': 'Years',
    'pt': 'Anos',
    'it': 'Anni',
    'es': 'Años',
    'fr': 'Ans',
    'de': 'Jahre',
  },
  'monthsShortLabel': {
    'ru': 'Мес',
    'en': 'Months',
    'pt': 'Mês',
    'it': 'Mesi',
    'es': 'Mes',
    'fr': 'Mois',
    'de': 'Mon',
  },
  'daysShortLabel': {
    'ru': 'Дней',
    'en': 'Days',
    'pt': 'Dias',
    'it': 'Giorni',
    'es': 'Días',
    'fr': 'Jours',
    'de': 'Tage',
  },
  'hoursLabel': {
    'ru': 'Час',
    'en': 'Hours',
    'pt': 'H',
    'it': 'Ore',
    'es': 'H',
    'fr': 'H',
    'de': 'Std',
  },
  'minLabel': {
    'ru': 'Мин',
    'en': 'Min',
    'pt': 'Min',
    'it': 'Min',
    'es': 'Min',
    'fr': 'Min',
    'de': 'Min',
  },
  'secLabel': {
    'ru': 'Сек',
    'en': 'Sec',
    'pt': 'Seg',
    'it': 'Sec',
    'es': 'Seg',
    'fr': 'Sec',
    'de': 'Sek',
  },
};
