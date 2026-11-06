// Закреплённые сообщения чата (06.11.2026). Украинский и китайский — в
// `../uk/chat_pins.dart` и `../zh/chat_pins.dart`. Пола партнёра чат не
// знает, поэтому строка о его закреплении без глагола в прошедшем времени.

const Map<String, Map<String, String>> chatPinsStrings = {
  'cpPin': {'ru': 'Закрепить', 'en': 'Pin', 'pt': 'Fixar', 'it': 'Fissa', 'es': 'Fijar', 'fr': 'Épingler', 'de': 'Anheften'},
  'cpUnpin': {'ru': 'Открепить', 'en': 'Unpin', 'pt': 'Desafixar', 'it': 'Togli dai fissati', 'es': 'Desfijar', 'fr': 'Désépingler', 'de': 'Lösen'},
  // {0} — номер, {1} — сколько всего
  'cpBarTitle': {'ru': 'Закреплённое · {0} из {1}', 'en': 'Pinned · {0} of {1}', 'pt': 'Fixada · {0} de {1}', 'it': 'Fissato · {0} di {1}', 'es': 'Fijado · {0} de {1}', 'fr': 'Épinglé · {0} sur {1}', 'de': 'Angeheftet · {0} von {1}'},
  'cpBarSingle': {'ru': 'Закреплённое сообщение', 'en': 'Pinned message', 'pt': 'Mensagem fixada', 'it': 'Messaggio fissato', 'es': 'Mensaje fijado', 'fr': 'Message épinglé', 'de': 'Angeheftete Nachricht'},
  'cpAll': {'ru': 'Все закреплённые', 'en': 'All pinned', 'pt': 'Todas as fixadas', 'it': 'Tutti i fissati', 'es': 'Todos los fijados', 'fr': 'Tous les épinglés', 'de': 'Alle angehefteten'},
  // Заголовок экрана; {0} — число. «One» — для 1, 21, 31…
  'cpCountOne': {'ru': '{0} закреплённое', 'en': '{0} pinned message', 'pt': '{0} mensagem fixada', 'it': '{0} messaggio fissato', 'es': '{0} mensaje fijado', 'fr': '{0} message épinglé', 'de': '{0} angeheftete Nachricht'},
  'cpCountMany': {'ru': '{0} закреплённых', 'en': '{0} pinned messages', 'pt': '{0} mensagens fixadas', 'it': '{0} messaggi fissati', 'es': '{0} mensajes fijados', 'fr': '{0} messages épinglés', 'de': '{0} angeheftete Nachrichten'},
  'cpShowInChat': {'ru': 'Показать в чате', 'en': 'Show in chat', 'pt': 'Mostrar no chat', 'it': 'Mostra nella chat', 'es': 'Ver en el chat', 'fr': 'Voir dans le chat', 'de': 'Im Chat zeigen'},
  'cpHoldHint': {'ru': 'Долгое нажатие на сообщение: открепить', 'en': 'Long-press a message to unpin it', 'pt': 'Toque longo na mensagem para desafixar', 'it': 'Tieni premuto un messaggio per toglierlo', 'es': 'Mantén pulsado un mensaje para desfijarlo', 'fr': 'Appui long sur un message pour le désépingler', 'de': 'Lange auf eine Nachricht tippen, um sie zu lösen'},
  'cpUnpinAll': {'ru': 'Открепить все', 'en': 'Unpin all', 'pt': 'Desafixar todas', 'it': 'Togli tutti', 'es': 'Desfijar todos', 'fr': 'Tout désépingler', 'de': 'Alle lösen'},
  'cpUnpinAllAsk': {'ru': 'Открепить все сообщения? У партнёра они тоже открепятся.', 'en': 'Unpin all messages? They will be unpinned for your partner too.', 'pt': 'Desafixar todas as mensagens? Elas também serão desafixadas para o parceiro.', 'it': 'Togliere tutti i messaggi fissati? Spariranno anche per il partner.', 'es': '¿Desfijar todos los mensajes? También se desfijarán para tu pareja.', 'fr': 'Désépingler tous les messages ? Ils le seront aussi pour votre partenaire.', 'de': 'Alle Nachrichten lösen? Sie werden auch für deinen Partner gelöst.'},
  'cpEmpty': {'ru': 'Закреплённых сообщений нет', 'en': 'No pinned messages', 'pt': 'Nenhuma mensagem fixada', 'it': 'Nessun messaggio fissato', 'es': 'No hay mensajes fijados', 'fr': 'Aucun message épinglé', 'de': 'Keine angehefteten Nachrichten'},
  // {0} — начало текста сообщения
  'cpNoteMine': {'ru': 'Вы закрепили «{0}»', 'en': 'You pinned “{0}”', 'pt': 'Você fixou “{0}”', 'it': 'Hai fissato «{0}»', 'es': 'Fijaste «{0}»', 'fr': 'Vous avez épinglé « {0} »', 'de': 'Du hast „{0}“ angeheftet'},
  // {0} — начало текста, {1} — имя партнёра
  'cpNoteTheirs': {'ru': '{1}: закреплено «{0}»', 'en': '{1} pinned “{0}”', 'pt': '{1} fixou “{0}”', 'it': '{1} ha fissato «{0}»', 'es': '{1} fijó «{0}»', 'fr': '{1} a épinglé « {0} »', 'de': '{1} hat „{0}“ angeheftet'},
};
