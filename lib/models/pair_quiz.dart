import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

/// Тесты для пары (06.11.2026, опрос в канале: 79% за новые тесты).
///
/// Три теста, каждый проходит человек сам, общий итог пары виден, когда
/// ответили оба (`pair_quizzes` на сервере):
///   * «Язык любви» — пять языков, десять пар «что приятнее»;
///   * «Тип привязанности» — две шкалы (тревога, избегание), четыре типа;
///   * «Какое ты животное» — восемь зверей, восемь вопросов.
///
/// Вопросы и тексты свои. Языки — русский, английский и украинский, остальные
/// получают английский: контента много, а люди приложения в основном
/// русскоязычные.
enum QuizKind { lang, attach, animal }

/// Типы результата каждого теста, порядок задаёт и разбор ничьей.
const Map<QuizKind, List<String>> kQuizTypes = {
  QuizKind.lang: ['words', 'time', 'gifts', 'acts', 'touch'],
  QuizKind.attach: ['secure', 'anxious', 'avoidant', 'fearful'],
  QuizKind.animal: ['cat', 'dog', 'hedgehog', 'otter', 'fox', 'bear', 'penguin', 'koala'],
};

class QuizOption {
  const QuizOption(this.text, this.score);
  final String text;

  /// Чему ответ добавляет: тип → очки. У привязанности — ось (`anx`/`avo`)
  /// и значение 1…5 с учётом обратных утверждений.
  final Map<String, int> score;
}

class QuizQuestion {
  const QuizQuestion(this.key, this.text, this.options);
  final String key;
  final String text;
  final List<QuizOption> options;
}

class QuizResult {
  const QuizResult({required this.kind, required this.type, required this.scores});

  final QuizKind kind;
  final String type;

  /// Доли 0…1: у языков и зверей — по типам, у привязанности — `anx` и `avo`.
  final Map<String, double> scores;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'type': type, 'scores': scores};

  static QuizResult? fromJson(Map<String, dynamic> json) {
    final kind = QuizKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) return null;
    final type = json['type'];
    if (type is! String || !kQuizTypes[kind]!.contains(type)) return null;
    final raw = json['scores'];
    return QuizResult(
      kind: kind,
      type: type,
      scores: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      },
    );
  }
}

/// Id записи: один на человека, пару и тест — повтор теста правит ту же.
String pairQuizRecordId(String groupId, String uid, QuizKind kind) {
  final digest = sha256.convert(utf8.encode('$groupId:$uid:${kind.name}')).toString();
  return 'pq${digest.substring(0, 13)}';
}

// ── тексты ──────────────────────────────────────────────────────────────────

String _t(Map<String, String> m, String lang) => m[lang] ?? m['en'] ?? m['ru'] ?? '';

Map<String, String> _m(String ru, String en, String uk) => {'ru': ru, 'en': en, 'uk': uk};

final Map<QuizKind, Map<String, String>> _titles = {
  QuizKind.lang: _m('Язык любви', 'Love language', 'Мова кохання'),
  QuizKind.attach: _m('Тип привязанности', 'Attachment style', 'Тип прив’язаності'),
  QuizKind.animal: _m('Какое ты животное', 'Which animal are you', 'Яка ти тварина'),
};

final Map<QuizKind, Map<String, String>> _intros = {
  QuizKind.lang: _m(
    'Десять пар. В каждой выберите то, что вам приятнее получить от партнёра. Думать долго не надо.',
    'Ten pairs. In each, pick what you would rather receive from your partner. Go with your gut.',
    'Десять пар. У кожній оберіть те, що вам приємніше отримати від партнера. Довго не думайте.',
  ),
  QuizKind.attach: _m(
    'Двенадцать утверждений о том, как вы ведёте себя в близких отношениях. Отвечайте, как есть, а не как хотелось бы. Это не психологическая оценка.',
    'Twelve statements about how you act in a close relationship. Answer as things are, not as you wish they were. This is not a psychological assessment.',
    'Дванадцять тверджень про те, як ви поводитеся в близьких стосунках. Відповідайте як є, а не як хотілося б. Це не психологічна оцінка.',
  ),
  QuizKind.animal: _m(
    'Восемь вопросов о вас в паре. В конце узнаете своего зверя, а когда ответит партнёр — ваш общий дуэт.',
    'Eight questions about you as a partner. You get your animal at the end, and your duo once your partner answers.',
    'Вісім питань про вас у парі. Наприкінці дізнаєтеся свого звіра. Коли відповість партнер, з’явиться ваш спільний дует.',
  ),
};

