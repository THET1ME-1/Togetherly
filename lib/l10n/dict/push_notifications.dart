// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.
//
// Уведомление собирает телефон получателя — значит и язык берётся его. До
// 23.08.2026 эти строки были зашиты по-русски, и англоязычный человек с
// английским интерфейсом читал в шторке русский текст (вопрос @kingchim:
// «how do i change notification to English?»).

const Map<String, Map<String, String>> pushNotificationsStrings = {
  'pushChannelName': {
    'ru': 'Уведомления от партнёра',
    'en': 'Partner notifications',
    'pt': 'Notificações do par',
    'it': 'Notifiche dal partner',
    'es': 'Notificaciones de tu pareja',
    'fr': 'Notifications du partenaire',
    'de': 'Benachrichtigungen vom Partner',
  },
  'pushChannelDescription': {
    'ru': 'Сообщения, настроение и «скучаю» от партнёра',
    'en': 'Messages, mood and “miss you” from your partner',
    'pt': 'Mensagens, humor e «sinto sua falta» do par',
    'it': 'Messaggi, umore e «mi manchi» dal partner',
    'es': 'Mensajes, ánimo y «te echo de menos» de tu pareja',
    'fr': 'Messages, humeur et « tu me manques » du partenaire',
    'de': 'Nachrichten, Stimmung und „Ich vermisse dich“ vom Partner',
  },
  'pushPartnerFallback': {
    'ru': 'Партнёр',
    'en': 'Partner',
    'pt': 'Par',
    'it': 'Partner',
    'es': 'Pareja',
    'fr': 'Partenaire',
    'de': 'Partner',
  },
  'pushMoodMarked': {
    'ru': 'Отметил реакцию дня 🗓️',
    'en': 'Marked the day’s reaction 🗓️',
    'pt': 'Marcou a reação do dia 🗓️',
    'it': 'Ha segnato la reazione del giorno 🗓️',
    'es': 'Marcó la reacción del día 🗓️',
    'fr': 'A noté la réaction du jour 🗓️',
    'de': 'Hat die Reaktion des Tages markiert 🗓️',
  },
  'pushMoodOfDay': {
    'ru': 'Реакция дня',
    'en': 'Reaction of the day',
    'pt': 'Reação do dia',
    'it': 'Reazione del giorno',
    'es': 'Reacción del día',
    'fr': 'Réaction du jour',
    'de': 'Reaktion des Tages',
  },
  'pushNewMemory': {
    'ru': 'Добавил новое воспоминание 📸',
    'en': 'Added a new memory 📸',
    'pt': 'Adicionou uma nova lembrança 📸',
    'it': 'Ha aggiunto un nuovo ricordo 📸',
    'es': 'Añadió un nuevo recuerdo 📸',
    'fr': 'A ajouté un nouveau souvenir 📸',
    'de': 'Hat eine neue Erinnerung hinzugefügt 📸',
  },
  'pushThinkingOfYou': {
    'ru': 'Думает о тебе 💭',
    'en': 'Is thinking of you 💭',
    'pt': 'Está pensando em você 💭',
    'it': 'Sta pensando a te 💭',
    'es': 'Está pensando en ti 💭',
    'fr': 'Pense à toi 💭',
    'de': 'Denkt an dich 💭',
  },
  'pushWantHug': {
    'ru': 'Хочет обнять тебя 🤗',
    'en': 'Wants to hug you 🤗',
    'pt': 'Quer te abraçar 🤗',
    'it': 'Vuole abbracciarti 🤗',
    'es': 'Quiere abrazarte 🤗',
    'fr': 'A envie de te serrer dans ses bras 🤗',
    'de': 'Will dich umarmen 🤗',
  },
  'pushMissesYou': {
    'ru': 'Думает о тебе и вспоминает 💭',
    'en': 'Is thinking of you and remembering 💭',
    'pt': 'Está pensando e lembrando de você 💭',
    'it': 'Ti pensa e ti ricorda 💭',
    'es': 'Piensa en ti y te recuerda 💭',
    'fr': 'Pense à toi et se souvient 💭',
    'de': 'Denkt an dich und erinnert sich 💭',
  },
};
