// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> homeScreenStrings = {
  'startWithBlankCanvas': {
    'ru': 'Начать с чистого холста',
    'en': 'Start with a blank canvas',
    'pt': 'Começar com uma tela em branco',
    'it': 'Parti da una tela vuota',
    'es': 'Empezar con un lienzo en blanco',
    'fr': 'Partir d’une toile vierge',
    'de': 'Mit leerer Leinwand beginnen',
  },
  'openSavedDrawing': {
    'ru': 'Открыть сохранённый рисунок',
    'en': 'Open a saved drawing',
    'pt': 'Abrir um desenho salvo',
    'it': 'Apri un disegno salvato',
    'es': 'Abrir un dibujo guardado',
    'fr': 'Ouvrir un dessin enregistré',
    'de': 'Gespeicherte Zeichnung öffnen',
  },
  'newPhoto': {
    'ru': 'Новое фото',
    'en': 'New Photo',
    'pt': 'Foto nova',
    'it': 'Foto nuova',
    'es': 'Foto nueva',
    'fr': 'Nouvelle photo',
    'de': 'Neues Foto',
  },
  'titleHint': {
    'ru': 'Заголовок…',
    'en': 'Title…',
    'pt': 'Título…',
    'it': 'Titolo…',
    'es': 'Título…',
    'fr': 'Titre…',
    'de': 'Titel…',
  },
  'descriptionOptionalHint': {
    'ru': 'Описание (необязательно)…',
    'en': 'Description (optional)…',
    'pt': 'Descrição (opcional)…',
    'it': 'Descrizione (facoltativa)…',
    'es': 'Descripción (opcional)…',
    'fr': 'Description (facultatif)…',
    'de': 'Beschreibung (optional)…',
  },
  'setAsWidgetPhoto': {
    'ru': 'Фото дня на виджете',
    'en': 'Set as widget photo',
    'pt': 'Foto do dia no widget',
    'it': 'Foto del giorno nel widget',
    'es': 'Foto del día en el widget',
    'fr': 'Photo du jour sur le widget',
    'de': 'Foto des Tages im Widget',
  },
};