final Map<QuizKind, Map<String, String>> _hints = {
  QuizKind.lang: _m('Как вам приятнее получать любовь', 'How you like to receive love', 'Як вам приємніше отримувати любов'),
  QuizKind.attach: _m('Как вы ведёте себя в близости', 'How you behave when close', 'Як ви поводитеся в близькості'),
  QuizKind.animal: _m('Ваш зверь и ваш дуэт', 'Your animal and your duo', 'Ваш звір і ваш дует'),
};

/// Подписи экрана теста.
final Map<String, Map<String, String>> _ui = {
  'start': _m('Начать', 'Start', 'Почати'),
  'step': _m('Вопрос {0} из {1}', 'Question {0} of {1}', 'Питання {0} з {1}'),
  'mine': _m('Ваш результат', 'Your result', 'Ваш результат'),
  'theirs': _m('Результат партнёра', 'Your partner’s result', 'Результат партнера'),
  'together': _m('Вместе', 'Together', 'Разом'),
  'wait': _m('Партнёр ещё не прошёл тест. Когда пройдёт, здесь появится ваш общий итог.',
      'Your partner hasn’t taken the test yet. Once they do, your shared result shows up here.',
      'Партнер ще не пройшов тест. Щойно пройде, тут з’явиться ваш спільний підсумок.'),
  'again': _m('Пройти заново', 'Take it again', 'Пройти знову'),
  'anx': _m('Тревога', 'Anxiety', 'Тривога'),
  'avo': _m('Избегание', 'Avoidance', 'Уникання'),
  'section': _m('Тесты для пары', 'Tests for two', 'Тести для пари'),
  'done': _m('Пройден', 'Done', 'Пройдено'),
  'note': _m('Это не психологическая оценка, а повод поговорить.', 'This is not a psychological assessment, just a reason to talk.',
      'Це не психологічна оцінка, а привід поговорити.'),
};

String quizUi(String key, String lang) => _t(_ui[key] ?? const {}, lang);

String quizHint(QuizKind kind, String lang) => _t(_hints[kind]!, lang);

String quizTitle(QuizKind kind, String lang) => _t(_titles[kind]!, lang);
String quizIntro(QuizKind kind, String lang) => _t(_intros[kind]!, lang);

// Язык любви: десять пар, каждая пара языков по разу.
final List<(String, Map<String, String>, String, Map<String, String>)> _langPairs = [
  ('words', _m('Партнёр говорит, как гордится мной', 'My partner says how proud they are of me', 'Партнер каже, як пишається мною'),
   'time', _m('Партнёр откладывает телефон и весь вечер только со мной', 'My partner puts the phone away and spends the whole evening with me', 'Партнер відкладає телефон і весь вечір тільки зі мною')),
  ('words', _m('Записка с тёплыми словами', 'A note with warm words', 'Записка з теплими словами'),
   'gifts', _m('Маленький подарок без повода', 'A small gift for no reason', 'Маленький подарунок без приводу')),
  ('words', _m('Услышать «я тебя люблю» посреди дня', 'Hearing “I love you” in the middle of the day', 'Почути «я тебе кохаю» посеред дня'),
   'acts', _m('Партнёр сам делает дело, которое я откладываю', 'My partner takes care of a chore I keep putting off', 'Партнер сам робить справу, яку я відкладаю')),
  ('words', _m('Комплимент при друзьях', 'A compliment in front of friends', 'Комплімент при друзях'),
   'touch', _m('Объятие сзади, когда я не жду', 'A hug from behind when I don’t expect it', 'Обійми ззаду, коли я не чекаю')),
  ('time', _m('Прогулка вдвоём без всяких планов', 'A walk together with no plans', 'Прогулянка удвох без жодних планів'),
   'gifts', _m('Сувенир из поездки: значит, партнёр там думал обо мне', 'A souvenir from a trip: proof they thought of me there', 'Сувенір з поїздки: отже, партнер там думав про мене')),
  ('time', _m('Долгий разговор перед сном', 'A long talk before bed', 'Довга розмова перед сном'),
   'acts', _m('Партнёр готовит завтрак, пока я сплю', 'My partner makes breakfast while I sleep', 'Партнер готує сніданок, поки я сплю')),
  ('time', _m('Смотреть кино и обсуждать каждую сцену', 'Watching a movie and talking about every scene', 'Дивитися кіно й обговорювати кожну сцену'),
   'touch', _m('Просто лежать рядом в обнимку', 'Just lying close, cuddling', 'Просто лежати поруч в обіймах')),
  ('gifts', _m('Подарок, который партнёр долго выбирал', 'A gift my partner took ages to choose', 'Подарунок, який партнер довго обирав'),
   'acts', _m('Партнёр приезжает за мной, когда у меня нет сил', 'My partner picks me up when I have no energy left', 'Партнер приїжджає по мене, коли в мене немає сил')),
  ('gifts', _m('Цветы просто так', 'Flowers just because', 'Квіти просто так'),
   'touch', _m('Держаться за руки на улице', 'Holding hands on the street', 'Триматися за руки на вулиці')),
  ('acts', _m('Партнёр берёт на себя мои дела в тяжёлый день', 'My partner takes over my tasks on a hard day', 'Партнер бере на себе мої справи у важкий день'),
   'touch', _m('Массаж плеч после трудного дня', 'A shoulder rub after a long day', 'Масаж плечей після важкого дня')),
];

