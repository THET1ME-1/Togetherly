// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> iMissYouVibesStrings = {
  'iMissYou': {
    'ru': 'Я скучаю',
    'en': 'I miss you',
    'pt': 'Estou com saudade',
    'it': 'Mi manchi',
    'es': 'Te echo de menos',
    'fr': 'Tu me manques',
    'de': 'Ich vermisse dich',
  },
  'iMissYouSent': {
    'ru': 'Отправлено! 💕',
    'en': 'Sent! 💕',
    'pt': 'Enviado! 💕',
    'it': 'Inviato! 💕',
    'es': '¡Enviado! 💕',
    'fr': 'Envoyé ! 💕',
    'de': 'Gesendet! 💕',
  },
  'missYouNotifBody': {
    'ru': 'Думает о вас и вспоминает 💭',
    'en': 'Thinking about you right now 💭',
    'pt': 'Está pensando em você 💭',
    'it': 'Sta pensando a te 💭',
    'es': 'Está pensando en ti 💭',
    'fr': 'Pense à toi en ce moment 💭',
    'de': 'Denkt gerade an dich 💭',
  },
  'thinkingOfYou': {
    'ru': 'Думаю о тебе',
    'en': 'Thinking of you',
    'pt': 'Penso em você',
    'it': 'Penso a te',
    'es': 'Pienso en ti',
    'fr': 'Je pense à toi',
    'de': 'Ich denke an dich',
  },
  'wantHug': {
    'ru': 'Хочу обнять',
    'en': 'Want a hug',
    'pt': 'Quero te abraçar',
    'it': 'Voglio abbracciarti',
    'es': 'Quiero abrazarte',
    'fr': 'J’ai envie de te serrer',
    'de': 'Ich will dich umarmen',
  },
  'vibeSent': {
    'ru': 'Отправлено ✨',
    'en': 'Sent ✨',
    'pt': 'Enviado ✨',
    'it': 'Inviato ✨',
    'es': 'Enviado ✨',
    'fr': 'Envoyé ✨',
    'de': 'Gesendet ✨',
  },
  'customVibe': {
    'ru': 'Своё желание...',
    'en': 'Custom wish...',
    'pt': 'Meu pedido...',
    'it': 'Il mio desiderio...',
    'es': 'Mi deseo...',
    'fr': 'Mon souhait...',
    'de': 'Eigener Wunsch...',
  },
  'customVibeTitle': {
    'ru': 'Своё сообщение',
    'en': 'Custom message',
    'pt': 'Mensagem própria',
    'it': 'Messaggio personale',
    'es': 'Mensaje propio',
    'fr': 'Message perso',
    'de': 'Eigene Nachricht',
  },
  'customVibeHint': {
    'ru': 'Что ты хочешь сказать?',
    'en': 'What do you want to say?',
    'pt': 'O que você quer dizer?',
    'it': 'Che cosa vuoi dire?',
    'es': '¿Qué quieres decir?',
    'fr': 'Qu’est-ce que tu veux dire ?',
    'de': 'Was möchtest du sagen?',
  },
};
