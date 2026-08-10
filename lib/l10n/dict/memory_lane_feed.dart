// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> memoryLaneFeedStrings = {
  'sharedAVideo': {
    'ru': 'Поделился видео',
    'en': 'Shared a video',
    'pt': 'Compartilhou um vídeo',
    'it': 'Ha condiviso un video',
    'es': 'Ha compartido un vídeo',
    'fr': 'A partagé une vidéo',
    'de': 'Hat ein Video geteilt',
  },
  'sharedAVideoLink': {
    'ru': 'Поделился видео по ссылке',
    'en': 'Shared a video link',
    'pt': 'Compartilhou um link de vídeo',
    'it': 'Ha condiviso un link video',
    'es': 'Ha compartido un enlace de vídeo',
    'fr': 'A partagé un lien vidéo',
    'de': 'Hat einen Video-Link geteilt',
  },
  'sharedAThought': {
    'ru': 'Поделился мыслями',
    'en': 'Shared a thought',
    'pt': 'Compartilhou um pensamento',
    'it': 'Ha condiviso un pensiero',
    'es': 'Ha compartido un pensamiento',
    'fr': 'A partagé une pensée',
    'de': 'Hat einen Gedanken geteilt',
  },
  'sharedALocation': {
    'ru': 'Отметил локацию',
    'en': 'Checked in',
    'pt': 'Marcou um lugar',
    'it': 'Ha segnato un luogo',
    'es': 'Ha marcado un lugar',
    'fr': 'A marqué un lieu',
    'de': 'Hat einen Ort markiert',
  },
  'sharedMusic': {
    'ru': 'Поделился музыкой',
    'en': 'Shared music',
    'pt': 'Compartilhou música',
    'it': 'Ha condiviso musica',
    'es': 'Ha compartido música',
    'fr': 'A partagé de la musique',
    'de': 'Hat Musik geteilt',
  },
  'vibesTo': {
    'ru': 'Вайбит под',
    'en': 'Vibes to',
    'pt': 'Vibra com',
    'it': 'Vibra con',
    'es': 'Vibra con',
    'fr': 'Vibre sur',
    'de': 'Vibet zu',
  },
  'setARoute': {
    'ru': 'Маршрут',
    'en': 'Set a route',
    'pt': 'Rota',
    'it': 'Percorso',
    'es': 'Ruta',
    'fr': 'Itinéraire',
    'de': 'Route',
  },
  'isListening': {
    'ru': 'слушает',
    'en': 'is listening',
    'pt': 'está ouvindo',
    'it': 'sta ascoltando',
    'es': 'está escuchando',
    'fr': 'écoute',
    'de': 'hört gerade',
  },
  'playTrack': {
    'ru': 'Включить',
    'en': 'Play',
    'pt': 'Ouvir',
    'it': 'Ascolta',
    'es': 'Escuchar',
    'fr': 'Écouter',
    'de': 'Abspielen',
  },
  'note': {
    'ru': 'Заметка',
    'en': 'Note',
    'pt': 'Nota',
    'it': 'Nota',
    'es': 'Nota',
    'fr': 'Note',
    'de': 'Notiz',
  },
};