final Map<String, String> _langQ = _m('Что вам приятнее?', 'What would you rather have?', 'Що вам приємніше?');

// Привязанность: ось, обратное ли утверждение, текст.
final List<(String, bool, Map<String, String>)> _attachItems = [
  ('anx', false, _m('Я боюсь, что партнёр меня разлюбит', 'I worry my partner will stop loving me', 'Я боюся, що партнер мене розлюбить')),
  ('avo', false, _m('Мне трудно говорить партнёру о своих чувствах', 'It is hard for me to tell my partner how I feel', 'Мені важко говорити партнеру про свої почуття')),
  ('anx', false, _m('Если партнёр долго не отвечает, я начинаю переживать', 'If my partner takes long to reply, I start to worry', 'Якщо партнер довго не відповідає, я починаю хвилюватися')),
  ('avo', false, _m('Когда партнёр слишком близко, мне хочется отстраниться', 'When my partner gets very close, I want to pull away', 'Коли партнер надто близько, мені хочеться відсторонитися')),
  ('anx', false, _m('Мне нужно часто слышать, что меня любят', 'I need to hear often that I am loved', 'Мені треба часто чути, що мене кохають')),
  ('avo', true, _m('Мне легко просить партнёра о помощи', 'It is easy for me to ask my partner for help', 'Мені легко просити партнера про допомогу')),
  ('anx', false, _m('Я волнуюсь, что партнёру будет лучше с кем-то другим', 'I worry my partner would be happier with someone else', 'Я хвилююся, що партнерові буде краще з кимось іншим')),
  ('avo', false, _m('Проблемы я предпочитаю решать в одиночку', 'I prefer to deal with problems on my own', 'Проблеми я волію розв’язувати сам на сам')),
  ('anx', true, _m('Я спокойно отношусь, когда партнёр проводит время без меня', 'I feel fine when my partner spends time without me', 'Я спокійно ставлюся, коли партнер проводить час без мене')),
  ('avo', true, _m('Мне комфортно быть с партнёром очень близко', 'I feel comfortable being very close to my partner', 'Мені комфортно бути з партнером дуже близько')),
  ('anx', false, _m('Ссора надолго выбивает меня из колеи', 'A fight throws me off balance for a long time', 'Сварка надовго вибиває мене з колії')),
  ('avo', false, _m('В ссоре мне проще уйти, чем разговаривать', 'In a fight it is easier for me to walk away than to talk', 'У сварці мені простіше піти, ніж говорити')),
];

final List<Map<String, String>> _likert = [
  _m('Совсем нет', 'Not at all', 'Зовсім ні'),
  _m('Скорее нет', 'Rather not', 'Радше ні'),
  _m('Иногда', 'Sometimes', 'Іноді'),
  _m('Скорее да', 'Rather yes', 'Радше так'),
  _m('Точно да', 'Definitely', 'Точно так'),
];

