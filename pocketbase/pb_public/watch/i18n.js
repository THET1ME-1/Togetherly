/* Русский, английский и португальский для лендинга и комнаты.
 *
 * Тексты лежат в одном словаре, разметка помечена data-i18n. Язык берётся из
 * адреса (`?lang=`, его передаёт приложение), потом из выбора человека, а если
 * выбора не было — из языка браузера. Русский и португальский показываем тем,
 * у кого такой браузер, остальным английский. Ключа нет в португальском —
 * берётся английский.
 */
(() => {
  'use strict';

  const DICT = {
    ru: {
      'nav.how': 'Как работает',
      'nav.where': 'Площадки',
      'nav.privacy': 'Приватность',
      'nav.app': 'Приложение',
      'nav.theme': 'Сменить тему',

      'hero.eyebrow': 'Комната на двоих в браузере',
      'hero.title1': 'СМОТРИМ',
      'hero.title2': 'ОДНО',
      'hero.title3': 'КИНО',
      'hero.lead': 'Один тайм-код на двоих. Пауза, перемотка и чат приезжают партнёру мгновенно.',
      'hero.create': 'Создать комнату',
      'hero.code': 'Код комнаты',
      'hero.join': 'Войти',
      'hero.note': 'Без регистрации. Комната открывается за секунду.',

      'start.cap': 'Комната на двоих',
      'start.or': 'или по коду',

      'how.kicker': '→ Как это работает',
      'how.1.title': 'Создайте',
      'how.1.text': 'Комната появляется сразу и живёт, пока вы в ней. Регистрация не нужна.',
      'how.2.title': 'Позовите',
      'how.2.text': 'Отправьте ссылку. Партнёр открывает её и оказывается рядом.',
      'how.3.title': 'Смотрите',
      'how.3.text': 'Поставил паузу один, встала у обоих. Время подтягивается само.',

      'where.kicker': '→ Откуда смотреть',
      'where.foot': 'Вставьте ссылку на ролик или фильм с любой из площадок. Своё видео тоже подойдёт: прямая ссылка на файл открывается как есть.',

      'privacy.kicker': '→ Что остаётся на сервере',
      'privacy.title': 'Ничего',
      'privacy.lead': 'Комната существует, пока в ней есть люди. Закрыли вкладки, и она исчезла вместе со ссылкой на видео и перепиской. В базе не появляется ни одной записи.',
      'privacy.1.title': 'Без аккаунта',
      'privacy.1.text': 'Вход анонимный, почта не нужна.',
      'privacy.2.title': 'Без истории',
      'privacy.2.text': 'Сообщения живут только в открытых вкладках.',
      'privacy.3.title': 'Без файлов',
      'privacy.3.text': 'Видео отдаёт площадка, а не мы.',

      'promo.kicker': '→ А ещё есть приложение',
      'promo.title': 'Togetherly для пар',
      'promo.text': 'Общие воспоминания, календарь настроений, подарки друг другу и виджеты на экране телефона.',
      'promo.btn': 'Скачать',

      'foot.privacy': 'Конфиденциальность',
      'foot.terms': 'Условия',
      'foot.about': 'Комната на двоих в браузере: одно видео, один тайм-код, чат рядом. Без регистрации, без истории, без файлов на сервере.',
      'foot.col.watch': 'Смотреть',
      'foot.col.app': 'Приложение',
      'foot.col.help': 'Поддержка',
      'foot.github': 'GitHub Releases',
      'foot.rights': '© 2026 Togetherly. Все права защищены.',
      'foot.made': 'Сделано для тех, кто далеко друг от друга.',

      // комната
      'room.copy': 'Скопировать ссылку',
      'room.copied': 'Ссылка скопирована',
      'room.share': 'Поделиться',
      'room.back': 'Назад',
      'room.fold': 'Свернуть шапку',
      'room.unfold': 'Развернуть шапку',
      'room.code': 'Код комнаты',
      'room.alone': 'вы один',
      'room.viewers': 'смотрят: {n}',
      'room.empty': 'Вставьте ссылку на видео',
      'room.linkPlaceholder': 'Ссылка на видео, Яндекс Диск, Google Диск, Dropbox',
      'room.play': 'Включить',
      'room.fileBtn': 'Открыть файл с диска',
      'room.fileSource': 'файл',
      'room.filePlaying': 'Играет ваш файл: {name}',
      'room.fileWanted': 'Партнёр включил {name}. Откройте у себя такой же файл.',
      'room.fileChoose': 'Выбрать файл',
      'room.resolving': 'Спрашиваю ссылку у Диска…',
      'room.manualNote': 'Этим плеером управляет каждый сам: жмите вместе по отсчёту.',
      'room.together': 'Начать вместе',
      'room.pauseBoth': 'Пауза у обоих',
      'room.now': 'Играй!',
      'room.pauseNow': 'Пауза',
      'room.chat': 'Чат',
      'room.chatEmpty': 'Здесь пока пусто. Напишите первым.',
      'room.message': 'Написать…',
      'room.connecting': 'Подключаюсь…',
      'room.ready': 'Комната готова',
      'room.lost': 'Связь потеряна, переподключаюсь…',
      'room.offline': 'Нет связи',
      'room.badLink': 'Такую ссылку не открыть. Годятся YouTube, ВК, Rutube, Vimeo, Яндекс.Диск, Google Drive, Dropbox, MEGA и прямые ссылки на файл',
      'room.seekMissed': 'Этот плеер не смог перемотать файл: он слишком тяжёлый. Перемотайте вручную или включите фильм по ссылке с Яндекс.Диска',
      'room.driveFolder': 'Это ссылка на папку Google Диска. Откройте в Диске само видео, нажмите «Поделиться» и скопируйте ссылку на файл',
      'room.playing': 'Играет: {name}',
      'room.leave': 'Выйти',
      'room.voiceCall': 'Позвонить',
      'room.voiceHang': 'Положить трубку',
      'room.voiceMic': 'Микрофон',
      'room.voiceRinging': 'Ждём ответа',
      'room.voiceFailed': 'Связь не поднялась',
      'room.you': 'Вы',
      'room.guest': 'Гость',
      'room.send': 'Отправить',
      'room.chatToggle': 'Скрыть или показать чат',
      'room.chatOpen': 'Открыть чат',
      'room.partnerJoined': 'Партнёр в комнате',

      'gate.closedTitle': 'Комната пары',
      'gate.closedText': 'Сюда пускают только вас двоих. Войдите тем же аккаунтом, что в приложении Togetherly. Если код набирали вручную, проверьте его.',
      'gate.closedAppText': 'Приложение не успело открыть комнату. Закройте её и откройте снова. Не поможет, войдите почтой и паролем от Togetherly.',
      'gate.strangerTitle': 'Это не ваша комната',
      'gate.strangerText': 'Аккаунт {who} не состоит в этой паре. Войдите тем аккаунтом, с которым вы в паре, или создайте свою комнату.',
      'gate.thisAccount': 'на этой странице',
      'gate.missingTitle': 'Такой комнаты нет',
      'gate.missingText': 'Проверьте код. Или создайте новую комнату и отправьте ссылку тому, с кем хотите смотреть.',
      'gate.email': 'Почта',
      'gate.pass': 'Пароль',
      'gate.signIn': 'Войти',
      'gate.or': 'или',
      'gate.yandex': 'Яндекс',
      'gate.other': 'Войти другим аккаунтом',
      'gate.create': 'Создать комнату',
      'gate.home': 'На главную',
      'gate.wait': 'Проверяю…',
      'gate.badPair': 'Почта или пароль не подошли',
      'gate.fail': 'Не получилось. Попробуйте ещё раз',
      'hero.createFailed': 'Комната не создалась. Проверьте интернет и нажмите ещё раз',
    },
    en: {
      'nav.how': 'How it works',
      'nav.where': 'Sources',
      'nav.privacy': 'Privacy',
      'nav.app': 'App',
      'nav.theme': 'Switch theme',

      'hero.eyebrow': 'A room for two, right in the browser',
      'hero.title1': 'ONE MOVIE',
      'hero.title2': 'TWO',
      'hero.title3': 'SCREENS',
      'hero.lead': 'One timecode for both of you. Pause, seek and chat reach your partner instantly.',
      'hero.create': 'Create a room',
      'hero.code': 'Room code',
      'hero.join': 'Join',
      'hero.note': 'No sign-up. The room opens in a second.',

      'start.cap': 'A room for two',
      'start.or': 'or by code',

      'how.kicker': '→ How it works',
      'how.1.title': 'Create',
      'how.1.text': 'The room opens instantly and lives while you are in it. No sign-up.',
      'how.2.title': 'Invite',
      'how.2.text': 'Send the link. Your partner opens it and lands next to you.',
      'how.3.title': 'Watch',
      'how.3.text': 'One of you pauses, it pauses for both. Time catches up on its own.',

      'where.kicker': '→ Where to watch from',
      'where.foot': 'Paste a link from any of these. Your own video works too: a direct file link plays as is.',

      'privacy.kicker': '→ What stays on the server',
      'privacy.title': 'Nothing',
      'privacy.lead': 'The room exists while people are in it. Close the tabs and it is gone, along with the video link and the chat. Not a single record is written.',
      'privacy.1.title': 'No account',
      'privacy.1.text': 'Anonymous entry, no email needed.',
      'privacy.2.title': 'No history',
      'privacy.2.text': 'Messages live only in open tabs.',
      'privacy.3.title': 'No files',
      'privacy.3.text': 'Video comes from the platform, not from us.',

      'promo.kicker': '→ There is an app, too',
      'promo.title': 'Togetherly for couples',
      'promo.text': 'Shared memories, a mood calendar, gifts for each other and widgets on your home screen.',
      'promo.btn': 'Download',

      'foot.privacy': 'Privacy',
      'foot.terms': 'Terms',
      'foot.about': 'A room for two right in the browser: one video, one timecode, chat alongside. No sign-up, no history, no files on the server.',
      'foot.col.watch': 'Watch',
      'foot.col.app': 'App',
      'foot.col.help': 'Support',
      'foot.github': 'GitHub Releases',
      'foot.rights': '© 2026 Togetherly. All rights reserved.',
      'foot.made': 'Made for those who are far apart.',

      'room.copy': 'Copy link',
      'room.copied': 'Link copied',
      'room.share': 'Share',
      'room.back': 'Back',
      'room.fold': 'Collapse header',
      'room.unfold': 'Expand header',
      'room.code': 'Room code',
      'room.alone': 'just you',
      'room.viewers': 'watching: {n}',
      'room.empty': 'Paste a video link',
      'room.linkPlaceholder': 'Link to a video, Yandex Disk, Google Drive, Dropbox',
      'room.play': 'Play',
      'room.fileBtn': 'Open a file from disk',
      'room.fileSource': 'file',
      'room.filePlaying': 'Playing your file: {name}',
      'room.fileWanted': 'Your partner started {name}. Open the same file on your side.',
      'room.fileChoose': 'Choose a file',
      'room.resolving': 'Asking the disk for a link…',
      'room.manualNote': 'This player takes no commands: press together on the countdown.',
      'room.together': 'Start together',
      'room.pauseBoth': 'Pause for both',
      'room.now': 'Go!',
      'room.pauseNow': 'Pause',
      'room.chat': 'Chat',
      'room.chatEmpty': 'Nothing here yet. Say something first.',
      'room.message': 'Message…',
      'room.connecting': 'Connecting…',
      'room.ready': 'Room is ready',
      'room.lost': 'Connection lost, reconnecting…',
      'room.offline': 'Offline',
      'room.badLink': 'Can\u2019t open that link. Works with YouTube, VK, Rutube, Vimeo, Yandex.Disk, Google Drive, Dropbox, MEGA and direct file links',
      'room.seekMissed': 'This player couldn\u2019t jump in the file: it\u2019s too heavy. Seek by hand or play the film from a Yandex.Disk link',
      'room.driveFolder': 'That\u2019s a link to a Google Drive folder. Open the video itself in Drive, tap Share and copy the link to the file',
      'room.playing': 'Playing: {name}',
      'room.leave': 'Leave',
      'room.voiceCall': 'Call',
      'room.voiceHang': 'Hang up',
      'room.voiceMic': 'Microphone',
      'room.voiceRinging': 'Ringing',
      'room.voiceFailed': 'Call failed',
      'room.you': 'You',
      'room.guest': 'Guest',
      'room.send': 'Send',
      'room.chatToggle': 'Hide or show chat',
      'room.chatOpen': 'Open chat',
      'room.partnerJoined': 'Your partner is here',

      'gate.closedTitle': 'A couple\u2019s room',
      'gate.closedText': 'Only the two of you can come in. Sign in with the account you use in the Togetherly app. If you typed the code by hand, check it.',
      'gate.closedAppText': 'The app didn\u2019t open the room in time. Close it and open it again. If that doesn\u2019t help, sign in with your Togetherly email and password.',
      'gate.strangerTitle': 'This room isn\u2019t yours',
      'gate.strangerText': 'The account {who} isn\u2019t part of this couple. Sign in with the account you share a couple with, or create your own room.',
      'gate.thisAccount': 'on this page',
      'gate.missingTitle': 'No such room',
      'gate.missingText': 'Check the code. Or create a new room and send the link to whoever you want to watch with.',
      'gate.email': 'Email',
      'gate.pass': 'Password',
      'gate.signIn': 'Sign in',
      'gate.or': 'or',
      'gate.yandex': 'Yandex',
      'gate.other': 'Use another account',
      'gate.create': 'Create a room',
      'gate.home': 'Back to home',
      'gate.wait': 'Checking…',
      'gate.badPair': 'Wrong email or password',
      'gate.fail': 'That didn\u2019t work. Try again',
      'hero.createFailed': 'Couldn\u2019t create the room. Check your connection and try again',
    },
    pt: {
      'nav.how': 'Como funciona',
      'nav.where': 'Plataformas',
      'nav.privacy': 'Privacidade',
      'nav.app': 'App',
      'nav.theme': 'Mudar tema',

      'hero.eyebrow': 'Uma sala para dois, direto no navegador',
      'hero.title1': 'UM FILME',
      'hero.title2': 'DUAS',
      'hero.title3': 'TELAS',
      'hero.lead': 'Um s\u00f3 tempo para voc\u00eas dois. Pausa, avan\u00e7o e chat chegam ao seu par na hora.',
      'hero.create': 'Criar sala',
      'hero.code': 'C\u00f3digo da sala',
      'hero.join': 'Entrar',
      'hero.note': 'Sem cadastro. A sala abre em um segundo.',

      'start.cap': 'Uma sala para dois',
      'start.or': 'ou pelo c\u00f3digo',

      'how.kicker': '\u2192 Como funciona',
      'how.1.title': 'Crie',
      'how.1.text': 'A sala abre na hora e existe enquanto voc\u00eas est\u00e3o nela. Sem cadastro.',
      'how.2.title': 'Convide',
      'how.2.text': 'Mande o link. Seu par abre e j\u00e1 aparece ao seu lado.',
      'how.3.title': 'Assistam',
      'how.3.text': 'Um pausa, pausa para os dois. O tempo se acerta sozinho.',

      'where.kicker': '\u2192 De onde assistir',
      'where.foot': 'Cole um link de qualquer uma delas. V\u00eddeo seu tamb\u00e9m serve: o link direto para o arquivo toca como est\u00e1.',

      'privacy.kicker': '\u2192 O que fica no servidor',
      'privacy.title': 'Nada',
      'privacy.lead': 'A sala existe enquanto tem gente nela. Fechou as abas, ela some, junto com o link do v\u00eddeo e o chat. Nenhum registro \u00e9 gravado.',
      'privacy.1.title': 'Sem conta',
      'privacy.1.text': 'Entrada an\u00f4nima, sem e-mail.',
      'privacy.2.title': 'Sem hist\u00f3rico',
      'privacy.2.text': 'As mensagens vivem s\u00f3 nas abas abertas.',
      'privacy.3.title': 'Sem arquivos',
      'privacy.3.text': 'O v\u00eddeo vem da plataforma, n\u00e3o de n\u00f3s.',

      'promo.kicker': '\u2192 Tamb\u00e9m tem app',
      'promo.title': 'Togetherly para casais',
      'promo.text': 'Lembran\u00e7as em comum, calend\u00e1rio de humor, presentes um para o outro e widgets na tela inicial.',
      'promo.btn': 'Baixar',

      'foot.privacy': 'Privacidade',
      'foot.terms': 'Termos',
      'foot.about': 'Uma sala para dois direto no navegador: um v\u00eddeo, um s\u00f3 tempo, chat ao lado. Sem cadastro, sem hist\u00f3rico, sem arquivos no servidor.',
      'foot.col.watch': 'Assistir',
      'foot.col.app': 'App',
      'foot.col.help': 'Suporte',
      'foot.github': 'GitHub Releases',
      'foot.rights': '\u00a9 2026 Togetherly. Todos os direitos reservados.',
      'foot.made': 'Feito para quem est\u00e1 longe.',

      'room.copy': 'Copiar link',
      'room.copied': 'Link copiado',
      'room.share': 'Compartilhar',
      'room.back': 'Voltar',
      'room.fold': 'Recolher o topo',
      'room.unfold': 'Abrir o topo',
      'room.code': 'C\u00f3digo da sala',
      'room.alone': 's\u00f3 voc\u00ea',
      'room.viewers': 'assistindo: {n}',
      'room.empty': 'Cole o link de um v\u00eddeo',
      'room.linkPlaceholder': 'Link de v\u00eddeo, Yandex Disk, Google Drive, Dropbox',
      'room.play': 'Assistir',
      'room.fileBtn': 'Abrir arquivo do aparelho',
      'room.fileSource': 'arquivo',
      'room.filePlaying': 'Tocando seu arquivo: {name}',
      'room.fileWanted': 'Seu par abriu {name}. Abra o mesmo arquivo a\u00ed do seu lado.',
      'room.fileChoose': 'Escolher arquivo',
      'room.resolving': 'Pedindo o link ao disco\u2026',
      'room.manualNote': 'Este player n\u00e3o recebe comandos: apertem juntos na contagem.',
      'room.together': 'Come\u00e7ar juntos',
      'room.pauseBoth': 'Pausar para os dois',
      'room.now': 'J\u00e1!',
      'room.pauseNow': 'Pausa',
      'room.chat': 'Chat',
      'room.chatEmpty': 'Ainda n\u00e3o tem nada aqui. Escreva primeiro.',
      'room.message': 'Mensagem\u2026',
      'room.connecting': 'Conectando\u2026',
      'room.ready': 'Sala pronta',
      'room.lost': 'Conex\u00e3o perdida, reconectando\u2026',
      'room.offline': 'Sem conex\u00e3o',
      'room.badLink': 'N\u00e3o d\u00e1 para abrir esse link. Funciona com YouTube, VK, Rutube, Vimeo, Yandex.Disk, Google Drive, Dropbox, MEGA e links diretos para arquivos',
      'room.seekMissed': 'Este player n\u00e3o conseguiu pular no arquivo: ele \u00e9 pesado demais. Avance na m\u00e3o ou toque o filme por um link do Yandex.Disk',
      'room.driveFolder': 'Esse \u00e9 o link de uma pasta do Google Drive. Abra o pr\u00f3prio v\u00eddeo no Drive, toque em Compartilhar e copie o link do arquivo',
      'room.playing': 'Tocando: {name}',
      'room.leave': 'Sair',
      'room.voiceCall': 'Ligar',
      'room.voiceHang': 'Desligar',
      'room.voiceMic': 'Microfone',
      'room.voiceRinging': 'Chamando',
      'room.voiceFailed': 'A liga\u00e7\u00e3o falhou',
      'room.you': 'Voc\u00ea',
      'room.guest': 'Convidado',
      'room.send': 'Enviar',
      'room.chatToggle': 'Esconder ou mostrar o chat',
      'room.chatOpen': 'Abrir o chat',
      'room.partnerJoined': 'Seu par chegou',

      'gate.closedTitle': 'Sala do casal',
      'gate.closedText': 'S\u00f3 voc\u00eas dois podem entrar. Entre com a conta que voc\u00ea usa no app Togetherly. Se digitou o c\u00f3digo na m\u00e3o, confira.',
      'gate.closedAppText': 'O app n\u00e3o abriu a sala a tempo. Feche e abra de novo. Se n\u00e3o ajudar, entre com o e-mail e a senha do Togetherly.',
      'gate.strangerTitle': 'Esta sala n\u00e3o \u00e9 sua',
      'gate.strangerText': 'A conta {who} n\u00e3o faz parte deste casal. Entre com a conta com que voc\u00ea forma o casal ou crie sua pr\u00f3pria sala.',
      'gate.thisAccount': 'nesta p\u00e1gina',
      'gate.missingTitle': 'Sala n\u00e3o encontrada',
      'gate.missingText': 'Confira o c\u00f3digo. Ou crie uma sala nova e mande o link para quem voc\u00ea quer assistir junto.',
      'gate.email': 'E-mail',
      'gate.pass': 'Senha',
      'gate.signIn': 'Entrar',
      'gate.or': 'ou',
      'gate.yandex': 'Yandex',
      'gate.other': 'Entrar com outra conta',
      'gate.create': 'Criar sala',
      'gate.home': 'Voltar ao in\u00edcio',
      'gate.wait': 'Verificando\u2026',
      'gate.badPair': 'E-mail ou senha incorretos',
      'gate.fail': 'N\u00e3o deu certo. Tente de novo',
      'hero.createFailed': 'A sala n\u00e3o foi criada. Confira a internet e tente de novo',
    },
  };

  const KEY = 'togetherly.watch.lang';
  const LANGS = ['ru', 'en', 'pt'];

  // \u042f\u0437\u044b\u043a \u0438\u0437 \u0430\u0434\u0440\u0435\u0441\u0430 (`?lang=pt`, \u0435\u0433\u043e \u0441\u0442\u0430\u0432\u0438\u0442 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435), \u043f\u043e\u0442\u043e\u043c \u0432\u044b\u0431\u043e\u0440 \u0447\u0435\u043b\u043e\u0432\u0435\u043a\u0430,
  // \u043f\u043e\u0442\u043e\u043c \u044f\u0437\u044b\u043a \u0431\u0440\u0430\u0443\u0437\u0435\u0440\u0430. \u041f\u043e\u0440\u0442\u0443\u0433\u0430\u043b\u044c\u0441\u043a\u0438\u0439 \u0438 \u0440\u0443\u0441\u0441\u043a\u0438\u0439 \u0431\u0435\u0440\u0451\u043c \u043f\u043e \u0431\u0440\u0430\u0443\u0437\u0435\u0440\u0443, \u043e\u0441\u0442\u0430\u043b\u044c\u043d\u044b\u043c
  // \u0430\u043d\u0433\u043b\u0438\u0439\u0441\u043a\u0438\u0439.
  function detect() {
    let asked = '';
    try {
      asked = new URLSearchParams(location.search).get('lang') || '';
    } catch (_) {}
    if (LANGS.includes(asked)) return asked;
    const saved = localStorage.getItem(KEY);
    if (LANGS.includes(saved)) return saved;
    const langs = navigator.languages || [navigator.language || 'en'];
    const first = langs.map((l) => String(l).toLowerCase().slice(0, 2)).find((l) => l === 'ru' || l === 'pt');
    return first || 'en';
  }

  const I18N = {
    lang: detect(),

    t(key, vars) {
      let text = (DICT[this.lang] && DICT[this.lang][key])
        || (this.lang !== 'ru' && DICT.en[key]) || DICT.ru[key] || key;
      if (vars) {
        Object.keys(vars).forEach((k) => {
          text = text.replace('{' + k + '}', vars[k]);
        });
      }
      return text;
    },

    apply(root) {
      const scope = root || document;
      scope.querySelectorAll('[data-i18n]').forEach((el) => {
        el.textContent = this.t(el.getAttribute('data-i18n'));
      });
      scope.querySelectorAll('[data-i18n-ph]').forEach((el) => {
        el.placeholder = this.t(el.getAttribute('data-i18n-ph'));
      });
      scope.querySelectorAll('[data-i18n-aria]').forEach((el) => {
        el.setAttribute('aria-label', this.t(el.getAttribute('data-i18n-aria')));
      });
      document.documentElement.lang = this.lang;
      document.querySelectorAll('[data-lang-btn]').forEach((btn) => {
        btn.classList.toggle('is-on', btn.getAttribute('data-lang-btn') === this.lang);
      });
    },

    set(lang) {
      if (!LANGS.includes(lang)) return;
      this.lang = lang;
      localStorage.setItem(KEY, lang);
      this.apply();
      document.dispatchEvent(new CustomEvent('langchange', { detail: lang }));
    },

    mount() {
      document.querySelectorAll('[data-lang-btn]').forEach((btn) => {
        btn.addEventListener('click', () => this.set(btn.getAttribute('data-lang-btn')));
      });
      this.apply();
    },
  };

  window.I18N = I18N;
})();
