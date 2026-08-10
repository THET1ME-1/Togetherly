// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> mapPickerScreenStrings = {
  'selectLocationOnMap': {
    'ru': 'Выберите место на карте',
    'en': 'Select a location on the map',
    'pt': 'Escolha um lugar no mapa',
    'it': 'Scegli un luogo sulla mappa',
    'es': 'Elige un lugar en el mapa',
    'fr': 'Choisis un lieu sur la carte',
    'de': 'Wähle einen Ort auf der Karte',
  },
  'selectedLocation': {
    'ru': 'Выбранная локация',
    'en': 'Selected location',
    'pt': 'Lugar escolhido',
    'it': 'Luogo scelto',
    'es': 'Lugar elegido',
    'fr': 'Lieu choisi',
    'de': 'Gewählter Ort',
  },
  'selectLocation': {
    'ru': 'Выбрать место',
    'en': 'Select Location',
    'pt': 'Escolher lugar',
    'it': 'Scegli il luogo',
    'es': 'Elegir lugar',
    'fr': 'Choisir un lieu',
    'de': 'Ort wählen',
  },
  'confirm': {
    'ru': 'Подтвердить',
    'en': 'Confirm',
    'pt': 'Confirmar',
    'it': 'Conferma',
    'es': 'Confirmar',
    'fr': 'Confirmer',
    'de': 'Bestätigen',
  },
  'gettingAddress': {
    'ru': 'Определяем адрес...',
    'en': 'Getting address...',
    'pt': 'Procurando o endereço...',
    'it': 'Cerco l’indirizzo...',
    'es': 'Buscando la dirección...',
    'fr': 'Recherche de l’adresse...',
    'de': 'Adresse wird ermittelt...',
  },
  'tapOnMapToSelect': {
    'ru': 'Нажмите на карту, чтобы выбрать другое место',
    'en': 'Tap on the map to select a different location',
    'pt': 'Toque no mapa para escolher outro lugar',
    'it': 'Tocca la mappa per scegliere un altro luogo',
    'es': 'Toca el mapa para elegir otro lugar',
    'fr': 'Touche la carte pour choisir un autre lieu',
    'de': 'Tippe auf die Karte, um einen anderen Ort zu wählen',
  },
  'failedGetCurrentLocation': {
    'ru': 'Не удалось определить текущее местоположение',
    'en': 'Failed to get current location',
    'pt': 'Não foi possível descobrir a localização atual',
    'it': 'Non è stato possibile determinare la posizione attuale',
    'es': 'No se pudo determinar la ubicación actual',
    'fr': 'Impossible de déterminer la position actuelle',
    'de': 'Der aktuelle Standort konnte nicht ermittelt werden',
  },
};