// Животное: восемь вопросов, у каждого четыре зверя (каждый зверь — 4 раза).
final List<(Map<String, String>, List<(String, Map<String, String>)>)> _animalQs = [
  (_m('Идеальный вечер вдвоём', 'Your ideal evening together', 'Ідеальний вечір удвох'), [
    ('cat', _m('Каждый своим делом, но рядом', 'Each doing our own thing, but close', 'Кожен своєю справою, але поруч')),
    ('dog', _m('Куда угодно, лишь бы вместе', 'Anywhere, as long as we are together', 'Куди завгодно, аби разом')),
    ('fox', _m('Внезапное приключение', 'A spontaneous adventure', 'Раптова пригода')),
    ('koala', _m('Плед, сериал и сон', 'A blanket, a series and sleep', 'Плед, серіал і сон')),
  ]),
  (_m('Как вы показываете любовь', 'How you show love', 'Як ви показуєте любов'), [
    ('otter', _m('Всё время держу за руку', 'I hold their hand all the time', 'Весь час тримаю за руку')),
    ('bear', _m('Крепко обнимаю', 'I hug them tight', 'Міцно обіймаю')),
    ('hedgehog', _m('Ворчу, но делаю для партнёра всё', 'I grumble, but I do everything for them', 'Буркочу, але роблю для партнера все')),
    ('penguin', _m('Дарю маленькие находки', 'I bring little finds', 'Дарую маленькі знахідки')),
  ]),
  (_m('После ссоры вы…', 'After a fight you…', 'Після сварки ви…'), [
    ('cat', _m('Делаю вид, что мне всё равно', 'Act like I don’t care', 'Вдаю, що мені байдуже')),
    ('dog', _m('Сразу иду мириться', 'Go to make up right away', 'Одразу йду миритися')),
    ('hedgehog', _m('Мне нужно время, чтобы отойти', 'Need time to cool off', 'Мені треба час, щоб відійти')),
    ('fox', _m('Шучу, чтобы разрядить обстановку', 'Make a joke to break the tension', 'Жартую, щоб розрядити атмосферу')),
  ]),
  (_m('Переписка днём', 'Texting during the day', 'Листування вдень'), [
    ('otter', _m('Пишу каждый час', 'I text every hour', 'Пишу щогодини')),
    ('cat', _m('Отвечаю, когда захочу', 'I reply when I feel like it', 'Відповідаю, коли захочу')),
    ('bear', _m('Напоминаю поесть', 'I remind them to eat', 'Нагадую поїсти')),
    ('koala', _m('Стикер — и снова дремать', 'A sticker, then back to napping', 'Стікер — і знову дрімати')),
  ]),
  (_m('В компании друзей', 'Out with friends', 'У компанії друзів'), [
    ('fox', _m('Душа компании', 'The life of the party', 'Душа компанії')),
    ('hedgehog', _m('Держусь своих, чужим не открываюсь', 'I stick to my people, strangers don’t get in', 'Тримаюся своїх, чужим не відкриваюся')),
    ('dog', _m('Всем радуюсь', 'Happy to see everyone', 'Усім радію')),
    ('penguin', _m('Ищу глазами своего человека', 'My eyes keep finding my person', 'Шукаю очима свою людину')),
  ]),
  (_m('Партнёру грустно', 'Your partner is sad', 'Партнерові сумно'), [
    ('bear', _m('Обниму и не отпущу', 'Hug them and not let go', 'Обійму й не відпущу')),
    ('otter', _m('Возьму за руку и буду рядом', 'Hold their hand and stay close', 'Візьму за руку й буду поруч')),
    ('penguin', _m('Принесу что-то вкусное', 'Bring something tasty', 'Принесу щось смачне')),
    ('koala', _m('Укутаю в плед и лягу рядом', 'Wrap them in a blanket and lie next to them', 'Закутаю в плед і ляжу поруч')),
  ]),
  (_m('Что главное в отношениях', 'What matters most in a relationship', 'Що головне в стосунках'), [
    ('penguin', _m('Верность', 'Loyalty', 'Вірність')),
    ('dog', _m('Радость', 'Joy', 'Радість')),
    ('bear', _m('Надёжность', 'Reliability', 'Надійність')),
    ('fox', _m('Искра', 'A spark', 'Іскра')),
  ]),
  (_m('Утро выходного', 'A weekend morning', 'Ранок вихідного'), [
    ('koala', _m('Спать до обеда', 'Sleep till noon', 'Спати до обіду')),
    ('hedgehog', _m('Тихий завтрак без разговоров', 'A quiet breakfast, no talking', 'Тихий сніданок без розмов')),
    ('otter', _m('Валяться в обнимку', 'Lie around cuddling', 'Валятися в обіймах')),
    ('cat', _m('Кофе и немного тишины', 'Coffee and a bit of quiet', 'Кава й трохи тиші')),
  ]),
];

