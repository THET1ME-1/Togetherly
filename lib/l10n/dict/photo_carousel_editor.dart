// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> photoCarouselEditorStrings = {
  'addOneToTenPhotos': {
    'ru': 'Добавьте от 1 до 10 фото',
    'en': 'Add 1 to 10 photos',
    'pt': 'Adicione de 1 a 10 fotos',
    'it': 'Aggiungi da 1 a 10 foto',
    'es': 'Añade de 1 a 10 fotos',
    'fr': 'Ajoute de 1 à 10 photos',
    'de': 'Füge 1 bis 10 Fotos hinzu',
  },
  'addMorePhotosCarouselHint': {
    'ru':
        'Добавьте ещё фото, чтобы появилась карусель — фото будут меняться автоматически.',
    'en':
        'Add more photos to enable the carousel — photos will rotate automatically.',
    'pt':
        'Adicione mais fotos para o carrossel começar — elas vão trocar sozinhas.',
    'it':
        'Aggiungi altre foto per far partire il carosello — cambieranno da sole.',
    'es':
        'Añade más fotos para que arranque el carrusel — irán cambiando solas.',
    'fr':
        'Ajoute d’autres photos pour lancer le carrousel — elles défileront toutes seules.',
    'de':
        'Füge weitere Fotos hinzu, damit das Karussell startet — die Fotos wechseln dann automatisch.',
  },
  'dragToReorder': {
    'ru': 'Удерживайте и перетаскивайте, чтобы изменить порядок',
    'en': 'Hold and drag to reorder',
    'pt': 'Segure e arraste para reordenar',
    'it': 'Tieni premuto e trascina per riordinare',
    'es': 'Mantén y arrastra para reordenar',
    'fr': 'Maintiens et fais glisser pour réorganiser',
    'de': 'Halten und ziehen, um die Reihenfolge zu ändern',
  },
  'mainPhoto': {
    'ru': 'Главное',
    'en': 'Main',
    'pt': 'Principal',
    'it': 'Principale',
    'es': 'Principal',
    'fr': 'Principale',
    'de': 'Titelbild',
  },
  'addMore': {
    'ru': 'Добавить ещё',
    'en': 'Add more',
    'pt': 'Adicionar mais',
    'it': 'Aggiungi altre',
    'es': 'Añadir más',
    'fr': 'Ajouter encore',
    'de': 'Weitere hinzufügen',
  },
  'fromDevice': {
    'ru': 'С устройства',
    'en': 'From device',
    'pt': 'Do aparelho',
    'it': 'Dal dispositivo',
    'es': 'Del dispositivo',
    'fr': 'Depuis l’appareil',
    'de': 'Vom Gerät',
  },
  'fromFeed': {
    'ru': 'Из ленты',
    'en': 'From feed',
    'pt': 'Do mural',
    'it': 'Dal diario',
    'es': 'Del muro',
    'fr': 'Depuis le fil',
    'de': 'Aus dem Erinnerungspfad',
  },
};
