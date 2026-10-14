// Наклейки на пинах ленты: пункт меню долгого нажатия, лист наборов,
// наклеивание прямо на карточке, касание по наклейке.
//
// Наклейки берутся из наборов настроений, поэтому слово «наклейка» в
// романских языках местное (autocollant, pegatina, adesivo), а не sticker.

const Map<String, Map<String, String>> stickersStrings = {
  'stickerAdd': {
    'ru': 'Наклеить наклейку',
    'en': 'Add a sticker',
    'de': 'Sticker aufkleben',
    'fr': 'Coller un autocollant',
    'es': 'Pegar una pegatina',
    'it': 'Attacca un adesivo',
    'pt': 'Colar um adesivo',
  },
  'stickersTitle': {
    'ru': 'Наклейки',
    'en': 'Stickers',
    'de': 'Sticker',
    'fr': 'Autocollants',
    'es': 'Pegatinas',
    'it': 'Adesivi',
    'pt': 'Adesivos',
  },
  // Подсказка над кнопками, пока наклейку ставят на место.
  'stickerHint': {
    'ru': 'Двигай пальцем, крути двумя',
    'en': 'Drag with one finger, twist with two',
    'de': 'Mit einem Finger ziehen, mit zwei drehen',
    'fr': 'Glisse avec un doigt, tourne avec deux',
    'es': 'Arrastra con un dedo, gira con dos',
    'it': 'Trascina con un dito, ruota con due',
    'pt': 'Arraste com um dedo, gire com dois',
  },
  // Касание по чужой наклейке: кто её поставил.
  'stickerFrom': {
    'ru': 'Наклейка от {name}',
    'en': 'Sticker from {name}',
    'de': 'Sticker von {name}',
    'fr': 'Autocollant de {name}',
    'es': 'Pegatina de {name}',
    'it': 'Adesivo di {name}',
    'pt': 'Adesivo de {name}',
  },
  'stickerMine': {
    'ru': 'Твоя наклейка',
    'en': 'Your sticker',
    'de': 'Dein Sticker',
    'fr': 'Ton autocollant',
    'es': 'Tu pegatina',
    'it': 'Il tuo adesivo',
    'pt': 'Seu adesivo',
  },
  'stickerMove': {
    'ru': 'Переставить',
    'en': 'Move',
    'de': 'Verschieben',
    'fr': 'Déplacer',
    'es': 'Mover',
    'it': 'Sposta',
    'pt': 'Mover',
  },
  'stickerRemove': {
    'ru': 'Убрать',
    'en': 'Remove',
    'de': 'Entfernen',
    'fr': 'Retirer',
    'es': 'Quitar',
    'it': 'Rimuovi',
    'pt': 'Remover',
  },
  'stickerLimit': {
    'ru': 'Своих наклеек на одной записи не больше трёх',
    'en': 'You can put up to three stickers on one memory',
    'de': 'Auf eine Erinnerung passen bis zu drei eigene Sticker',
    'fr': 'Trois autocollants à toi au plus par souvenir',
    'es': 'Hasta tres pegatinas tuyas por recuerdo',
    'it': 'Al massimo tre adesivi tuoi per ricordo',
    'pt': 'Até três adesivos seus por lembrança',
  },
};