List<QuizQuestion> quizQuestions(QuizKind kind, String lang) => switch (kind) {
      QuizKind.lang => [
          for (var i = 0; i < _langPairs.length; i++)
            QuizQuestion('lang_$i', _t(_langQ, lang), [
              QuizOption(_t(_langPairs[i].$2, lang), {_langPairs[i].$1: 1}),
              QuizOption(_t(_langPairs[i].$4, lang), {_langPairs[i].$3: 1}),
            ]),
        ],
      QuizKind.attach => [
          for (var i = 0; i < _attachItems.length; i++)
            QuizQuestion('attach_$i', _t(_attachItems[i].$3, lang), [
              for (var v = 0; v < 5; v++)
                QuizOption(_t(_likert[v], lang), {
                  _attachItems[i].$1: _attachItems[i].$2 ? 5 - v : v + 1,
                }),
            ]),
        ],
      QuizKind.animal => [
          for (var i = 0; i < _animalQs.length; i++)
            QuizQuestion('animal_$i', _t(_animalQs[i].$1, lang), [
              for (final (key, text) in _animalQs[i].$2) QuizOption(_t(text, lang), {key: 1}),
            ]),
        ],
    };

/// Ось утверждения привязанности (`anx` или `avo`) — для тестов и подсказок.
String attachItemAxis(QuizQuestion q) => q.options.first.score.keys.single;

/// Обратное утверждение: согласие с ним снижает шкалу.
bool attachItemReversed(QuizQuestion q) => q.options.first.score.values.single == 5;

/// Подсчёт. [answers] — индекс выбранного варианта на каждый вопрос по
/// порядку; лишние, недостающие и кривые ответы пропускаются.
QuizResult scoreQuiz(QuizKind kind, List<int> answers) {
  final qs = quizQuestions(kind, 'en');
  final sums = <String, int>{};
  final counts = <String, int>{};
  for (var i = 0; i < qs.length && i < answers.length; i++) {
    final a = answers[i];
    if (a < 0 || a >= qs[i].options.length) continue;
    qs[i].options[a].score.forEach((k, v) => sums[k] = (sums[k] ?? 0) + v);
    for (final o in qs[i].options.first.score.keys) {
      counts[o] = (counts[o] ?? 0) + 1;
    }
  }
  if (kind == QuizKind.attach) {
    // Среднее по оси 1…5 → доля 0…1; порог — середина шкалы.
    double axis(String k) {
      final n = counts[k] ?? 0;
      return n == 0 ? 0.5 : ((sums[k] ?? 0) / n - 1) / 4;
    }
    final anx = axis('anx'), avo = axis('avo');
    final type = anx > 0.5
        ? (avo > 0.5 ? 'fearful' : 'anxious')
        : (avo > 0.5 ? 'avoidant' : 'secure');
    return QuizResult(kind: kind, type: type, scores: {'anx': anx, 'avo': avo});
  }
  final types = kQuizTypes[kind]!;
  // Сколько раз тип вообще встречался в вопросах — доля от возможного.
  final possible = <String, int>{};
  for (final q in qs) {
    for (final o in q.options) {
      for (final k in o.score.keys) {
        possible[k] = (possible[k] ?? 0) + 1;
      }
    }
  }
  var best = types.first;
  for (final t in types) {
    if ((sums[t] ?? 0) > (sums[best] ?? 0)) best = t;
  }
  return QuizResult(
    kind: kind,
    type: best,
    scores: {for (final t in types) t: (sums[t] ?? 0) / (possible[t] ?? 1)},
  );
}

