// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> dateHelpersStrings = {
  'todayDate': {
    'ru': 'Сегодня',
    'en': 'Today',
    'pt': 'Hoje',
    'it': 'Oggi',
    'es': 'Hoy',
    'fr': 'Aujourd’hui',
    'de': 'Heute',
  },
  'yesterday': {
    'ru': 'Вчера',
    'en': 'Yesterday',
    'pt': 'Ontem',
    'it': 'Ieri',
    'es': 'Ayer',
    'fr': 'Hier',
    'de': 'Gestern',
  },
};
