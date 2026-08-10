// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> timerCardStrings = {
  'timers': {
    'ru': 'Таймеры',
    'en': 'Timers',
    'pt': 'Cronômetros',
    'it': 'Timer',
    'es': 'Temporizadores',
    'fr': 'Minuteurs',
    'de': 'Timer',
  },
  'failedUploadBackground': {
    'ru': 'Не удалось загрузить фон. Проверьте подключение.',
    'en': 'Failed to upload background. Check your connection.',
    'pt': 'O fundo não subiu. Confira sua conexão.',
    'it': 'Lo sfondo non è stato caricato. Controlla la connessione.',
    'es': 'No se pudo cargar el fondo. Revisa tu conexión.',
    'fr': 'Le fond n’a pas pu être chargé. Vérifie ta connexion.',
    'de': 'Hintergrund konnte nicht geladen werden. Prüfe deine Verbindung.',
  },
};