// ── результаты ──────────────────────────────────────────────────────────────

final Map<String, (Map<String, String>, Map<String, String>)> _langTypes = {
  'words': (_m('Слова', 'Words', 'Слова'), _m(
    'Вам важно слышать любовь: признания, похвалу, тёплые сообщения. Одно «горжусь тобой» весит больше подарка.',
    'You need to hear love: confessions, praise, warm messages. One “I’m proud of you” outweighs a gift.',
    'Вам важливо чути любов: зізнання, похвалу, теплі повідомлення. Одне «пишаюся тобою» важить більше за подарунок.')),
  'time': (_m('Время вместе', 'Quality time', 'Час разом'), _m(
    'Любовь для вас — это внимание целиком: без телефона, вдвоём, хоть полчаса. Отменённые планы ранят сильнее, чем кажется.',
    'Love to you is undivided attention: phones down, just the two of you, even for half an hour. Cancelled plans hurt more than they seem to.',
    'Для вас любов означає увагу повністю: без телефона, удвох, хоч пів години. Скасовані плани ранять сильніше, ніж здається.')),
  'gifts': (_m('Подарки', 'Gifts', 'Подарунки'), _m(
    'Вам дорога не цена, а мысль: «увидел и вспомнил о тебе». Маленькая вещица без повода — лучшее признание.',
    'It is the thought, not the price: “I saw this and thought of you.” A small thing for no reason says it best.',
    'Вам дорога не ціна, а думка: «побачив і згадав про тебе». Маленька річ без приводу і є найкраще зізнання.')),
  'acts': (_m('Помощь делом', 'Acts of service', 'Допомога ділом'), _m(
    'Любовь вы видите в делах: сделать за вас дело, встретить, приготовить. Слова без дел вас не греют.',
    'To you, love is help: doing a chore for you, picking you up, cooking. Words without action leave you cold.',
    'Любов ви бачите у справах: зробити справу за вас, зустріти, приготувати. Слова без справ вас не гріють.')),
  'touch': (_m('Прикосновения', 'Physical touch', 'Дотики'), _m(
    'Вам нужна близость телом: объятия, рука в руке, голова на плече. Без прикосновений любовь кажется далёкой.',
    'You need closeness: hugs, holding hands, a head on your shoulder. Without touch, love feels far away.',
    'Вам потрібна близькість: обійми, рука в руці, голова на плечі. Без дотиків любов здається далекою.')),
};

/// Как порадовать человека с этим языком — для общего итога пары.
final Map<String, Map<String, String>> _langTip = {
  'words': _m('пишите тёплое посреди дня и говорите вслух, за что цените', 'text something warm midday and say out loud what you value', 'пишіть тепле посеред дня й кажіть уголос, за що цінуєте'),
  'time': _m('отложите телефон и выделите вечер только для двоих', 'put the phone away and keep an evening just for two', 'відкладіть телефон і виділіть вечір тільки для двох'),
  'gifts': _m('приносите мелочи без повода: шоколадку, открытку, находку', 'bring small things for no reason: chocolate, a card, a find', 'приносьте дрібниці без приводу: шоколадку, листівку, знахідку'),
  'acts': _m('возьмите на себя дело, которое давно висит', 'take one long-pending chore off their plate', 'візьміть на себе справу, яка давно висить'),
  'touch': _m('чаще обнимайте и берите за руку просто так', 'hug more and take their hand just because', 'частіше обіймайте й беріть за руку просто так'),
};

