// Голос в комнате совместного просмотра. Полоса живёт под плеером и работает
// без видео: позвонить можно в пустой комнате, поэтому подписи говорят про
// разговор, а не про просмотр.

const Map<String, Map<String, String>> watchVoiceStrings = {
  'watchVoiceCall': {
    'ru': 'Позвонить',
    'en': 'Call',
    'pt': 'Ligar',
    'it': 'Chiama',
    'es': 'Llamar',
    'fr': 'Appeler',
    'de': 'Anrufen',
  },
  'watchVoiceHangUp': {
    'ru': 'Положить трубку',
    'en': 'Hang up',
    'pt': 'Desligar',
    'it': 'Riaggancia',
    'es': 'Colgar',
    'fr': 'Raccrocher',
    'de': 'Auflegen',
  },
  'watchVoiceConnecting': {
    'ru': 'Соединяем…',
    'en': 'Connecting…',
    'pt': 'A ligar…',
    'it': 'Connessione…',
    'es': 'Conectando…',
    'fr': 'Connexion…',
    'de': 'Verbinden…',
  },
  'watchVoiceLive': {
    'ru': 'Вы слышите друг друга',
    'en': 'You can hear each other',
    'pt': 'Vocês se ouvem',
    'it': 'Vi sentite',
    'es': 'Os oís',
    'fr': 'Vous vous entendez',
    'de': 'Ihr hört euch',
  },
  'watchVoiceFailed': {
    'ru': 'Связь оборвалась, попробуйте снова',
    'en': 'The call dropped, try again',
    'pt': 'A chamada caiu, tente de novo',
    'it': 'La chiamata è caduta, riprova',
    'es': 'La llamada se cortó, inténtalo otra vez',
    'fr': 'L’appel a coupé, réessayez',
    'de': 'Die Verbindung brach ab, versuch es noch mal',
  },
  // Строка объясняет, что делает кнопка, а не зачем она придумана: «Говорите
  // даже без видео» рассказывало про замысел, и человек не понимал, что будет
  // после нажатия (правка 20.08.2026).
  'watchVoiceHint': {
    'ru': 'Включите голосовой режим для обсуждения',
    'en': 'Turn on voice to talk it over',
    'pt': 'Ative a voz para conversarem',
    'it': 'Attiva la voce per parlarne',
    'es': 'Activa la voz para comentarlo',
    'fr': 'Activez la voix pour en parler',
    'de': 'Sprachmodus einschalten und reden',
  },
  'watchVoiceMic': {
    'ru': 'Микрофон',
    'en': 'Microphone',
    'pt': 'Microfone',
    'it': 'Microfono',
    'es': 'Micrófono',
    'fr': 'Micro',
    'de': 'Mikrofon',
  },
  'watchVoiceSpeaker': {
    'ru': 'Динамик',
    'en': 'Speaker',
    'pt': 'Altifalante',
    'it': 'Altoparlante',
    'es': 'Altavoz',
    'fr': 'Haut-parleur',
    'de': 'Lautsprecher',
  },
};
