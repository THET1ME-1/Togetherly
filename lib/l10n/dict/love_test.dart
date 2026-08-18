// Тест «Умение любить»: грани, градации ответа и двадцать утверждений.
//
// Лежали строками прямо в модели — по-русски и без единого перевода, поэтому
// немец, испанец и все остальные видели русский текст (жалоба 18.08.2026).
// Ключи считаются из порядкового номера (`love_q1`…`love_q20`) и имени грани,
// поэтому новое утверждение — это запись здесь и строчка в `kLoveQuestions`.
//
// Утверждение №9 заодно перестало обрываться: «Я замечаю, что он для меня
// меняет» — предложение без конца, стало «Я замечаю, что он меняется ради меня».

const Map<String, Map<String, String>> loveTestStrings = {
  // ── Грани ────────────────────────────────────────────────────────────────
  'love_facet_interest': {
    'ru': 'Интерес',
    'en': 'Interest',
    'de': 'Interesse',
    'fr': 'Intérêt',
    'es': 'Interés',
    'it': 'Interesse',
    'pt': 'Interesse',
  },
  'love_facet_trust': {
    'ru': 'Доверие',
    'en': 'Trust',
    'de': 'Vertrauen',
    'fr': 'Confiance',
    'es': 'Confianza',
    'it': 'Fiducia',
    'pt': 'Confiança',
  },
  'love_facet_gratitude': {
    'ru': 'Благодарность',
    'en': 'Gratitude',
    'de': 'Dankbarkeit',
    'fr': 'Gratitude',
    'es': 'Gratitud',
    'it': 'Gratitudine',
    'pt': 'Gratidão',
  },
  'love_facet_mutuality': {
    'ru': 'Взаимность',
    'en': 'Mutuality',
    'de': 'Gegenseitigkeit',
    'fr': 'Réciprocité',
    'es': 'Reciprocidad',
    'it': 'Reciprocità',
    'pt': 'Reciprocidade',
  },
  'love_facet_passion': {
    'ru': 'Страсть',
    'en': 'Passion',
    'de': 'Leidenschaft',
    'fr': 'Passion',
    'es': 'Pasión',
    'it': 'Passione',
    'pt': 'Paixão',
  },
  'love_facet_acceptance': {
    'ru': 'Принятие',
    'en': 'Acceptance',
    'de': 'Akzeptanz',
    'fr': 'Acceptation',
    'es': 'Aceptación',
    'it': 'Accettazione',
    'pt': 'Aceitação',
  },

  // ── Градации ответа ──────────────────────────────────────────────────────
  'love_answer_0': {
    'ru': 'Почти никогда',
    'en': 'Almost never',
    'de': 'Fast nie',
    'fr': 'Presque jamais',
    'es': 'Casi nunca',
    'it': 'Quasi mai',
    'pt': 'Quase nunca',
  },
  'love_answer_1': {
    'ru': 'Редко',
    'en': 'Rarely',
    'de': 'Selten',
    'fr': 'Rarement',
    'es': 'Rara vez',
    'it': 'Raramente',
    'pt': 'Raramente',
  },
  'love_answer_2': {
    'ru': 'Часто',
    'en': 'Often',
    'de': 'Oft',
    'fr': 'Souvent',
    'es': 'A menudo',
    'it': 'Spesso',
    'pt': 'Muitas vezes',
  },
  'love_answer_3': {
    'ru': 'Почти всегда',
    'en': 'Almost always',
    'de': 'Fast immer',
    'fr': 'Presque toujours',
    'es': 'Casi siempre',
    'it': 'Quasi sempre',
    'pt': 'Quase sempre',
  },

  // ── Интерес ──────────────────────────────────────────────────────────────
  'love_q1': {
    'ru': 'Я замечаю, что партнёру тяжело, раньше, чем он об этом скажет',
    'en': 'I notice my partner is struggling before they say a word',
    'de': 'Ich merke, dass es meinem Partner schlecht geht, bevor er es sagt',
    'fr': 'Je remarque que mon partenaire va mal avant qu’il le dise',
    'es': 'Noto que mi pareja lo está pasando mal antes de que lo diga',
    'it': 'Mi accorgo che il mio partner sta male prima che lo dica',
    'pt': 'Percebo que meu par está mal antes de ele dizer',
  },
  'love_q2': {
    'ru': 'Мне любопытно, что он думает о вещах, которые меня не касаются',
    'en': 'I am curious what they think about things that do not concern me',
    'de': 'Mich interessiert, was er über Dinge denkt, die mich nichts angehen',
    'fr':
        'Je suis curieux de ce qu’il pense de choses qui ne me concernent pas',
    'es': 'Tengo curiosidad por lo que piensa de cosas que no me afectan',
    'it': 'Sono curioso di sapere cosa pensa di cose che non mi riguardano',
    'pt':
        'Tenho curiosidade sobre o que ele pensa de coisas que não me dizem respeito',
  },
  'love_q3': {
    'ru': 'Я помню, чем он был занят на этой неделе',
    'en': 'I remember what they were busy with this week',
    'de': 'Ich weiß noch, womit er diese Woche beschäftigt war',
    'fr': 'Je me souviens de ce qui l’a occupé cette semaine',
    'es': 'Recuerdo con qué estuvo ocupado esta semana',
    'it': 'Ricordo di cosa si è occupato questa settimana',
    'pt': 'Lembro do que ele fez esta semana',
  },

  // ── Доверие ──────────────────────────────────────────────────────────────
  'love_q4': {
    'ru': 'Я рассказываю ему о своих неудачах, не смягчая',
    'en': 'I tell them about my failures without softening them',
    'de': 'Ich erzähle ihm von meinen Misserfolgen, ohne sie zu beschönigen',
    'fr': 'Je lui parle de mes échecs sans les adoucir',
    'es': 'Le cuento mis fracasos sin suavizarlos',
    'it': 'Gli racconto i miei fallimenti senza addolcirli',
    'pt': 'Conto meus fracassos sem suavizar',
  },
  'love_q5': {
    'ru': 'Когда он задерживается, я не выстраиваю худших версий',
    'en': 'When they are late, I do not imagine the worst',
    'de': 'Wenn er sich verspätet, male ich mir nicht das Schlimmste aus',
    'fr': 'Quand il est en retard, je n’imagine pas le pire',
    'es': 'Cuando llega tarde, no me imagino lo peor',
    'it': 'Quando fa tardi, non immagino il peggio',
    'pt': 'Quando ele se atrasa, não imagino o pior',
  },
  'love_q6': {
    'ru': 'Я могу молчать рядом с ним и не чувствовать неловкости',
    'en': 'I can be silent next to them without feeling awkward',
    'de': 'Ich kann neben ihm schweigen, ohne dass es unangenehm wird',
    'fr': 'Je peux me taire à côté de lui sans gêne',
    'es': 'Puedo estar en silencio a su lado sin incomodidad',
    'it': 'Posso stare in silenzio accanto a lui senza disagio',
    'pt': 'Consigo ficar em silêncio ao lado dele sem constrangimento',
  },
  'love_q7': {
    'ru': 'Я говорю о том, что меня задело, а не коплю',
    'en': 'I say what hurt me instead of storing it up',
    'de': 'Ich spreche aus, was mich verletzt hat, statt es anzusammeln',
    'fr': 'Je dis ce qui m’a blessé au lieu de l’accumuler',
    'es': 'Digo lo que me dolió en vez de acumularlo',
    'it': 'Dico ciò che mi ha ferito invece di accumularlo',
    'pt': 'Falo o que me magoou em vez de acumular',
  },

  // ── Благодарность ────────────────────────────────────────────────────────
  'love_q8': {
    'ru': 'Я говорю спасибо за мелочи, которые он делает каждый день',
    'en': 'I say thank you for the small things they do every day',
    'de': 'Ich sage Danke für die Kleinigkeiten, die er jeden Tag tut',
    'fr': 'Je dis merci pour les petites choses qu’il fait chaque jour',
    'es': 'Doy las gracias por las pequeñas cosas que hace cada día',
    'it': 'Dico grazie per le piccole cose che fa ogni giorno',
    'pt': 'Agradeço pelas pequenas coisas que ele faz todo dia',
  },
  'love_q9': {
    'ru': 'Я замечаю, что он меняется ради меня',
    'en': 'I notice the ways they change for me',
    'de': 'Ich merke, dass er sich für mich verändert',
    'fr': 'Je remarque qu’il change pour moi',
    'es': 'Noto que cambia por mí',
    'it': 'Noto che cambia per me',
    'pt': 'Percebo que ele muda por mim',
  },
  'love_q10': {
    'ru': 'Мне легко сказать вслух, за что я его ценю',
    'en': 'It is easy for me to say out loud what I value in them',
    'de': 'Es fällt mir leicht auszusprechen, wofür ich ihn schätze',
    'fr': 'Il m’est facile de dire à voix haute ce que j’apprécie chez lui',
    'es': 'Me resulta fácil decir en voz alta lo que valoro de él',
    'it': 'Mi è facile dire ad alta voce cosa apprezzo di lui',
    'pt': 'É fácil dizer em voz alta o que valorizo nele',
  },

  // ── Взаимность ───────────────────────────────────────────────────────────
  'love_q11': {
    'ru': 'Мы делим бытовые дела так, что никто не тянет всё',
    'en': 'We split chores so that no one carries everything',
    'de': 'Wir teilen den Haushalt so, dass niemand alles trägt',
    'fr': 'On partage les tâches pour que personne ne porte tout',
    'es': 'Repartimos las tareas para que nadie cargue con todo',
    'it': 'Ci dividiamo le faccende così nessuno porta tutto',
    'pt': 'Dividimos as tarefas para ninguém carregar tudo',
  },
  'love_q12': {
    'ru': 'Мои планы учитывают его планы',
    'en': 'My plans take their plans into account',
    'de': 'Meine Pläne berücksichtigen seine Pläne',
    'fr': 'Mes projets tiennent compte des siens',
    'es': 'Mis planes tienen en cuenta los suyos',
    'it': 'I miei piani tengono conto dei suoi',
    'pt': 'Meus planos levam em conta os dele',
  },
  'love_q13': {
    'ru': 'Он получает от меня столько же внимания, сколько я от него',
    'en': 'They get as much attention from me as I get from them',
    'de': 'Er bekommt von mir so viel Aufmerksamkeit wie ich von ihm',
    'fr': 'Il reçoit de moi autant d’attention que j’en reçois de lui',
    'es': 'Recibe de mí tanta atención como yo de él',
    'it': 'Riceve da me tanta attenzione quanta ne ricevo io',
    'pt': 'Ele recebe de mim tanta atenção quanto eu dele',
  },
  'love_q14': {
    'ru': 'Когда мы спорим, я ищу решение, а не победу',
    'en': 'When we argue, I look for a solution, not a win',
    'de': 'Wenn wir streiten, suche ich eine Lösung, keinen Sieg',
    'fr': 'Quand on se dispute, je cherche une solution, pas la victoire',
    'es': 'Cuando discutimos, busco una solución, no ganar',
    'it': 'Quando litighiamo, cerco una soluzione, non la vittoria',
    'pt': 'Quando discutimos, busco solução, não vitória',
  },

  // ── Страсть ──────────────────────────────────────────────────────────────
  'love_q15': {
    'ru': 'Мне хочется прикасаться к нему без повода',
    'en': 'I want to touch them for no reason',
    'de': 'Ich möchte ihn ohne Anlass berühren',
    'fr': 'J’ai envie de le toucher sans raison',
    'es': 'Quiero tocarlo sin motivo',
    'it': 'Ho voglia di toccarlo senza motivo',
    'pt': 'Tenho vontade de tocá-lo sem motivo',
  },
  'love_q16': {
    'ru': 'Я жду наших встреч, даже когда мы виделись вчера',
    'en': 'I look forward to seeing them even if we met yesterday',
    'de': 'Ich freue mich auf unsere Treffen, auch wenn wir uns gestern sahen',
    'fr': 'J’attends nos retrouvailles même si on s’est vus hier',
    'es': 'Espero nuestros encuentros aunque nos vimos ayer',
    'it': 'Aspetto i nostri incontri anche se ci siamo visti ieri',
    'pt': 'Espero nossos encontros mesmo tendo nos visto ontem',
  },
  'love_q17': {
    'ru': 'Я придумываю, чем его удивить',
    'en': 'I think up ways to surprise them',
    'de': 'Ich überlege mir, womit ich ihn überraschen kann',
    'fr': 'J’invente des façons de le surprendre',
    'es': 'Pienso cómo sorprenderlo',
    'it': 'Penso a come sorprenderlo',
    'pt': 'Penso em como surpreendê-lo',
  },

  // ── Принятие ─────────────────────────────────────────────────────────────
  'love_q18': {
    'ru': 'Мне не хочется его переделывать',
    'en': 'I do not want to remake them',
    'de': 'Ich will ihn nicht ändern',
    'fr': 'Je n’ai pas envie de le changer',
    'es': 'No quiero cambiarlo',
    'it': 'Non voglio cambiarlo',
    'pt': 'Não quero mudá-lo',
  },
  'love_q19': {
    'ru': 'Я спокойно отношусь к его увлечениям, которых не разделяю',
    'en': 'I am fine with their hobbies I do not share',
    'de': 'Seine Hobbys, die ich nicht teile, stören mich nicht',
    'fr': 'Ses passions que je ne partage pas ne me dérangent pas',
    'es': 'Sus aficiones que no comparto no me molestan',
    'it': 'I suoi hobby che non condivido non mi disturbano',
    'pt': 'Seus hobbies que não compartilho não me incomodam',
  },
  'love_q20': {
    'ru': 'Его слабости не портят моего отношения к нему',
    'en': 'Their weaknesses do not spoil how I feel about them',
    'de': 'Seine Schwächen ändern nichts an meinen Gefühlen',
    'fr': 'Ses faiblesses ne gâchent pas ce que je ressens',
    'es': 'Sus debilidades no estropean lo que siento',
    'it': 'Le sue debolezze non rovinano ciò che provo',
    'pt': 'Suas fraquezas não estragam o que sinto',
  },

  // ── Экран и карточка ─────────────────────────────────────────────────────
  'love_title': {
    'ru': 'Умение любить',
    'en': 'How you love',
    'de': 'Wie du liebst',
    'fr': 'Ta façon d’aimer',
    'es': 'Cómo amas',
    'it': 'Come ami',
    'pt': 'Como você ama',
  },
  'love_intro': {
    'ru':
        'Двадцать утверждений о себе. Ответы складываются в шесть граней '
        'и в одну фигуру — она вытянута туда, где отношения сильнее.',
    'en':
        'Twenty statements about yourself. The answers add up to six '
        'facets and one shape, stretched where your bond is stronger.',
    'de':
        'Zwanzig Aussagen über dich. Die Antworten ergeben sechs Facetten '
        'und eine Figur, die sich dorthin dehnt, wo eure Beziehung stärker ist.',
    'fr':
        'Vingt affirmations sur toi. Les réponses forment six facettes et '
        'une figure, étirée là où votre lien est plus fort.',
    'es':
        'Veinte afirmaciones sobre ti. Las respuestas forman seis facetas y '
        'una figura, estirada donde vuestro vínculo es más fuerte.',
    'it':
        'Venti affermazioni su di te. Le risposte formano sei sfaccettature '
        'e una figura, tesa dove il vostro legame è più forte.',
    'pt':
        'Vinte afirmações sobre você. As respostas formam seis facetas e '
        'uma figura, esticada onde o vínculo é mais forte.',
  },
  'love_start': {
    'ru': 'Начать · две минуты',
    'en': 'Start · two minutes',
    'de': 'Starten · zwei Minuten',
    'fr': 'Commencer · deux minutes',
    'es': 'Empezar · dos minutos',
    'it': 'Inizia · due minuti',
    'pt': 'Começar · dois minutos',
  },
  // {n} — номер вопроса, {total} — сколько их всего.
  'love_progress': {
    'ru': 'Вопрос {n} из {total}',
    'en': 'Question {n} of {total}',
    'de': 'Frage {n} von {total}',
    'fr': 'Question {n} sur {total}',
    'es': 'Pregunta {n} de {total}',
    'it': 'Domanda {n} di {total}',
    'pt': 'Pergunta {n} de {total}',
  },
  'love_you': {
    'ru': 'Вы',
    'en': 'You',
    'de': 'Du',
    'fr': 'Toi',
    'es': 'Tú',
    'it': 'Tu',
    'pt': 'Você',
  },
  'love_partner': {
    'ru': 'Партнёр',
    'en': 'Partner',
    'de': 'Partner',
    'fr': 'Partenaire',
    'es': 'Pareja',
    'it': 'Partner',
    'pt': 'Par',
  },
  // {facet} — название грани.
  'love_strongest': {
    'ru': 'Держится на грани «{facet}»',
    'en': 'Strongest facet: {facet}',
    'de': 'Stärkste Facette: {facet}',
    'fr': 'Facette la plus forte : {facet}',
    'es': 'Faceta más fuerte: {facet}',
    'it': 'Sfaccettatura più forte: {facet}',
    'pt': 'Faceta mais forte: {facet}',
  },
  'love_saving': {
    'ru': 'Сохраняем…',
    'en': 'Saving…',
    'de': 'Wird gespeichert…',
    'fr': 'Enregistrement…',
    'es': 'Guardando…',
    'it': 'Salvataggio…',
    'pt': 'Salvando…',
  },
  'love_retake': {
    'ru': 'Пройти заново',
    'en': 'Take it again',
    'de': 'Noch einmal machen',
    'fr': 'Refaire le test',
    'es': 'Hacerlo de nuevo',
    'it': 'Rifai il test',
    'pt': 'Fazer de novo',
  },
  'love_six_facets': {
    'ru': 'Шесть граней',
    'en': 'Six facets',
    'de': 'Sechs Facetten',
    'fr': 'Six facettes',
    'es': 'Seis facetas',
    'it': 'Sei sfaccettature',
    'pt': 'Seis facetas',
  },
  'love_closest': {
    'ru': 'Где сошлись',
    'en': 'Closest',
    'de': 'Größte Nähe',
    'fr': 'Point commun',
    'es': 'Donde coincidís',
    'it': 'Dove coincidete',
    'pt': 'Onde vocês coincidem',
  },
  'love_widest': {
    'ru': 'Где разошлись',
    'en': 'Widest gap',
    'de': 'Größter Abstand',
    'fr': 'Plus grand écart',
    'es': 'Donde más difieren',
    'it': 'Dove divergete',
    'pt': 'Onde mais diferem',
  },
  'love_not_saved': {
    'ru': 'Результат не сохранился — попробуйте пройти ещё раз позже',
    'en': 'Result was not saved — try again a bit later',
    'de': 'Das Ergebnis wurde nicht gespeichert — versuche es später erneut',
    'fr': 'Le résultat n’a pas été enregistré — réessaie un peu plus tard',
    'es': 'El resultado no se guardó — inténtalo de nuevo más tarde',
    'it': 'Il risultato non è stato salvato — riprova più tardi',
    'pt': 'O resultado não foi salvo — tente de novo mais tarde',
  },
  // {who} — имя партнёра или слово «партнёр».
  'love_partner_took': {
    'ru': '{who} прошёл «Умение любить»',
    'en': '{who} took “How you love”',
    'de': '{who} hat „Wie du liebst“ gemacht',
    'fr': '{who} a fait « Ta façon d’aimer »',
    'es': '{who} hizo «Cómo amas»',
    'it': '{who} ha fatto «Come ami»',
    'pt': '{who} fez “Como você ama”',
  },
  'love_take': {
    'ru': 'Пройти',
    'en': 'Take it',
    'de': 'Machen',
    'fr': 'Le faire',
    'es': 'Hacerlo',
    'it': 'Fallo',
    'pt': 'Fazer',
  },
  'love_hide': {
    'ru': 'Скрыть',
    'en': 'Hide',
    'de': 'Ausblenden',
    'fr': 'Masquer',
    'es': 'Ocultar',
    'it': 'Nascondi',
    'pt': 'Ocultar',
  },
  'love_card_hint': {
    'ru': 'Его фигура откроется, когда ответите сами. Две минуты.',
    'en': 'Their shape opens once you answer too. Two minutes.',
    'de': 'Seine Figur öffnet sich, sobald du selbst antwortest. Zwei Minuten.',
    'fr': 'Sa figure s’ouvre quand tu réponds aussi. Deux minutes.',
    'es': 'Su figura se abre cuando respondas tú. Dos minutos.',
    'it': 'La sua figura si apre quando rispondi anche tu. Due minuti.',
    'pt': 'A figura dele abre quando você também responder. Dois minutos.',
  },
};