final Map<String, (Map<String, String>, Map<String, String>)> _attachTypes = {
  'secure': (_m('Надёжный', 'Secure', 'Надійний'), _m(
    'Вы спокойно сближаетесь и спокойно отпускаете. Ссору видите как задачу, а не как конец света.',
    'You get close easily and let go easily. A fight is a problem to solve, not the end of the world.',
    'Ви спокійно зближуєтеся й спокійно відпускаєте. Сварку бачите як задачу, а не як кінець світу.')),
  'anxious': (_m('Тревожный', 'Anxious', 'Тривожний'), _m(
    'Вы сильно привязываетесь и боитесь потерять. Молчание партнёра легко читается как беда.',
    'You attach deeply and fear losing it. A partner’s silence easily reads as trouble.',
    'Ви сильно прив’язуєтеся й боїтеся втратити. Мовчання партнера легко читається як біда.')),
  'avoidant': (_m('Избегающий', 'Avoidant', 'Уникаючий'), _m(
    'Вы цените свободу и тяжело открываетесь. Когда близости слишком много, хочется отойти и выдохнуть.',
    'You value freedom and open up slowly. When closeness gets too much, you want to step back and breathe.',
    'Ви цінуєте свободу й важко відкриваєтеся. Коли близькості забагато, хочеться відійти й видихнути.')),
  'fearful': (_m('Смешанный', 'Fearful', 'Змішаний'), _m(
    'Хочется близости, но она же и пугает. Вы то тянетесь к партнёру, то закрываетесь.',
    'You want closeness, yet it scares you. You reach out, then shut down.',
    'Хочеться близькості, але вона ж і лякає. Ви то тягнетеся до партнера, то закриваєтеся.')),
};

/// Что помогает человеку с этим типом — для общего итога пары.
final Map<String, Map<String, String>> _attachNeed = {
  'secure': _m('прямо говорить о проблемах', 'talking about problems directly', 'прямо говорити про проблеми'),
  'anxious': _m('слышать, что всё хорошо, и не ждать ответа часами', 'hearing that all is well and not waiting hours for a reply', 'чути, що все добре, і не чекати відповіді годинами'),
  'avoidant': _m('время наедине с собой без обид', 'time alone without hurt feelings', 'час наодинці з собою без образ'),
  'fearful': _m('мягкость и предсказуемость', 'gentleness and predictability', 'м’якість і передбачуваність'),
};

final Map<String, (Map<String, String>, Map<String, String>)> _animalTypes = {
  'cat': (_m('Кот', 'Cat', 'Кіт'), _m('Любит по-своему и на своих условиях. Зато если выбрал вас, то всерьёз.', 'Loves in their own way, on their own terms. But once they choose you, it’s for real.', 'Любить по-своєму й на своїх умовах. Зате якщо обрав вас, то всерйоз.')),
  'dog': (_m('Пёс', 'Dog', 'Пес'), _m('Встречает у двери, радуется каждой минуте вместе и не умеет долго дуться.', 'Greets you at the door, loves every minute together and can’t stay mad for long.', 'Зустрічає біля дверей, радіє кожній хвилині разом і не вміє довго дутися.')),
  'hedgehog': (_m('Ёж', 'Hedgehog', 'Їжак'), _m('Колючий снаружи и мягкий внутри. Чужих держит на расстоянии, а своим доверяет целиком.', 'Prickly outside, soft inside. Keeps strangers at a distance and trusts their own completely.', 'Колючий ззовні й м’який усередині. Чужих тримає на відстані, а своїм довіряє повністю.')),
  'otter': (_m('Выдра', 'Otter', 'Видра'), _m('Держится за лапку даже во сне. Нежность для вас — обычное состояние.', 'Holds hands even while asleep. Tenderness is your default state.', 'Тримається за лапку навіть уві сні. Ніжність для вас — звичайний стан.')),
  'fox': (_m('Лиса', 'Fox', 'Лисиця'), _m('Игривая, хитрая и живая. С вами не бывает скучно, и вы это знаете.', 'Playful, clever and lively. Life with you is never boring, and you know it.', 'Грайлива, хитра й жива. З вами не буває нудно, і ви це знаєте.')),
  'bear': (_m('Медведь', 'Bear', 'Ведмідь'), _m('Надёжный, тёплый и сильный. За вас можно спрятаться от любой бури.', 'Reliable, warm and strong. Anyone can hide behind you from any storm.', 'Надійний, теплий і сильний. За вас можна сховатися від будь-якої бурі.')),
  'penguin': (_m('Пингвин', 'Penguin', 'Пінгвін'), _m('Выбирает одного человека на всю жизнь и на других не смотрит. Дарит самое лучшее, что нашёл.', 'Picks one person for life and never looks at anyone else. Gives the very best thing they found.', 'Обирає одну людину на все життя й на інших не дивиться. Дарує найкраще, що знайшов.')),
  'koala': (_m('Коала', 'Koala', 'Коала'), _m('Уют, сон и обнимашки. Рядом с вами отдыхают даже самые беспокойные.', 'Coziness, sleep and cuddles. Even the most restless relax next to you.', 'Затишок, сон і обійми. Поруч із вами відпочивають навіть найнеспокійніші.')),
};

