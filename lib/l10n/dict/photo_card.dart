// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> photoCardStrings = {
  'sharedAPicture': {
    'ru': 'Поделился фото',
    'en': 'Shared a picture',
    'pt': 'Compartilhou uma foto',
    'it': 'Ha condiviso una foto',
    'es': 'Ha compartido una foto',
    'fr': 'A partagé une photo',
    'de': 'Hat ein Foto geteilt',
  },
  'openInMaps': {
    'ru': 'Открыть в картах',
    'en': 'Open in maps',
    'pt': 'Abrir no Mapas',
    'it': 'Apri in Mappe',
    'es': 'Abrir en Mapas',
    'fr': 'Ouvrir dans Cartes',
    'de': 'In Karten öffnen',
  },
  'justNow': {
    'ru': 'только что',
    'en': 'just now',
    'pt': 'agora mesmo',
    'it': 'proprio ora',
    'es': 'ahora mismo',
    'fr': 'à l’instant',
    'de': 'gerade eben',
  },
};
