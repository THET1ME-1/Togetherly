// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> timerExpandableTimerCardStrings = {
  'noTimers': {
    'ru': 'Нет таймеров',
    'en': 'No timers',
    'pt': 'Sem cronômetros',
    'it': 'Nessun timer',
    'es': 'Sin temporizadores',
    'fr': 'Aucun minuteur',
    'de': 'Keine Timer',
  },
  'createTimer': {
    'ru': 'Создать таймер',
    'en': 'Create Timer',
    'pt': 'Criar um cronômetro',
    'it': 'Crea un timer',
    'es': 'Crear un temporizador',
    'fr': 'Créer un minuteur',
    'de': 'Timer erstellen',
  },
  'editTimer': {
    'ru': 'Редактировать таймер',
    'en': 'Edit Timer',
    'pt': 'Editar o cronômetro',
    'it': 'Modifica il timer',
    'es': 'Editar el temporizador',
    'fr': 'Modifier le minuteur',
    'de': 'Timer bearbeiten',
  },
  'timerNameLabel': {
    'ru': 'НАЗВАНИЕ',
    'en': 'NAME',
    'pt': 'NOME',
    'it': 'NOME',
    'es': 'NOMBRE',
    'fr': 'NOM',
    'de': 'NAME',
  },
  'egAnniversary': {
    'ru': 'Напр. Годовщина',
    'en': 'E.g. Anniversary',
    'pt': 'Ex. Aniversário',
    'it': 'Es. Anniversario',
    'es': 'Ej. Aniversario',
    'fr': 'Ex. Anniversaire',
    'de': 'Z. B. Jubiläum',
  },
  'targetDate': {
    'ru': 'ЦЕЛЕВАЯ ДАТА',
    'en': 'TARGET DATE',
    'pt': 'DATA ALVO',
    'it': 'DATA OBIETTIVO',
    'es': 'FECHA OBJETIVO',
    'fr': 'DATE CIBLE',
    'de': 'ZIELDATUM',
  },
  'startDate': {
    'ru': 'ДАТА НАЧАЛА',
    'en': 'START DATE',
    'pt': 'DATA DE INÍCIO',
    'it': 'DATA D’INIZIO',
    'es': 'FECHA DE INICIO',
    'fr': 'DATE DE DÉBUT',
    'de': 'STARTDATUM',
  },
  'dateFormatHint': {
    'ru': 'дд.мм.гггг',
    'en': 'dd.mm.yyyy',
    'pt': 'dd.mm.aaaa',
    'it': 'gg.mm.aaaa',
    'es': 'dd.mm.aaaa',
    'fr': 'jj.mm.aaaa',
    'de': 'tt.mm.jjjj',
  },
  'symbolLabel': {
    'ru': 'СИМВОЛ',
    'en': 'SYMBOL',
    'pt': 'SÍMBOLO',
    'it': 'SIMBOLO',
    'es': 'SÍMBOLO',
    'fr': 'SYMBOLE',
    'de': 'SYMBOL',
  },
  'countdownMode': {
    'ru': 'Режим отсчёта',
    'en': 'Countdown Mode',
    'pt': 'Contagem regressiva',
    'it': 'Conto alla rovescia',
    'es': 'Cuenta atrás',
    'fr': 'Décompte',
    'de': 'Countdown',
  },
  'countdownPastDateWarning': {
    'ru':
        'Целевая дата уже прошла — таймер покажет нули. Выберите будущую дату.',
    'en':
        'Target date has already passed — the timer will show zeros. Please pick a future date.',
    'pt':
        'A data alvo já passou — o cronômetro vai mostrar zeros. Escolha uma data futura.',
    'it':
        'La data obiettivo è già passata — il timer mostrerà zeri. Scegli una data futura.',
    'es':
        'La fecha objetivo ya pasó — el temporizador mostrará ceros. Elige una fecha futura.',
    'fr':
        'La date cible est déjà passée — le minuteur affichera des zéros. Choisis une date future.',
    'de':
        'Das Zieldatum liegt in der Vergangenheit — der Timer zeigt Nullen. Wähle ein Datum in der Zukunft.',
  },
  'setAsMain': {
    'ru': 'Сделать основным',
    'en': 'Set as Main',
    'pt': 'Como principal',
    'it': 'Come principale',
    'es': 'Como principal',
    'fr': 'Comme minuteur principal',
    'de': 'Als Haupttimer',
  },
  'saveSettings': {
    'ru': 'СОХРАНИТЬ',
    'en': 'SAVE SETTINGS',
    'pt': 'SALVAR',
    'it': 'SALVA',
    'es': 'GUARDAR',
    'fr': 'ENREGISTRER',
    'de': 'SPEICHERN',
  },
  'deleteTimerQuestion': {
    'ru': 'Удалить таймер?',
    'en': 'Delete Timer?',
    'pt': 'Excluir o cronômetro?',
    'it': 'Eliminare il timer?',
    'es': '¿Borrar el temporizador?',
    'fr': 'Supprimer le minuteur ?',
    'de': 'Timer löschen?',
  },
};