/// Что зверь приносит в пару — для общего итога.
final Map<String, Map<String, String>> _animalBrings = {
  'cat': _m('свободу', 'freedom', 'свободу'),
  'dog': _m('радость', 'joy', 'радість'),
  'hedgehog': _m('защиту', 'protection', 'захист'),
  'otter': _m('нежность', 'tenderness', 'ніжність'),
  'fox': _m('искру', 'a spark', 'іскру'),
  'bear': _m('надёжность', 'reliability', 'надійність'),
  'penguin': _m('верность', 'loyalty', 'вірність'),
  'koala': _m('уют', 'coziness', 'затишок'),
};

/// Значок зверя на экране результата.
const Map<String, String> kAnimalEmoji = {
  'cat': '🐱', 'dog': '🐶', 'hedgehog': '🦔', 'otter': '🦦',
  'fox': '🦊', 'bear': '🐻', 'penguin': '🐧', 'koala': '🐨',
};

(Map<String, String>, Map<String, String>)? _typeEntry(QuizKind kind, String type) => switch (kind) {
      QuizKind.lang => _langTypes[type],
      QuizKind.attach => _attachTypes[type],
      QuizKind.animal => _animalTypes[type],
    };

String quizTypeTitle(QuizKind kind, String type, String lang) {
  final e = _typeEntry(kind, type);
  return e == null ? '' : _t(e.$1, lang);
}

String quizTypeText(QuizKind kind, String type, String lang) {
  final e = _typeEntry(kind, type);
  return e == null ? '' : _t(e.$2, lang);
}

/// Общий итог пары: [mine] — свой тип, [theirs] — тип партнёра.
String quizPairText(QuizKind kind, String mine, String theirs, String lang) {
  String pick(String ru, String en, String uk) => _t(_m(ru, en, uk), lang);
  switch (kind) {
    case QuizKind.lang:
      final tip = _t(_langTip[theirs]!, lang);
      if (mine == theirs) {
        return pick('Вы говорите на одном языке. Чтобы порадовать партнёра, $tip.',
            'You speak the same language. To make your partner happy, $tip.',
            'Ви говорите однією мовою. Щоб порадувати партнера, $tip.');
      }
      final their = quizTypeTitle(kind, theirs, lang);
      return pick('Языки у вас разные: партнёру нужнее «$their». Чтобы порадовать партнёра, $tip.',
          'Your languages differ: your partner needs “$their” more. To make them happy, $tip.',
          'Мови у вас різні: партнерові потрібніше «$their». Щоб порадувати партнера, $tip.');
    case QuizKind.attach:
      final a = _t(_attachNeed[mine]!, lang), b = _t(_attachNeed[theirs]!, lang);
      if (mine == theirs) {
        return pick('У вас один тип, вам обоим помогает $a.', 'You share a style: you both do well with $a.',
            'У вас один тип, вам обом допомагає $a.');
      }
      return pick('Вам помогает $a, а партнёру — $b. Скажите друг другу об этом вслух.',
          'You do well with $a, your partner with $b. Say it to each other out loud.',
          'Вам допомагає $a, а партнерові — $b. Скажіть про це одне одному вголос.');
    case QuizKind.animal:
      final a = _t(_animalBrings[mine]!, lang), b = _t(_animalBrings[theirs]!, lang);
      if (mine == theirs) {
        return pick('Два зверя одной породы: вы приносите в пару $a и понимаете друг друга без слов.',
            'Two of a kind: you both bring $a and understand each other without words.',
            'Два звірі однієї породи: ви приносите в пару $a й розумієте одне одного без слів.');
      }
      return pick('Вы приносите в пару $a, а партнёр — $b. Вместе выходит хороший дуэт.',
          'You bring $a to the couple, your partner brings $b. Together you make a good duo.',
          'Ви приносите в пару $a, а партнер — $b. Разом виходить гарний дует.');
  }
}
