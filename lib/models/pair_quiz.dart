import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

/// Тесты для пары (06.11.2026, опрос в канале: 79% за новые тесты).
///
/// Пять тестов по 15 вопросов, каждый проходит человек сам, общий итог пары
/// виден, когда ответили оба (`pair_quizzes` на сервере):
///   * «Язык любви» — пять языков, пары «что приятнее»;
///   * «Тип привязанности» — две шкалы (тревога, избегание), четыре типа;
///   * «Какое ты животное» — восемь зверей;
///   * «Как вы ссоритесь» — пять стилей спора, пары «что ближе»;
///   * «Насколько вы похожи» — «или-или» о себе, итог — процент совпадения.
///     Своего типа у человека нет, поэтому тип один (`done`), а в `scores`
///     лежат сами ответы: ключ вопроса → 0 или 1.
///
/// Вопросы и тексты свои. Языки — русский, английский и украинский, остальные
/// получают английский: контента много, а люди приложения в основном
/// русскоязычные.
enum QuizKind { lang, attach, animal, fight, alike }

/// Типы результата каждого теста, порядок задаёт и разбор ничьей.
const Map<QuizKind, List<String>> kQuizTypes = {
  QuizKind.lang: ['words', 'time', 'gifts', 'acts', 'touch'],
  QuizKind.attach: ['secure', 'anxious', 'avoidant', 'fearful'],
  QuizKind.animal: ['cat', 'dog', 'hedgehog', 'otter', 'fox', 'bear', 'penguin', 'koala'],
  QuizKind.fight: ['push', 'yield', 'avoid', 'trade', 'solve'],
  QuizKind.alike: ['done'],
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
  QuizKind.fight: _m('Как вы ссоритесь', 'How you argue', 'Як ви сваритеся'),
  QuizKind.alike: _m('Насколько вы похожи', 'How alike you are', 'Наскільки ви схожі'),
};

final Map<QuizKind, Map<String, String>> _intros = {
  QuizKind.lang: _m(
    'Пятнадцать пар. В каждой выберите то, что вам приятнее получить от партнёра. Думать долго не надо.',
    'Fifteen pairs. In each, pick what you would rather receive from your partner. Go with your gut.',
    'П’ятнадцять пар. У кожній оберіть те, що вам приємніше отримати від партнера. Довго не думайте.',
  ),
  QuizKind.attach: _m(
    'Пятнадцать утверждений о том, как вы ведёте себя в близких отношениях. Отвечайте, как есть, а не как хотелось бы. Это не психологическая оценка.',
    'Fifteen statements about how you act in a close relationship. Answer as things are, not as you wish they were. This is not a psychological assessment.',
    'П’ятнадцять тверджень про те, як ви поводитеся в близьких стосунках. Відповідайте як є, а не як хотілося б. Це не психологічна оцінка.',
  ),
  QuizKind.animal: _m(
    'Пятнадцать вопросов о вас в паре. В конце узнаете своего зверя, а когда ответит партнёр — ваш общий дуэт.',
    'Fifteen questions about you as a partner. You get your animal at the end, and your duo once your partner answers.',
    'П’ятнадцять питань про вас у парі. Наприкінці дізнаєтеся свого звіра. Коли відповість партнер, з’явиться ваш спільний дует.',
  ),
  QuizKind.fight: _m(
    'Пятнадцать пар. В каждой выберите, что больше похоже на вас в ссоре. Отвечайте честно: правильных ответов нет.',
    'Fifteen pairs. In each, pick what sounds more like you in a fight. Be honest: there are no right answers.',
    'П’ятнадцять пар. У кожній оберіть, що більше схоже на вас у сварці. Відповідайте чесно: правильних відповідей немає.',
  ),
  QuizKind.alike: _m(
    'Пятнадцать быстрых «или-или». Отвечайте о себе. Партнёру достанутся те же вопросы, а в конце вы увидите, на сколько процентов совпали и в чём разные.',
    'Fifteen quick either-or picks. Answer about yourself. Your partner gets the same questions, and at the end you’ll see your match score and where you differ.',
    'П’ятнадцять швидких «або-або». Відповідайте про себе. Партнерові дістануться ті самі питання, а наприкінці ви побачите, на скільки відсотків збіглися і в чому різні.',
  ),
};

final Map<QuizKind, Map<String, String>> _hints = {
  QuizKind.lang: _m('Как вам приятнее получать любовь', 'How you like to receive love', 'Як вам приємніше отримувати любов'),
  QuizKind.attach: _m('Как вы ведёте себя в близости', 'How you behave when close', 'Як ви поводитеся в близькості'),
  QuizKind.animal: _m('Ваш зверь и ваш дуэт', 'Your animal and your duo', 'Ваш звір і ваш дует'),
  QuizKind.fight: _m('Ваш стиль в споре и правило на следующий раз', 'Your style in an argument and a rule for next time',
      'Ваш стиль у суперечці й правило на наступний раз'),
  QuizKind.alike: _m('Пятнадцать «или-или» и процент совпадения', 'Fifteen either-or picks and a match score',
      'П’ятнадцять «або-або» і відсоток збігу'),
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
  'share': _m('Поделиться', 'Share', 'Поділитися'),
  'save': _m('Сохранить', 'Save', 'Зберегти'),
  'done': _m('Пройден', 'Done', 'Пройдено'),
  'note': _m('Это не психологическая оценка, а повод поговорить.', 'This is not a psychological assessment, just a reason to talk.',
      'Це не психологічна оцінка, а привід поговорити.'),
  'you': _m('Вы', 'You', 'Ви'),
  'differ': _m('В чём вы разные', 'Where you differ', 'У чому ви різні'),
};

String quizUi(String key, String lang) => _t(_ui[key] ?? const {}, lang);

String quizHint(QuizKind kind, String lang) => _t(_hints[kind]!, lang);

String quizTitle(QuizKind kind, String lang) => _t(_titles[kind]!, lang);
String quizIntro(QuizKind kind, String lang) => _t(_intros[kind]!, lang);

// Язык любви: пятнадцать пар. Первые десять — каждая пара языков по разу,
// ещё пять идут по кругу (слова, время, подарки, дела, касания), так что
// каждый язык встречается ровно шесть раз.
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
  ('words', _m('Партнёр благодарит меня за мелочи', 'My partner thanks me for little things', 'Партнер дякує мені за дрібниці'),
   'time', _m('Вдвоём собирать пазл весь вечер', 'Doing a puzzle together all evening', 'Удвох складати пазл увесь вечір')),
  ('time', _m('Вдвоём кататься на велосипедах', 'Riding bikes together', 'Удвох кататися на велосипедах'),
   'gifts', _m('Кружка с нашей общей шуткой', 'A mug with our inside joke', 'Горнятко з нашим спільним жартом')),
  ('gifts', _m('Билеты туда, куда я давно хочу попасть', 'Tickets to a place I’ve long wanted to go', 'Квитки туди, куди я давно хочу потрапити'),
   'acts', _m('Партнёр встречает меня с поезда', 'My partner meets me off the train', 'Партнер зустрічає мене з потяга')),
  ('acts', _m('Партнёр убирает со стола, пока я отдыхаю', 'My partner clears the table while I rest', 'Партнер прибирає зі столу, поки я відпочиваю'),
   'touch', _m('Партнёр обнимает меня, пока я готовлю', 'My partner hugs me while I cook', 'Партнер обіймає мене, поки я готую')),
  ('touch', _m('Партнёр берёт моё лицо в ладони', 'My partner cups my face in their hands', 'Партнер бере моє обличчя в долоні'),
   'words', _m('Партнёр говорит, что со мной спокойно', 'My partner says they feel at peace with me', 'Партнер каже, що зі мною спокійно')),
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
  ('anx', false, _m('Я боюсь надоесть партнёру', 'I’m afraid my partner will get tired of me', 'Я боюся набриднути партнерові')),
  ('avo', false, _m('Я не спешу рассказывать партнёру о своём прошлом', 'I’m in no hurry to tell my partner about my past', 'Я не поспішаю розповідати партнерові про своє минуле')),
  ('anx', true, _m('В чувствах партнёра я не сомневаюсь', 'I don’t doubt my partner’s feelings', 'У почуттях партнера я не сумніваюся')),
];

final List<Map<String, String>> _likert = [
  _m('Совсем нет', 'Not at all', 'Зовсім ні'),
  _m('Скорее нет', 'Rather not', 'Радше ні'),
  _m('Иногда', 'Sometimes', 'Іноді'),
  _m('Скорее да', 'Rather yes', 'Радше так'),
  _m('Точно да', 'Definitely', 'Точно так'),
];

// Животное: пятнадцать вопросов, у каждого четыре зверя. Кот, пёс, выдра и
// медведь встречаются по восемь раз, остальные по семь: итог считается долей.
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
  (_m('Партнёр зовёт вас на свидание', 'Your partner asks you out', 'Партнер кличе вас на побачення'), [
    ('cat', _m('Соглашаюсь, если сам вечер мне нравится', 'I say yes if I like the plan', 'Погоджуюся, якщо сам вечір мені подобається')),
    ('otter', _m('Соглашаюсь и всю дорогу держу за руку', 'I say yes and hold hands the whole way', 'Погоджуюся й усю дорогу тримаю за руку')),
    ('penguin', _m('Иду с маленьким подарком', 'I come with a little gift', 'Іду з маленьким подарунком')),
    ('fox', _m('Предлагаю что-нибудь безумнее', 'I suggest something crazier', 'Пропоную щось божевільніше')),
  ]),
  (_m('Вы поссорились из-за ерунды', 'You fought over nothing', 'Ви посварилися через дурницю'), [
    ('dog', _m('Через пять минут уже лезу обниматься', 'Five minutes later I’m in for a hug', 'За п’ять хвилин уже лізу обійматися')),
    ('koala', _m('Ложусь спать, утром всё забудется', 'I go to bed, it’ll be forgotten by morning', 'Лягаю спати, зранку все забудеться')),
    ('hedgehog', _m('Дуюсь, но оттаиваю, как только партнёр сделает шаг', 'I sulk, but melt as soon as my partner makes a move', 'Дуюся, але відтаю, щойно партнер зробить крок')),
    ('bear', _m('Сажусь и спокойно всё обсуждаю', 'I sit down and talk it through calmly', 'Сідаю й спокійно все обговорюю')),
  ]),
  (_m('Совместная поездка', 'A trip together', 'Спільна поїздка'), [
    ('cat', _m('Мне нужен свой час в день без компании', 'I need an hour a day on my own', 'Мені потрібна своя година на день без компанії')),
    ('bear', _m('Беру с собой аптечку и всё на всякий случай', 'I pack a first aid kit and everything just in case', 'Беру із собою аптечку й усе про всяк випадок')),
    ('otter', _m('Везде ходим, взявшись за руки', 'We go everywhere holding hands', 'Скрізь ходимо, узявшись за руки')),
    ('fox', _m('Сворачиваю с маршрута туда, где интереснее', 'I leave the route for somewhere more fun', 'Звертаю з маршруту туди, де цікавіше')),
  ]),
  (_m('Партнёр задерживается на работе', 'Your partner is stuck at work late', 'Партнер затримується на роботі'), [
    ('dog', _m('Встречаю у двери, будто год не виделись', 'I greet them at the door like it’s been a year', 'Зустрічаю біля дверей, ніби рік не бачилися')),
    ('penguin', _m('Оставляю ужин и записку', 'I leave dinner and a note', 'Залишаю вечерю й записку')),
    ('koala', _m('Засыпаю на диване, пока жду', 'I fall asleep on the couch waiting', 'Засинаю на дивані, поки чекаю')),
    ('hedgehog', _m('Ворчу, что поздно, и грею еду', 'I grumble that it’s late and heat up the food', 'Буркочу, що пізно, і грію їжу')),
  ]),
  (_m('Ваш подарок партнёру', 'Your gift to your partner', 'Ваш подарунок партнерові'), [
    ('cat', _m('То, что нравится мне', 'Something I like myself', 'Те, що подобається мені')),
    ('dog', _m('Что угодно, лишь бы обрадовать', 'Anything, as long as it makes them happy', 'Що завгодно, аби потішити')),
    ('bear', _m('Что-то полезное и надёжное', 'Something useful and sturdy', 'Щось корисне й надійне')),
    ('penguin', _m('Вещица со смыслом, понятным только нам', 'A little thing with a meaning only we get', 'Дрібничка зі змістом, зрозумілим лише нам')),
  ]),
  (_m('Как вы засыпаете вдвоём', 'How you fall asleep together', 'Як ви засинаєте удвох'), [
    ('fox', _m('Болтаем и смеёмся до глубокой ночи', 'We chat and laugh deep into the night', 'Балакаємо й сміємося до глибокої ночі')),
    ('otter', _m('Только держась за руки', 'Only holding hands', 'Тільки тримаючись за руки')),
    ('hedgehog', _m('Каждый под своим одеялом', 'Each under our own blanket', 'Кожен під своєю ковдрою')),
    ('koala', _m('Обвиваю партнёра и сразу сплю', 'I wrap around my partner and I’m out', 'Обвиваю партнера й одразу сплю')),
  ]),
  (_m('Вас пригласили на свадьбу друзей', 'You’re invited to your friends’ wedding', 'Вас запросили на весілля друзів'), [
    ('cat', _m('Приду ненадолго и тихо уйду', 'I’ll drop by for a bit and slip away', 'Прийду ненадовго й тихо піду')),
    ('dog', _m('Танцую со всеми до утра', 'I dance with everyone till morning', 'Танцюю з усіма до ранку')),
    ('otter', _m('Не отпускаю партнёра весь вечер', 'I don’t let go of my partner all night', 'Не відпускаю партнера весь вечір')),
    ('bear', _m('Слежу, чтобы все добрались домой', 'I make sure everyone gets home', 'Стежу, щоб усі дісталися додому')),
  ]),
];

// ── банк: запасные варианты каждого вопроса ─────────────────────────────────
//
// Как в «Умении любить», набор меняется от раза к разу. Вопрос — это слот:
// у каждого слота несколько вариантов с ТЕМИ ЖЕ типами на тех же местах,
// поэтому баланс (каждый язык и каждый зверь ровно четыре раза, шесть
// утверждений на ось) держится в любом наборе. Основной вариант — списки выше.

/// Ещё по четыре варианта на каждую пару языков, в том же порядке типов.
final List<List<(Map<String, String>, Map<String, String>)>> _langExtra = [
  [ // words / time
    (_m('Партнёр рассказывает, за что меня любит', 'My partner tells me why they love me', 'Партнер розповідає, за що мене кохає'),
     _m('Вечер, когда мы вдвоём разбираем старые фото', 'An evening going through old photos together', 'Вечір, коли ми удвох переглядаємо старі фото')),
    (_m('Тёплое сообщение, как только партнёр проснётся', 'A warm text as soon as my partner wakes up', 'Тепле повідомлення, щойно партнер прокинеться'),
     _m('Партнёр берёт выходной, чтобы провести день со мной', 'My partner takes a day off to spend it with me', 'Партнер бере вихідний, щоб провести день зі мною')),
    (_m('Сообщение «думаю о тебе» посреди рабочего дня', 'A “thinking of you” text in the middle of the workday', 'Повідомлення «думаю про тебе» посеред робочого дня'),
     _m('Целый выходной только вдвоём', 'A whole day off, just the two of us', 'Цілий вихідний тільки удвох')),
    (_m('Партнёр хвалит то, что у меня получилось', 'My partner praises what I pulled off', 'Партнер хвалить те, що в мене вийшло'),
     _m('Партнёр слушает меня, ни на что не отвлекаясь', 'My partner listens to me with full attention', 'Партнер слухає мене, ні на що не відволікаючись')),
  ],
  [ // words / gifts
    (_m('Пост о нас с тёплой подписью', 'A post about us with a sweet caption', 'Допис про нас із теплим підписом'),
     _m('Билеты на концерт моей любимой группы', 'Tickets to my favorite band’s concert', 'Квитки на концерт мого улюбленого гурту')),
    (_m('Партнёр перечисляет, что во мне ценит', 'My partner lists what they value in me', 'Партнер перелічує, що в мені цінує'),
     _m('Вещица, которая напоминает о нашем первом свидании', 'A little thing that reminds me of our first date', 'Дрібничка, що нагадує про наше перше побачення')),
    (_m('Голосовое с признанием', 'A voice message with a confession', 'Голосове із зізнанням'),
     _m('Любимая сладость, купленная по дороге', 'My favorite treat, picked up on the way', 'Улюблена солодість, куплена дорогою')),
    (_m('Открытка с длинным письмом от руки', 'A card with a long handwritten letter', 'Листівка з довгим листом від руки'),
     _m('Подарок по моему случайному намёку', 'A gift based on a hint I dropped once', 'Подарунок за моїм випадковим натяком')),
  ],
  [ // words / acts
    (_m('Партнёр говорит «ты молодец» после трудного дня', 'My partner says “well done” after a hard day', 'Партнер каже «ти молодець» після важкого дня'),
     _m('Партнёр забирает за меня посылку', 'My partner picks up my parcel for me', 'Партнер забирає за мене посилку')),
    (_m('Партнёр подбадривает меня перед важным делом', 'My partner cheers me on before something big', 'Партнер підбадьорює мене перед важливою справою'),
     _m('Партнёр гладит мне одежду на завтра', 'My partner irons my clothes for tomorrow', 'Партнер прасує мені одяг на завтра')),
    (_m('Услышать «спасибо, что ты есть»', 'Hearing “thank you for being you”', 'Почути «дякую, що ти є»'),
     _m('Партнёр чинит то, что давно сломано', 'My partner fixes what has been broken for ages', 'Партнер лагодить те, що давно зламане')),
    (_m('Партнёр говорит, что верит в меня', 'My partner says they believe in me', 'Партнер каже, що вірить у мене'),
     _m('Партнёр сам закупает продукты на неделю', 'My partner does the weekly grocery run', 'Партнер сам закуповує продукти на тиждень')),
  ],
  [ // words / touch
    (_m('Партнёр пишет, что скучает', 'My partner texts that they miss me', 'Партнер пише, що сумує'),
     _m('Партнёр берёт мою руку под столом', 'My partner takes my hand under the table', 'Партнер бере мою руку під столом')),
    (_m('Нежные слова шёпотом на ухо', 'Sweet words whispered in my ear', 'Ніжні слова пошепки на вухо'),
     _m('Партнёр утыкается мне в плечо', 'My partner nuzzles into my shoulder', 'Партнер утикається мені в плече')),
    (_m('Ласковое прозвище', 'A sweet nickname', 'Ласкаве прізвисько'),
     _m('Поцелуй в лоб', 'A kiss on the forehead', 'Поцілунок у лоб')),
    (_m('Комплимент моей внешности', 'A compliment on how I look', 'Комплімент моїй зовнішності'),
     _m('Рука на моём плече в толпе', 'A hand on my shoulder in a crowd', 'Рука на моєму плечі в натовпі')),
  ],
  [ // time / gifts
    (_m('Пикник вдвоём в парке', 'A picnic for two in the park', 'Пікнік удвох у парку'),
     _m('Цветок в горшке, чтобы он рос у нас дома', 'A potted plant to grow in our home', 'Квітка в горщику, щоб вона росла в нас удома')),
    (_m('Утро, когда никуда не надо спешить, и мы вместе', 'A morning with nowhere to rush, just us', 'Ранок, коли нікуди не треба поспішати, і ми разом'),
     _m('Шарф, связанный своими руками', 'A scarf knitted by hand', 'Шарф, сплетений власними руками')),
    (_m('Свидание, которое партнёр сам спланировал', 'A date my partner planned all by themselves', 'Побачення, яке партнер сам спланував'),
     _m('Коробка с маленькими сюрпризами', 'A box of little surprises', 'Коробка з маленькими сюрпризами')),
    (_m('Вечер настольных игр вдвоём', 'A board game night for two', 'Вечір настільних ігор удвох'),
     _m('Книга, которую партнёр выбрал специально для меня', 'A book my partner chose just for me', 'Книжка, яку партнер обрав спеціально для мене')),
  ],
  [ // time / acts
    (_m('Поход в музей вдвоём', 'A trip to a museum together', 'Похід до музею удвох'),
     _m('Партнёр сам планирует наш отпуск и всё бронирует', 'My partner plans our vacation and books everything', 'Партнер сам планує нашу відпустку й усе бронює')),
    (_m('Партнёр едет со мной по делам, просто чтобы быть рядом', 'My partner runs errands with me just to be together', 'Партнер їде зі мною у справах, просто щоб бути поруч'),
     _m('Партнёр собирает мои вещи в поездку', 'My partner packs my bag for a trip', 'Партнер збирає мої речі в поїздку')),
    (_m('Поездка за город вдвоём', 'A trip out of town together', 'Поїздка за місто удвох'),
     _m('Партнёр убирает квартиру, пока меня нет', 'My partner cleans the place while I’m out', 'Партнер прибирає квартиру, поки мене немає')),
    (_m('Совместный завтрак без спешки', 'A slow breakfast together', 'Спільний сніданок без поспіху'),
     _m('Партнёр заранее собирает мне обед с собой', 'My partner packs me lunch ahead of time', 'Партнер заздалегідь збирає мені обід із собою')),
  ],
  [ // time / touch
    (_m('Встречать рассвет вдвоём', 'Watching the sunrise together', 'Зустрічати світанок удвох'),
     _m('Танцевать вдвоём на кухне', 'Dancing together in the kitchen', 'Танцювати удвох на кухні')),
    (_m('Слушать музыку и болтать обо всём', 'Listening to music and chatting about everything', 'Слухати музику й балакати про все'),
     _m('Партнёр греет мои руки в своих', 'My partner warms my hands in theirs', 'Партнер гріє мої руки у своїх')),
    (_m('Готовить ужин вместе', 'Cooking dinner together', 'Готувати вечерю разом'),
     _m('Засыпать в обнимку', 'Falling asleep in each other’s arms', 'Засинати в обіймах')),
    (_m('Гулять ночью по городу', 'Walking around the city at night', 'Гуляти вночі містом'),
     _m('Партнёр гладит меня по волосам', 'My partner strokes my hair', 'Партнер гладить мене по волоссю')),
  ],
  [ // gifts / acts
    (_m('Вещь, о которой я давно мечтаю', 'Something I’ve been dreaming of for ages', 'Річ, про яку я давно мрію'),
     _m('Партнёр помогает мне с переездом', 'My partner helps me move', 'Партнер допомагає мені з переїздом')),
    (_m('Сладкий сюрприз на подушке', 'A sweet surprise on my pillow', 'Солодкий сюрприз на подушці'),
     _m('Партнёр ухаживает за мной, когда я болею', 'My partner takes care of me when I’m sick', 'Партнер доглядає за мною, коли я хворію')),
    (_m('Фото в рамке с нашим общим моментом', 'A framed photo of a moment we shared', 'Фото в рамці з нашою спільною миттю'),
     _m('Партнёр делает за меня скучные звонки', 'My partner makes the boring calls for me', 'Партнер робить за мене нудні дзвінки')),
    (_m('Подарок на годовщину, придуманный заранее', 'An anniversary gift planned well ahead', 'Подарунок на річницю, вигаданий заздалегідь'),
     _m('Партнёр встречает меня горячим чаем после работы', 'My partner greets me with hot tea after work', 'Партнер зустрічає мене гарячим чаєм після роботи')),
  ],
  [ // gifts / touch
    (_m('Подарок, упакованный своими руками', 'A gift wrapped by hand', 'Подарунок, запакований власними руками'),
     _m('Поцелуй перед уходом из дома', 'A kiss before leaving the house', 'Поцілунок перед виходом з дому')),
    (_m('Духи, которые партнёр подобрал под меня', 'A perfume my partner picked just for me', 'Парфуми, які партнер дібрав під мене'),
     _m('Обниматься под одеялом холодным вечером', 'Cuddling under a blanket on a cold evening', 'Обійматися під ковдрою холодного вечора')),
    (_m('Браслет или украшение на память', 'A bracelet or a keepsake piece of jewelry', 'Браслет чи прикраса на згадку'),
     _m('Обнять, едва увидев после разлуки', 'A hug the moment we meet after time apart', 'Обійняти, щойно побачивши після розлуки')),
    (_m('Плейлист, собранный специально для меня', 'A playlist made just for me', 'Плейлист, зібраний спеціально для мене'),
     _m('Сидеть рядом, касаясь плечами', 'Sitting close, shoulders touching', 'Сидіти поруч, торкаючись плечима')),
  ],
  [ // acts / touch
    (_m('Партнёр берёт на себя дело, которое я терпеть не могу', 'My partner handles the chore I can’t stand', 'Партнер бере на себе справу, яку я терпіти не можу'),
     _m('Партнёр кладёт голову мне на колени', 'My partner rests their head in my lap', 'Партнер кладе голову мені на коліна')),
    (_m('Партнёр провожает меня до дома поздно вечером', 'My partner walks me home late at night', 'Партнер проводжає мене додому пізно ввечері'),
     _m('Идти под руку на прогулке', 'Walking arm in arm', 'Іти під руку на прогулянці')),
    (_m('Партнёр сам моет посуду после ужина', 'My partner does the dishes after dinner', 'Партнер сам миє посуд після вечері'),
     _m('Долгие объятия без слов', 'A long hug without words', 'Довгі обійми без слів')),
    (_m('Партнёр готовит мою любимую еду', 'My partner cooks my favorite food', 'Партнер готує мою улюблену їжу'),
     _m('Партнёр держит меня за руку в кино', 'My partner holds my hand at the movies', 'Партнер тримає мене за руку в кіно')),
  ],
  [ // words / time
    (_m('Партнёр хвастается мной перед родными', 'My partner shows me off to their family', 'Партнер хизується мною перед рідними'),
     _m('Поездка на выходные в новый город', 'A weekend trip to a new city', 'Поїздка на вихідні в нове місто')),
    (_m('Утром партнёр пишет «доброе утро, мой любимый человек»', 'My partner texts “good morning, my favorite person”', 'Зранку партнер пише «доброго ранку, моя улюблена людино»'),
     _m('Сидеть вдвоём в кафе до самого закрытия', 'Sitting in a café together until closing time', 'Сидіти удвох у кав’ярні до самого закриття')),
    (_m('Партнёр пишет длинное сообщение о нас', 'My partner writes a long message about us', 'Партнер пише довге повідомлення про нас'),
     _m('Вместе учиться чему-то новому', 'Learning something new together', 'Разом учитися чогось нового')),
    (_m('Партнёр замечает мою новую стрижку и хвалит её', 'My partner notices my new haircut and praises it', 'Партнер помічає мою нову зачіску й хвалить її'),
     _m('Партнёр звонит, просто чтобы поболтать', 'My partner calls just to chat', 'Партнер дзвонить, просто щоб побалакати')),
  ],
  [ // time / gifts
    (_m('Вместе смотреть на звёзды', 'Stargazing together', 'Разом дивитися на зорі'),
     _m('Рисунок, который партнёр нарисовал для меня', 'A drawing my partner made for me', 'Малюнок, який партнер намалював для мене')),
    (_m('Вдвоём выбирать, куда поехать летом', 'Choosing together where to go in summer', 'Удвох обирати, куди поїхати влітку'),
     _m('Набор моего любимого чая', 'A set of my favorite tea', 'Набір мого улюбленого чаю')),
    (_m('Вдвоём не спеша бродить по рынку', 'Strolling around a market together', 'Удвох не поспішаючи блукати ринком'),
     _m('Брелок с нашими инициалами', 'A keychain with our initials', 'Брелок з нашими ініціалами')),
    (_m('Долгий ужин в ресторане вдвоём', 'A long dinner for two at a restaurant', 'Довга вечеря в ресторані удвох'),
     _m('Фотокнига о нашем годе', 'A photo book of our year', 'Фотокнига про наш рік')),
  ],
  [ // gifts / acts
    (_m('Сертификат в мой любимый магазин', 'A gift card to my favorite store', 'Сертифікат у мою улюблену крамницю'),
     _m('Партнёр ставит мой телефон на зарядку, пока я сплю', 'My partner charges my phone while I sleep', 'Партнер ставить мій телефон на зарядку, поки я сплю')),
    (_m('Новая книга любимого автора', 'A new book by my favorite author', 'Нова книжка улюбленого автора'),
     _m('Партнёр помогает мне с учёбой или работой', 'My partner helps me with study or work', 'Партнер допомагає мені з навчанням чи роботою')),
    (_m('Мягкая игрушка, чтобы обнимать её, когда партнёра нет рядом', 'A plush toy to hug when my partner is away', 'М’яка іграшка, щоб обіймати її, коли партнера немає поруч'),
     _m('Партнёр сам разбирается с бумагами, которые меня пугают', 'My partner handles the paperwork that scares me', 'Партнер сам розбирається з папірцями, які мене лякають')),
    (_m('Свеча с запахом, который я люблю', 'A candle with a scent I love', 'Свічка з ароматом, який я люблю'),
     _m('Партнёр приносит мне кофе в постель', 'My partner brings me coffee in bed', 'Партнер приносить мені каву в ліжко')),
  ],
  [ // acts / touch
    (_m('Партнёр поливает мои цветы, пока меня нет', 'My partner waters my plants while I’m away', 'Партнер поливає мої квіти, поки мене немає'),
     _m('Партнёр рисует пальцем узоры у меня на спине', 'My partner traces patterns on my back', 'Партнер малює пальцем візерунки в мене на спині')),
    (_m('Партнёр напоминает мне о важных делах', 'My partner reminds me of important things', 'Партнер нагадує мені про важливі справи'),
     _m('Спать, переплетясь ногами', 'Sleeping with our legs tangled', 'Спати, переплівшись ногами')),
    (_m('Партнёр помогает мне собраться, когда я опаздываю', 'My partner helps me get ready when I’m running late', 'Партнер допомагає мені зібратися, коли я запізнююся'),
     _m('Партнёр целует мне руку', 'My partner kisses my hand', 'Партнер цілує мені руку')),
    (_m('Партнёр сам идёт в аптеку, когда мне плохо', 'My partner goes to the pharmacy when I feel bad', 'Партнер сам іде до аптеки, коли мені погано'),
     _m('Партнёр делает мне массаж ног', 'My partner gives me a foot rub', 'Партнер робить мені масаж ніг')),
  ],
  [ // touch / words
    (_m('Партнёр трётся носом о мой нос', 'My partner rubs noses with me', 'Партнер треться носом об мій ніс'),
     _m('Партнёр называет меня лучшим другом', 'My partner calls me their best friend', 'Партнер називає мене найкращим другом')),
    (_m('Партнёр сажает меня к себе на колени', 'My partner pulls me onto their lap', 'Партнер садить мене собі на коліна'),
     _m('Партнёр первым извиняется и подбирает тёплые слова', 'My partner apologizes first and finds warm words', 'Партнер першим вибачається й добирає теплі слова')),
    (_m('Партнёр щекочет меня, пока я не рассмеюсь', 'My partner tickles me until I laugh', 'Партнер лоскоче мене, поки я не засміюся'),
     _m('Партнёр вспоминает вслух наш первый день', 'My partner recalls our first day out loud', 'Партнер згадує вголос наш перший день')),
    (_m('Партнёр гладит мою руку, пока мы разговариваем', 'My partner strokes my hand while we talk', 'Партнер гладить мою руку, поки ми розмовляємо'),
     _m('Партнёр говорит, что я самый красивый человек на свете', 'My partner says I’m the most beautiful person in the world', 'Партнер каже, що я найгарніша людина у світі')),
  ],
];

/// Ещё по три утверждения на каждый слот: та же ось и то же направление.
final List<List<Map<String, String>>> _attachExtra = [
  [ // anx
    _m('Мне страшно, что меня бросят', 'I’m scared of being left', 'Мені страшно, що мене покинуть'),
    _m('Иногда я сомневаюсь, что партнёр правда меня любит', 'Sometimes I doubt my partner really loves me', 'Іноді я сумніваюся, що партнер справді мене кохає'),
    _m('Мне кажется, что я люблю сильнее, чем меня', 'I feel like I love more than I’m loved', 'Мені здається, що я кохаю сильніше, ніж мене'),
  ],
  [ // avo
    _m('Мне неловко, когда партнёр говорит о чувствах', 'I feel awkward when my partner talks about feelings', 'Мені ніяково, коли партнер говорить про почуття'),
    _m('Я редко говорю партнёру, что мне плохо', 'I rarely tell my partner when I feel bad', 'Я рідко кажу партнерові, що мені погано'),
    _m('Свои переживания я держу при себе, даже от партнёра', 'I keep my worries to myself, even from my partner', 'Свої переживання я тримаю при собі, навіть від партнера'),
  ],
  [ // anx
    _m('Я перечитываю переписку и ищу, не обиделся ли партнёр', 'I reread our chat looking for signs my partner is upset', 'Я перечитую листування й шукаю, чи не образився партнер'),
    _m('Когда партнёр не берёт трубку, я представляю худшее', 'When my partner doesn’t pick up, I imagine the worst', 'Коли партнер не бере слухавку, я уявляю найгірше'),
    _m('Я проверяю, когда партнёр был в сети', 'I check when my partner was last online', 'Я перевіряю, коли партнер був у мережі'),
  ],
  [ // avo
    _m('Слишком много времени вместе меня утомляет', 'Too much time together wears me out', 'Забагато часу разом мене втомлює'),
    _m('Даже когда всё хорошо, мне нужно много времени наедине с собой', 'Even when things are good, I need a lot of time alone', 'Навіть коли все добре, мені потрібно багато часу наодинці з собою'),
    _m('Когда отношения становятся серьёзнее, мне хочется притормозить', 'When things get more serious, I want to slow down', 'Коли стосунки стають серйознішими, мені хочеться пригальмувати'),
  ],
  [ // anx
    _m('Мне важно, чтобы партнёр часто писал первым', 'I need my partner to text first often', 'Мені важливо, щоб партнер часто писав першим'),
    _m('Без частых знаков внимания я начинаю сомневаться в партнёре', 'Without frequent signs of attention I start to doubt my partner', 'Без частих знаків уваги я починаю сумніватися в партнері'),
    _m('Я расстраиваюсь, если партнёр не замечает моих стараний', 'I get upset if my partner doesn’t notice my efforts', 'Я засмучуюся, якщо партнер не помічає моїх старань'),
  ],
  [ // avo, обратное
    _m('Я легко делюсь с партнёром тем, что меня тревожит', 'I easily share what worries me with my partner', 'Я легко ділюся з партнером тим, що мене тривожить'),
    _m('Я могу заплакать при партнёре и не стыдиться этого', 'I can cry in front of my partner without shame', 'Я можу заплакати при партнерові й не соромитися цього'),
    _m('Мне легко рассказать партнёру о своих слабостях', 'It is easy for me to tell my partner about my weak spots', 'Мені легко розповісти партнерові про свої слабкості'),
  ],
  [ // anx
    _m('Я ревную, даже если повода нет', 'I get jealous even without a reason', 'Я ревную, навіть якщо приводу немає'),
    _m('Я сравниваю себя с бывшими партнёра', 'I compare myself to my partner’s exes', 'Я порівнюю себе з колишніми партнера'),
    _m('Меня тревожит, когда партнёр хвалит кого-то другого', 'It bothers me when my partner praises someone else', 'Мене тривожить, коли партнер хвалить когось іншого'),
  ],
  [ // avo
    _m('Когда что-то не так, я скорее замолчу, чем скажу', 'When something is wrong, I’d rather go quiet than say it', 'Коли щось не так, я радше замовкну, ніж скажу'),
    _m('Я не люблю зависеть от партнёра', 'I don’t like depending on my partner', 'Я не люблю залежати від партнера'),
    _m('О трудностях я рассказываю, только когда уже их решу', 'I only talk about my troubles once I’ve solved them', 'Про труднощі я розповідаю, тільки коли вже їх розв’яжу'),
  ],
  [ // anx, обратное
    _m('Если партнёр занят, я спокойно жду', 'If my partner is busy, I wait calmly', 'Якщо партнер зайнятий, я спокійно чекаю'),
    _m('Когда партнёр уезжает, я спокойно живу своей жизнью', 'When my partner is away, I calmly get on with my life', 'Коли партнер їде, я спокійно живу своїм життям'),
    _m('Мне не нужно знать, где партнёр каждую минуту', 'I don’t need to know where my partner is every minute', 'Мені не треба знати, де партнер щохвилини'),
  ],
  [ // avo, обратное
    _m('Мне нравится, когда мы знаем друг о друге всё', 'I like it when we know everything about each other', 'Мені подобається, коли ми знаємо одне про одного все'),
    _m('Я люблю, когда партнёр рядом почти всё время', 'I love having my partner around almost all the time', 'Я люблю, коли партнер поруч майже весь час'),
    _m('Мне легко сказать партнёру «я тебя люблю»', 'It is easy for me to say “I love you” to my partner', 'Мені легко сказати партнерові «я тебе кохаю»'),
  ],
  [ // anx
    _m('После ссоры мне трудно уснуть', 'After a fight it is hard for me to fall asleep', 'Після сварки мені важко заснути'),
    _m('После ссоры я боюсь, что это конец', 'After a fight I fear it’s the end', 'Після сварки я боюся, що це кінець'),
    _m('Даже маленькое недовольство партнёра меня сильно тревожит', 'Even a little displeasure from my partner worries me a lot', 'Навіть маленьке невдоволення партнера мене дуже тривожить'),
  ],
  [ // avo
    _m('Когда партнёр просит поговорить о нас, я ищу повод отложить', 'When my partner asks to talk about us, I look for a reason to put it off', 'Коли партнер просить поговорити про нас, я шукаю привід відкласти'),
    _m('В трудном разговоре я закрываюсь', 'In a hard conversation I shut down', 'У важкій розмові я закриваюся'),
    _m('Когда партнёр расстроен, мне хочется уйти в другую комнату', 'When my partner is upset, I want to go to another room', 'Коли партнер засмучений, мені хочеться піти в іншу кімнату'),
  ],
  [ // anx
    _m('Когда партнёр не в духе, я думаю, что дело во мне', 'When my partner is in a bad mood, I think it’s because of me', 'Коли партнер не в гуморі, я думаю, що справа в мені'),
    _m('Мне трудно поверить, что партнёр выбрал именно меня', 'It’s hard for me to believe my partner chose me', 'Мені важко повірити, що партнер обрав саме мене'),
    _m('Я боюсь спорить с партнёром, чтобы не потерять отношения', 'I’m afraid to argue with my partner in case I lose us', 'Я боюся сперечатися з партнером, щоб не втратити стосунки'),
  ],
  [ // avo
    _m('Мне неуютно, когда партнёр от меня зависит', 'I feel uneasy when my partner depends on me', 'Мені незатишно, коли партнер від мене залежить'),
    _m('Обещания на годы вперёд меня пугают', 'Promises years ahead scare me', 'Обіцянки на роки вперед мене лякають'),
    _m('Мне сложно признаться партнёру, что я скучаю', 'It’s hard for me to admit to my partner that I miss them', 'Мені складно зізнатися партнерові, що я сумую'),
  ],
  [ // anx, обратное
    _m('Если партнёр не ответил сразу, я себя не накручиваю', 'If my partner doesn’t reply right away, I don’t wind myself up', 'Якщо партнер не відповів одразу, я себе не накручую'),
    _m('Мне спокойно, даже когда мы долго не видимся', 'I feel calm even when we don’t see each other for a while', 'Мені спокійно, навіть коли ми довго не бачимося'),
    _m('После ссоры я не думаю, что мы расстанемся', 'After a fight I don’t think we’ll break up', 'Після сварки я не думаю, що ми розійдемося'),
  ],
];

/// Ещё по три вопроса на каждый слот: те же звери в том же порядке.
final List<List<(Map<String, String>, List<Map<String, String>>)>> _animalExtra = [
  [ // cat, dog, fox, koala
    (_m('Как вы отдыхаете в отпуске', 'How you spend a vacation', 'Як ви відпочиваєте у відпустці'), [
      _m('Каждый читает своё у бассейна', 'Each reading our own book by the pool', 'Кожен читає своє біля басейну'),
      _m('Везде вместе, куда бы ни пошли', 'Together everywhere, wherever we go', 'Скрізь разом, куди б не пішли'),
      _m('Каждый день новое место', 'A new place every day', 'Щодня нове місце'),
      _m('Номер, кровать и доставка еды', 'The room, the bed and food delivery', 'Номер, ліжко й доставка їжі'),
    ]),
    (_m('Свободный день вдвоём', 'A free day together', 'Вільний день удвох'), [
      _m('Полдня вместе, полдня каждый сам по себе', 'Half the day together, half on our own', 'Пів дня разом, пів дня кожен сам по собі'),
      _m('Весь день вместе, чем бы ни заниматься', 'The whole day together, whatever we do', 'Увесь день разом, чим би не займатися'),
      _m('Едем туда, где ещё не были', 'Off somewhere we’ve never been', 'Їдемо туди, де ще не були'),
      _m('Не вылезаем из кровати', 'We never leave the bed', 'Не вилазимо з ліжка'),
    ]),
    (_m('Как вы празднуете годовщину', 'How you celebrate your anniversary', 'Як ви святкуєте річницю'), [
      _m('Тихо, без лишней суеты', 'Quietly, no fuss', 'Тихо, без зайвої метушні'),
      _m('Зовём друзей, пусть радуются с нами', 'We invite friends to celebrate with us', 'Кличемо друзів, хай радіють із нами'),
      _m('Устраиваю сюрприз, о котором партнёр не догадается', 'I set up a surprise my partner won’t see coming', 'Влаштовую сюрприз, про який партнер не здогадається'),
      _m('Заказываем еду и смотрим фильм под пледом', 'We order food and watch a movie under a blanket', 'Замовляємо їжу й дивимося фільм під пледом'),
    ]),
  ],
  [ // otter, bear, hedgehog, penguin
    (_m('Партнёр замёрз', 'Your partner is cold', 'Партнер змерз'), [
      _m('Грею ладони партнёра в своих', 'I warm their hands in mine', 'Грію долоні партнера у своїх'),
      _m('Обнимаю целиком', 'I wrap them in a full hug', 'Обіймаю повністю'),
      _m('Ворчу и отдаю свою куртку', 'I grumble and hand over my jacket', 'Буркочу й віддаю свою куртку'),
      _m('Приношу горячий чай', 'I bring hot tea', 'Приношу гарячий чай'),
    ]),
    (_m('Как вы заботитесь о партнёре', 'How you take care of your partner', 'Як ви дбаєте про партнера'), [
      _m('Не отхожу ни на шаг', 'I never leave their side', 'Не відходжу ні на крок'),
      _m('Защищаю от всего мира', 'I protect them from the whole world', 'Захищаю від усього світу'),
      _m('Ворчу «оденься теплее» и несу шарф', 'I grumble “dress warmer” and bring a scarf', 'Буркочу «вдягнися тепліше» й несу шарф'),
      _m('Оставляю записки и маленькие сюрпризы', 'I leave notes and little surprises', 'Залишаю записки й маленькі сюрпризи'),
    ]),
    (_m('Ваш способ сказать «люблю»', 'Your way of saying “I love you”', 'Ваш спосіб сказати «кохаю»'), [
      _m('Переплетаю пальцы с пальцами партнёра', 'I lace my fingers with theirs', 'Переплітаю пальці з пальцями партнера'),
      _m('Обнимаю так, что хрустят косточки', 'I hug so hard their bones crack', 'Обіймаю так, що хрустять кісточки'),
      _m('Говорю колкость, но с улыбкой', 'I tease them, but with a smile', 'Кажу шпильку, але з усмішкою'),
      _m('Приношу камешек, листик или ракушку', 'I bring a pebble, a leaf or a seashell', 'Приношу камінчик, листочок чи мушлю'),
    ]),
  ],
  [ // cat, dog, hedgehog, fox
    (_m('Партнёр опаздывает на свидание', 'Your partner is late for a date', 'Партнер запізнюється на побачення'), [
      _m('Не жду и занимаюсь своим', 'I don’t wait, I do my own thing', 'Не чекаю й займаюся своїм'),
      _m('Жду и радуюсь, когда наконец приходит', 'I wait and light up when they finally show', 'Чекаю й радію, коли нарешті приходить'),
      _m('Встречаю колкостью, но никуда не ухожу', 'I greet them with a jab, but I stay', 'Зустрічаю шпилькою, але нікуди не йду'),
      _m('Придумываю розыгрыш', 'I plot a little prank', 'Вигадую розіграш'),
    ]),
    (_m('Партнёр на вас обиделся', 'Your partner is hurt by you', 'Партнер на вас образився'), [
      _m('Жду, когда пройдёт само', 'I wait for it to pass on its own', 'Чекаю, коли мине саме'),
      _m('Не отстаю, пока не помиримся', 'I don’t give up until we make up', 'Не відстаю, поки не помиримося'),
      _m('Колюсь в ответ, а потом отхожу', 'I prickle back, then soften', 'Колюся у відповідь, а потім відходжу'),
      _m('Смешу, пока партнёр не улыбнётся', 'I make them laugh until they smile', 'Смішу, поки партнер не всміхнеться'),
    ]),
    (_m('Партнёр вас критикует', 'Your partner criticizes you', 'Партнер вас критикує'), [
      _m('Слушаю вполуха и делаю по-своему', 'I half listen and do it my way', 'Слухаю впіввуха й роблю по-своєму'),
      _m('Расстраиваюсь, но быстро прощаю', 'I get upset, but forgive quickly', 'Засмучуюся, але швидко прощаю'),
      _m('Сразу ощетиниваюсь', 'My spikes go up at once', 'Одразу наїжачуюся'),
      _m('Отшучиваюсь', 'I laugh it off', 'Віджартовуюся'),
    ]),
  ],
  [ // otter, cat, bear, koala
    (_m('Вы долго не виделись', 'You haven’t seen each other for a while', 'Ви довго не бачилися'), [
      _m('Весь день не отпускаю руку', 'I don’t let go of their hand all day', 'Увесь день не відпускаю руку'),
      _m('Делаю вид, что не так уж и скучаю', 'I act like I didn’t miss them that much', 'Вдаю, що не так уже й сумую'),
      _m('Сначала накормлю и укутаю', 'First I feed them and tuck them in', 'Спершу нагодую й закутаю'),
      _m('Обнимаемся и засыпаем', 'We cuddle and fall asleep', 'Обіймаємося й засинаємо'),
    ]),
    (_m('Партнёр уехал на неделю', 'Your partner is away for a week', 'Партнер поїхав на тиждень'), [
      _m('Звоню по видео каждый вечер', 'I video call every evening', 'Дзвоню по відео щовечора'),
      _m('Наслаждаюсь тишиной и жду', 'I enjoy the quiet and wait', 'Насолоджуюся тишею й чекаю'),
      _m('Каждый день спрашиваю, как партнёр ест и спит', 'Every day I ask how they eat and sleep', 'Щодня питаю, як партнер їсть і спить'),
      _m('Сплю в обнимку с вещью партнёра', 'I sleep hugging something of theirs', 'Сплю в обіймах із річчю партнера'),
    ]),
    (_m('Голосовые сообщения', 'Voice messages', 'Голосові повідомлення'), [
      _m('Записываю по десять в день', 'I record ten a day', 'Записую по десять на день'),
      _m('Слушаю, когда будет настроение', 'I listen when I’m in the mood', 'Слухаю, коли буде настрій'),
      _m('Напоминаю в них одеться теплее', 'I use them to remind them to dress warm', 'Нагадую в них вдягнутися тепліше'),
      _m('Засыпаю, не дослушав', 'I fall asleep before the end', 'Засинаю, не дослухавши'),
    ]),
  ],
  [ // fox, hedgehog, dog, penguin
    (_m('Новые знакомые партнёра', 'Your partner’s new friends', 'Нові знайомі партнера'), [
      _m('Быстро нахожу с ними общий язык', 'I get along with them right away', 'Швидко знаходжу з ними спільну мову'),
      _m('Присматриваюсь, пока не пойму, кто они', 'I keep my distance until I figure them out', 'Придивляюся, поки не зрозумію, хто вони'),
      _m('Сразу считаю их друзьями', 'I treat them as friends straight away', 'Одразу вважаю їх друзями'),
      _m('Мне хватает моего человека', 'My person is all I need', 'Мені вистачає моєї людини'),
    ]),
    (_m('Вечеринка у друзей партнёра', 'A party at your partner’s friends’ place', 'Вечірка в друзів партнера'), [
      _m('Через час знаю всех по именам', 'An hour in, I know everyone by name', 'За годину знаю всіх на ім’я'),
      _m('Сижу в углу с тем, кого знаю', 'I sit in a corner with someone I know', 'Сиджу в кутку з тим, кого знаю'),
      _m('На прощание обнимаюсь со всеми', 'I hug everyone goodbye', 'На прощання обіймаюся з усіма'),
      _m('Весь вечер держусь рядом с партнёром', 'I stay by my partner all evening', 'Увесь вечір тримаюся поруч із партнером'),
    ]),
    (_m('Ваш день рождения', 'Your birthday', 'Ваш день народження'), [
      _m('Большая шумная вечеринка с играми', 'A big loud party with games', 'Велика гучна вечірка з іграми'),
      _m('Только самые близкие', 'Only my closest people', 'Тільки найближчі'),
      _m('Зову всех, кого знаю', 'I invite everyone I know', 'Кличу всіх, кого знаю'),
      _m('Ужин вдвоём, больше никого', 'Dinner for two, no one else', 'Вечеря удвох, більше нікого'),
    ]),
  ],
  [ // bear, otter, penguin, koala
    (_m('У партнёра тяжёлый день', 'Your partner has a rough day', 'У партнера важкий день'), [
      _m('Беру всё на себя', 'I take everything on myself', 'Беру все на себе'),
      _m('Весь день пишу, что я рядом', 'I text all day that I’m here', 'Увесь день пишу, що я поруч'),
      _m('Готовлю сюрприз к вечеру', 'I plan a surprise for the evening', 'Готую сюрприз на вечір'),
      _m('Зову полежать вместе и ничего не делать', 'I invite them to lie down together and do nothing', 'Кличу полежати разом і нічого не робити'),
    ]),
    (_m('Партнёр заболел', 'Your partner is sick', 'Партнер захворів'), [
      _m('Беру всё лечение на себя', 'I take charge of all the care', 'Беру все лікування на себе'),
      _m('Сижу рядом и держу за руку', 'I sit close and hold their hand', 'Сиджу поруч і тримаю за руку'),
      _m('Несу апельсины и любимые сладости', 'I bring oranges and favorite sweets', 'Несу апельсини й улюблені солодощі'),
      _m('Лежу рядом, пока партнёр спит', 'I lie next to them while they sleep', 'Лежу поруч, поки партнер спить'),
    ]),
    (_m('Партнёр волнуется перед важным днём', 'Your partner is nervous before a big day', 'Партнер хвилюється перед важливим днем'), [
      _m('Говорю: «Я с тобой, справимся»', 'I say: “I’m with you, we’ll handle it”', 'Кажу: «Я з тобою, впораємося»'),
      _m('Держу за руку до самой двери', 'I hold their hand right up to the door', 'Тримаю за руку до самих дверей'),
      _m('Кладу в сумку шоколадку на удачу', 'I slip a chocolate in their bag for luck', 'Кладу в сумку шоколадку на щастя'),
      _m('Укладываю пораньше спать', 'I get them to bed early', 'Вкладаю раніше спати'),
    ]),
  ],
  [ // penguin, dog, bear, fox
    (_m('Что ранило бы вас сильнее', 'What would hurt you most', 'Що поранило б вас найбільше'), [
      _m('Измена', 'Cheating', 'Зрада'),
      _m('Холодность', 'Coldness', 'Холодність'),
      _m('Ненадёжность', 'Unreliability', 'Ненадійність'),
      _m('Скука', 'Boredom', 'Нудьга'),
    ]),
    (_m('Каким должен быть партнёр', 'What your partner should be like', 'Яким має бути партнер'), [
      _m('Единственным на всю жизнь', 'The one for life', 'Єдиним на все життя'),
      _m('Весёлым', 'Fun to be around', 'Веселим'),
      _m('Тем, за кем как за стеной', 'Someone solid as a wall', 'Тим, за ким як за стіною'),
      _m('С огоньком в глазах', 'With a spark in their eyes', 'З вогником в очах'),
    ]),
    (_m('Чего вы ждёте от будущего', 'What you want from the future', 'Чого ви чекаєте від майбутнього'), [
      _m('Быть вместе до старости', 'To be together into old age', 'Бути разом до старості'),
      _m('Чтобы каждый день был счастливым', 'For every day to be happy', 'Щоб кожен день був щасливим'),
      _m('Свой дом и спокойствие', 'A home of our own and peace', 'Свій дім і спокій'),
      _m('Путешествия и новые впечатления', 'Travel and new experiences', 'Подорожі й нові враження'),
    ]),
  ],
  [ // koala, hedgehog, otter, cat
    (_m('Любимое место дома', 'Your favorite spot at home', 'Улюблене місце вдома'), [
      _m('Кровать', 'The bed', 'Ліжко'),
      _m('Свой угол, куда никто не лезет', 'My own corner nobody touches', 'Свій куток, куди ніхто не лізе'),
      _m('Диван, где мы вдвоём', 'The couch where we sit together', 'Диван, де ми вдвох'),
      _m('Подоконник с видом', 'A windowsill with a view', 'Підвіконня з краєвидом'),
    ]),
    (_m('Прозвенел будильник', 'The alarm goes off', 'Задзвонив будильник'), [
      _m('Ещё пять минут, и ещё пять', 'Five more minutes, then five more', 'Ще п’ять хвилин, і ще п’ять'),
      _m('Встаю молча, меня пока лучше не трогать', 'I get up silently, better not touch me yet', 'Встаю мовчки, мене поки краще не чіпати'),
      _m('Тянусь обнять партнёра', 'I reach out to hug my partner', 'Тягнуся обійняти партнера'),
      _m('Встаю, когда захочу', 'I get up when I feel like it', 'Встаю, коли захочу'),
    ]),
    (_m('Дождливый день', 'A rainy day', 'Дощовий день'), [
      _m('Спать под шум дождя', 'Sleeping to the sound of rain', 'Спати під шум дощу'),
      _m('Читать в своём углу', 'Reading in my own corner', 'Читати у своєму кутку'),
      _m('Смотреть на дождь, прижавшись друг к другу', 'Watching the rain, snuggled together', 'Дивитися на дощ, пригорнувшись одне до одного'),
      _m('Сидеть у окна с чаем и смотреть на капли', 'Sitting by the window with tea, watching the drops', 'Сидіти біля вікна з чаєм і дивитися на краплі'),
    ]),
  ],
  [ // cat, otter, penguin, fox
    (_m('Вы гуляете по городу', 'You’re walking around the city', 'Ви гуляєте містом'), [
      _m('Иду чуть впереди, куда мне интересно', 'I walk a bit ahead, wherever I like', 'Іду трохи попереду, куди мені цікаво'),
      _m('Иду вплотную, плечом к плечу', 'I walk right beside them, shoulder to shoulder', 'Іду впритул, пліч-о-пліч'),
      _m('Подбираю для партнёра красивый листик', 'I pick up a pretty leaf for my partner', 'Підбираю для партнера гарний листочок'),
      _m('Сворачиваю в незнакомые дворы', 'I turn into unfamiliar courtyards', 'Звертаю в незнайомі двори'),
    ]),
    (_m('Партнёр предлагает съехаться', 'Your partner suggests moving in together', 'Партнер пропонує з’їхатися'), [
      _m('Соглашаюсь, если у меня будет свой угол', 'I agree if I get a corner of my own', 'Погоджуюся, якщо в мене буде свій куток'),
      _m('Да! Наконец-то каждый вечер вместе', 'Yes! Finally every evening together', 'Так! Нарешті щовечора разом'),
      _m('Да, я давно этого жду', 'Yes, I’ve been waiting for this', 'Так, я давно цього чекаю'),
      _m('Давай, а через год переедем в другую страну', 'Sure, and in a year let’s move abroad', 'Давай, а за рік переїдемо в іншу країну'),
    ]),
    (_m('Чем вы заняты, пока партнёр работает вечером', 'What you do while your partner works in the evening', 'Чим ви зайняті, поки партнер працює ввечері'), [
      _m('Наконец-то своими делами', 'Finally my own things', 'Нарешті своїми справами'),
      _m('Сижу рядом и тихонько трогаю за руку', 'I sit nearby and quietly touch their hand', 'Сиджу поруч і тихенько торкаюся руки'),
      _m('Готовлю маленький сюрприз', 'I prepare a little surprise', 'Готую маленький сюрприз'),
      _m('Придумываю, куда мы пойдём потом', 'I plan where we’ll go afterwards', 'Вигадую, куди ми підемо потім'),
    ]),
  ],
  [ // dog, koala, hedgehog, bear
    (_m('Утро понедельника', 'Monday morning', 'Ранок понеділка'), [
      _m('Бужу партнёра поцелуями', 'I wake my partner with kisses', 'Буджу партнера поцілунками'),
      _m('Не встаю, пока меня не вытащат', 'I don’t get up until someone drags me out', 'Не встаю, поки мене не витягнуть'),
      _m('До кофе со мной лучше не разговаривать', 'Better not talk to me before coffee', 'До кави зі мною краще не розмовляти'),
      _m('Встаю раньше и готовлю завтрак на двоих', 'I get up earlier and make breakfast for two', 'Встаю раніше й готую сніданок на двох'),
    ]),
    (_m('Партнёр хочет завести питомца', 'Your partner wants to get a pet', 'Партнер хоче завести улюбленця'), [
      _m('Ура, давай прямо сегодня', 'Yay, let’s do it today', 'Ура, давай просто сьогодні'),
      _m('Только если он будет спать с нами', 'Only if it sleeps with us', 'Тільки якщо він спатиме з нами'),
      _m('Сначала решим, кто будет за ним ухаживать', 'First let’s decide who’ll look after it', 'Спершу вирішимо, хто буде за ним доглядати'),
      _m('Уже читаю, как о нём заботиться', 'I’m already reading up on how to care for it', 'Уже читаю, як про нього дбати'),
    ]),
    (_m('Партнёра кто-то обидел', 'Someone hurt your partner', 'Партнера хтось образив'), [
      _m('Кручусь рядом и утешаю как могу', 'I fuss around and comfort them as best I can', 'Кручуся поруч і втішаю як можу'),
      _m('Утаскиваю под плед, пусть мир подождёт', 'I drag them under a blanket, the world can wait', 'Затягую під плед, хай світ почекає'),
      _m('Выпускаю иголки на обидчика', 'I show my spikes to whoever did it', 'Випускаю голки на кривдника'),
      _m('Иду разбираться', 'I go and sort it out', 'Іду розбиратися'),
    ]),
  ],
  [ // cat, bear, otter, fox
    (_m('Партнёр зовёт в новое хобби на двоих', 'Your partner suggests a new hobby for two', 'Партнер кличе в нове хобі на двох'), [
      _m('Попробую, но без обещаний', 'I’ll try, no promises', 'Спробую, але без обіцянок'),
      _m('Сразу покупаю всё нужное для обоих', 'I buy everything we both need right away', 'Одразу купую все потрібне для обох'),
      _m('Да, главное — вместе', 'Yes, what matters is doing it together', 'Так, головне — разом'),
      _m('А давай сразу прыжок с парашютом', 'Let’s go straight for skydiving', 'А давай одразу стрибок з парашутом'),
    ]),
    (_m('На улице гроза', 'There’s a thunderstorm outside', 'Надворі гроза'), [
      _m('Сворачиваюсь клубком и никуда не иду', 'I curl up and go nowhere', 'Згортаюся клубочком і нікуди не йду'),
      _m('Проверяю, все ли дома', 'I check that everyone is home', 'Перевіряю, чи всі вдома'),
      _m('Прижимаюсь к партнёру', 'I snuggle up to my partner', 'Пригортаюся до партнера'),
      _m('Бегу под дождь, это же весело', 'I run out into the rain, it’s fun', 'Біжу під дощ, це ж весело'),
    ]),
    (_m('Партнёр устал после работы', 'Your partner is tired after work', 'Партнер утомився після роботи'), [
      _m('Даю тишину и не лезу с расспросами', 'I give them quiet and don’t pry', 'Даю тишу й не лізу з розпитуваннями'),
      _m('Ужин уже ждёт на столе', 'Dinner is already on the table', 'Вечеря вже чекає на столі'),
      _m('Сажусь рядом и кладу голову на плечо', 'I sit close and rest my head on their shoulder', 'Сідаю поруч і кладу голову на плече'),
      _m('Рассказываю самую смешную историю за день', 'I tell the funniest story of my day', 'Розповідаю найсмішнішу історію за день'),
    ]),
  ],
  [ // dog, penguin, koala, hedgehog
    (_m('Праздник в семье партнёра', 'A celebration with your partner’s family', 'Свято в родині партнера'), [
      _m('Подружусь со всеми родственниками', 'I’ll make friends with every relative', 'Потоваришую з усіма родичами'),
      _m('Приду с подарком для каждого', 'I’ll bring a gift for each of them', 'Прийду з подарунком для кожного'),
      _m('Наемся и задремлю в кресле', 'I’ll eat well and doze off in an armchair', 'Наїмся й задрімаю в кріслі'),
      _m('Посижу тихо рядом с партнёром', 'I’ll sit quietly next to my partner', 'Посиджу тихо поруч із партнером'),
    ]),
    (_m('Первое свидание', 'A first date', 'Перше побачення'), [
      _m('Рассказываю о себе всё и сразу', 'I tell everything about myself at once', 'Розповідаю про себе все й одразу'),
      _m('Уже знаю: это мой человек', 'I already know: this is my person', 'Уже знаю: це моя людина'),
      _m('Выбираю кафе с самыми мягкими диванами', 'I pick the café with the softest couches', 'Обираю кав’ярню з найм’якшими диванами'),
      _m('Присматриваюсь и почти молчу', 'I watch closely and barely speak', 'Придивляюся й майже мовчу'),
    ]),
    (_m('Партнёр забыл о вашей дате', 'Your partner forgot your special date', 'Партнер забув про вашу дату'), [
      _m('Не обижаюсь, просто напоминаю', 'I don’t take offense, I just remind them', 'Не ображаюся, просто нагадую'),
      _m('Расстраиваюсь: для меня это важно', 'I get upset: it matters to me', 'Засмучуюся: для мене це важливо'),
      _m('Мне тоже было не до дат', 'I wasn’t thinking about dates either', 'Мені теж було не до дат'),
      _m('Колюсь весь вечер, потом прощаю', 'I’m prickly all evening, then forgive', 'Колюся весь вечір, потім прощаю'),
    ]),
  ],
  [ // cat, dog, bear, penguin
    (_m('Партнёр просит совета', 'Your partner asks for advice', 'Партнер просить поради'), [
      _m('Отвечаю коротко и по делу', 'I answer briefly and to the point', 'Відповідаю коротко й по суті'),
      _m('Поддерживаю любое решение', 'I back any decision', 'Підтримую будь-яке рішення'),
      _m('Разбираю всё по полочкам и помогаю', 'I break it all down and help', 'Розкладаю все по поличках і допомагаю'),
      _m('Советую от сердца и остаюсь рядом', 'I advise from the heart and stay close', 'Раджу від серця й лишаюся поруч'),
    ]),
    (_m('Годовщина через неделю', 'Your anniversary is in a week', 'Річниця за тиждень'), [
      _m('Вспомню накануне', 'I’ll remember the day before', 'Згадаю напередодні'),
      _m('Считаю дни и не могу дождаться', 'I count the days and can’t wait', 'Рахую дні й не можу дочекатися'),
      _m('Всё уже забронировано', 'Everything is already booked', 'Усе вже заброньовано'),
      _m('Делаю подарок своими руками', 'I’m making a gift by hand', 'Роблю подарунок власними руками'),
    ]),
    (_m('Вы ревнуете', 'You feel jealous', 'Ви ревнуєте'), [
      _m('Почти не ревную, у меня своя жизнь', 'I hardly get jealous, I have my own life', 'Майже не ревную, у мене своє життя'),
      _m('Ревную, но быстро забываю', 'I get jealous, but forget fast', 'Ревную, але швидко забуваю'),
      _m('Спокойно говорю партнёру, что мне неприятно', 'I calmly tell my partner it bothers me', 'Спокійно кажу партнерові, що мені неприємно'),
      _m('Нам не к кому ревновать: у нас есть только мы', 'There’s no one to be jealous of: we only have each other', 'Нам нема до кого ревнувати: у нас є тільки ми'),
    ]),
  ],
  [ // fox, otter, hedgehog, koala
    (_m('Ваше идеальное свидание', 'Your ideal date', 'Ваше ідеальне побачення'), [
      _m('Квест или что-то с адреналином', 'An escape room or something with adrenaline', 'Квест або щось з адреналіном'),
      _m('Каток, где можно держаться за руки', 'An ice rink where we can hold hands', 'Ковзанка, де можна триматися за руки'),
      _m('Тихий ресторан на двоих', 'A quiet restaurant for two', 'Тихий ресторан на двох'),
      _m('Дома, в пижамах', 'At home, in pajamas', 'Удома, у піжамах'),
    ]),
    (_m('Партнёр зовёт в поход', 'Your partner invites you camping', 'Партнер кличе в похід'), [
      _m('Уже собираю рюкзак', 'I’m already packing my backpack', 'Уже збираю рюкзак'),
      _m('Иду, если палатка одна на двоих', 'I’m in if we share one tent', 'Іду, якщо намет один на двох'),
      _m('Иду, если без шумной компании', 'I’m in if there’s no loud crowd', 'Іду, якщо без гучної компанії'),
      _m('Можно я посплю в машине?', 'Can I sleep in the car?', 'Можна я посплю в машині?'),
    ]),
    (_m('Вы ждёте партнёра у кино', 'You’re waiting for your partner outside the cinema', 'Ви чекаєте партнера біля кіно'), [
      _m('Придумываю, как удивить при встрече', 'I think up a way to surprise them', 'Вигадую, як здивувати при зустрічі'),
      _m('Высматриваю, чтобы сразу взять за руку', 'I watch for them so I can take their hand right away', 'Виглядаю, щоб одразу взяти за руку'),
      _m('Злюсь, если опаздывают хоть на минуту', 'I get annoyed if they’re even a minute late', 'Злюся, якщо запізнюються хоч на хвилину'),
      _m('Сажусь на лавочку и дремлю', 'I sit on a bench and doze', 'Сідаю на лавку й дрімаю'),
    ]),
  ],
  [ // cat, dog, otter, bear
    (_m('Партнёр возвращается из поездки', 'Your partner comes back from a trip', 'Партнер повертається з поїздки'), [
      _m('Делаю вид, что ничего особенного', 'I act like it’s no big deal', 'Вдаю, що нічого особливого'),
      _m('Встречаю в аэропорту с плакатом', 'I meet them at the airport with a sign', 'Зустрічаю в аеропорту з плакатом'),
      _m('До вечера не отлипаю от партнёра', 'I stick to my partner until evening', 'До вечора не відлипаю від партнера'),
      _m('Забираю чемодан и везу домой', 'I take the suitcase and drive them home', 'Забираю валізу й везу додому'),
    ]),
    (_m('Вы гуляете в парке', 'You’re walking in the park', 'Ви гуляєте в парку'), [
      _m('Отхожу посмотреть на что-то своё', 'I wander off to look at my own thing', 'Відходжу подивитися на щось своє'),
      _m('Бегаю и радуюсь всему вокруг', 'I run around happy about everything', 'Бігаю й радію всьому навколо'),
      _m('Иду, прижавшись к партнёру', 'I walk pressed close to my partner', 'Іду, пригорнувшись до партнера'),
      _m('Несу сумку и плед на двоих', 'I carry the bag and a blanket for two', 'Несу сумку й плед на двох'),
    ]),
    (_m('Как вы встречаете Новый год', 'How you see in the New Year', 'Як ви зустрічаєте Новий рік'), [
      _m('Тихо дома, без гостей', 'Quietly at home, no guests', 'Тихо вдома, без гостей'),
      _m('Большой компанией, с объятиями в полночь', 'With a big crowd and hugs at midnight', 'Великою компанією, з обіймами опівночі'),
      _m('Загадываем желание, держась за руки', 'We make a wish holding hands', 'Загадуємо бажання, тримаючись за руки'),
      _m('Накрываю стол на всех', 'I set the table for everyone', 'Накриваю стіл для всіх'),
    ]),
  ],
];

// Как вы ссоритесь: пятнадцать пар стилей. Первые десять — каждая пара по
// разу, ещё пять идут по кругу, так что каждый стиль встречается ровно шесть
// раз. У пары четыре варианта текста, первый — основной.
final Map<String, String> _fightQ = _m('Что вам ближе в споре?', 'Which is more like you in an argument?', 'Що вам ближче в суперечці?');

final List<(String, String, List<(Map<String, String>, Map<String, String>)>)> _fightSlots = [
  ('push', 'yield', [
    (_m('Я отстаиваю своё мнение до конца', 'I defend my view to the end', 'Я відстоюю свою думку до кінця'),
     _m('Я соглашаюсь, лишь бы не ругаться', 'I agree just to avoid a fight', 'Я погоджуюся, аби не сваритися')),
    (_m('Я говорю, что думаю, даже если это обидно', 'I say what I think, even if it stings', 'Я кажу, що думаю, навіть якщо це образливо'),
     _m('Я уступаю, даже когда мне это не нравится', 'I give in even when I don’t like it', 'Я поступаюся, навіть коли мені це не подобається')),
    (_m('Я не сдаюсь, пока партнёр не признает мою правоту', 'I don’t back down until my partner admits I’m right', 'Я не здаюся, поки партнер не визнає, що я маю рацію'),
     _m('Я извиняюсь, даже если вины моей нет', 'I apologize even when it isn’t my fault', 'Я вибачаюся, навіть якщо моєї провини немає')),
    (_m('Я привожу доводы, пока не переспорю', 'I keep making points until I win', 'Я наводжу аргументи, поки не переспорю'),
     _m('Мне проще сделать, как хочет партнёр', 'It’s easier to do what my partner wants', 'Мені простіше зробити, як хоче партнер')),
  ]),
  ('push', 'avoid', [
    (_m('Я повышаю голос, когда меня не слышат', 'I raise my voice when I’m not heard', 'Я підвищую голос, коли мене не чують'),
     _m('Я ухожу в другую комнату, пока не остыну', 'I go to another room until I cool down', 'Я йду в іншу кімнату, поки не охолону')),
    (_m('Мне важно выиграть спор', 'Winning the argument matters to me', 'Мені важливо виграти суперечку'),
     _m('Я перевожу разговор на другую тему', 'I change the subject', 'Я переводжу розмову на іншу тему')),
    (_m('Я настаиваю, когда правда на моей стороне', 'I insist when the truth is on my side', 'Я наполягаю, коли правда на моєму боці'),
     _m('Я молчу и жду, когда пройдёт само', 'I stay quiet and wait for it to pass', 'Я мовчу й чекаю, поки мине саме')),
    (_m('Я сразу говорю, что мне не нравится', 'I say right away what I don’t like', 'Я одразу кажу, що мені не подобається'),
     _m('Я откладываю неприятный разговор на потом', 'I put off the unpleasant talk', 'Я відкладаю неприємну розмову на потім')),
  ]),
  ('push', 'trade', [
    (_m('Я не отступаю, даже когда спор затянулся', 'I don’t retreat even when the fight drags on', 'Я не відступаю, навіть коли суперечка затяглася'),
     _m('Я предлагаю уступить друг другу понемногу', 'I suggest we each give a little', 'Я пропоную поступитися одне одному потроху')),
    (_m('Я доказываю свою точку зрения фактами', 'I prove my point with facts', 'Я доводжу свою думку фактами'),
     _m('Я ищу вариант, где каждый что-то получит', 'I look for an option where each of us gets something', 'Я шукаю варіант, де кожен щось отримає')),
    (_m('Я спорю, пока последнее слово не останется за мной', 'I argue until I get the last word', 'Я сперечаюся, поки останнє слово не залишиться за мною'),
     _m('Я отдаю половину своего, если партнёр отдаст половину своего', 'I give up half of mine if my partner gives up half of theirs', 'Я віддаю половину свого, якщо партнер віддасть половину свого')),
    (_m('Я не стесняюсь давить, если дело важное', 'I don’t mind pushing if it matters', 'Я не соромлюся тиснути, якщо справа важлива'),
     _m('Я предлагаю: сегодня по-твоему, завтра по-моему', 'I suggest: your way today, mine tomorrow', 'Я пропоную: сьогодні по-твоєму, завтра по-моєму')),
  ]),
  ('push', 'solve', [
    (_m('Я стою на своём, даже если партнёр расстроен', 'I stand my ground even if my partner is upset', 'Я стою на своєму, навіть якщо партнер засмучений'),
     _m('Я спрашиваю, что для партнёра на самом деле важно', 'I ask what really matters to my partner', 'Я питаю, що для партнера насправді важливо')),
    (_m('Мне трудно признать свою ошибку', 'It’s hard for me to admit a mistake', 'Мені важко визнати свою помилку'),
     _m('Я предлагаю сесть и разобраться вместе', 'I suggest we sit down and figure it out together', 'Я пропоную сісти й розібратися разом')),
    (_m('Я требую объяснений здесь и сейчас', 'I demand an explanation here and now', 'Я вимагаю пояснень тут і зараз'),
     _m('Я ищу решение, от которого выиграют оба', 'I look for a solution where we both win', 'Я шукаю рішення, від якого виграють обоє')),
    (_m('Я перебиваю, когда слышу неправду', 'I interrupt when I hear something untrue', 'Я перебиваю, коли чую неправду'),
     _m('Я говорю о своих чувствах и слушаю о чувствах партнёра', 'I share my feelings and listen to my partner’s', 'Я говорю про свої почуття й слухаю про почуття партнера')),
  ]),
  ('yield', 'avoid', [
    (_m('Я молча принимаю решение партнёра', 'I silently accept my partner’s decision', 'Я мовчки приймаю рішення партнера'),
     _m('Я делаю вид, что ничего не случилось', 'I act like nothing happened', 'Я вдаю, що нічого не сталося')),
    (_m('Я забываю о своих желаниях ради мира', 'I forget what I want for the sake of peace', 'Я забуваю про свої бажання заради миру'),
     _m('Я отвечаю коротко и закрываюсь', 'I give short answers and shut down', 'Я відповідаю коротко й закриваюся')),
    (_m('Я сдаюсь раньше партнёра', 'I give up before my partner does', 'Я здаюся раніше за партнера'),
     _m('Я ухожу гулять, чтобы не ругаться', 'I go for a walk to avoid fighting', 'Я йду гуляти, щоб не сваритися')),
    (_m('Я говорю «ладно», хотя думаю иначе', 'I say “fine” though I think otherwise', 'Я кажу «гаразд», хоча думаю інакше'),
     _m('О проблеме я вообще не заговариваю', 'I don’t bring up the problem at all', 'Про проблему я взагалі не заговорюю')),
  ]),
  ('yield', 'trade', [
    (_m('Я ставлю чувства партнёра выше своей правоты', 'I put my partner’s feelings above being right', 'Я ставлю почуття партнера вище за свою правоту'),
     _m('Я торгуюсь, пока мы не найдём середину', 'I bargain until we find the middle', 'Я торгуюся, поки ми не знайдемо середину')),
    (_m('Я отказываюсь от своего плана, чтобы партнёру было хорошо', 'I drop my plan so my partner feels good', 'Я відмовляюся від свого плану, щоб партнерові було добре'),
     _m('Я уступаю в одном, если партнёр уступит в другом', 'I give in on one thing if my partner gives in on another', 'Я поступаюся в одному, якщо партнер поступиться в іншому')),
    (_m('Я подстраиваюсь, чтобы не расстраивать партнёра', 'I adjust so as not to upset my partner', 'Я підлаштовуюся, щоб не засмучувати партнера'),
     _m('Если не договорились, я предлагаю чередовать', 'If we can’t agree, I suggest taking turns', 'Якщо не домовилися, я пропоную чергувати')),
    (_m('Я не спорю, даже когда есть что сказать', 'I don’t argue even when I have something to say', 'Я не сперечаюся, навіть коли є що сказати'),
     _m('Я ищу решение побыстрее, пусть и не идеальное', 'I look for a quick fix, even if it’s not perfect', 'Я шукаю рішення швидше, хай і не ідеальне')),
  ]),
  ('yield', 'solve', [
    (_m('Я соглашаюсь на вариант партнёра, чтобы спор кончился', 'I take my partner’s option so the fight ends', 'Я погоджуюся на варіант партнера, щоб суперечка скінчилася'),
     _m('Я не успокаиваюсь, пока мы оба не будем довольны', 'I don’t rest until we’re both happy', 'Я не заспокоююся, поки ми обоє не будемо задоволені')),
    (_m('Я жертвую своим, чтобы сохранить тепло между нами', 'I sacrifice my own wishes to keep things warm between us', 'Я жертвую своїм, щоб зберегти тепло між нами'),
     _m('Я выкладываю всё, что меня беспокоит, и прошу партнёра о том же', 'I lay out everything that bothers me and ask my partner to do the same', 'Я викладаю все, що мене турбує, і прошу партнера про те саме')),
    (_m('Мне неловко настаивать на своём', 'I feel awkward insisting on my way', 'Мені ніяково наполягати на своєму'),
     _m('Я хочу понять, откуда на самом деле взялась ссора', 'I want to understand where the fight really came from', 'Я хочу зрозуміти, звідки насправді взялася сварка')),
    (_m('Я уступаю, если вижу, что партнёру это важнее', 'I give in if I see it matters more to my partner', 'Я поступаюся, якщо бачу, що партнерові це важливіше'),
     _m('Я предлагаю выписать варианты и выбрать лучший вместе', 'I suggest writing down options and picking the best one together', 'Я пропоную виписати варіанти й обрати найкращий разом')),
  ]),
  ('avoid', 'trade', [
    (_m('Когда назревает ссора, я прячусь в телефон', 'When a fight is brewing, I hide in my phone', 'Коли назріває сварка, я ховаюся в телефон'),
     _m('Спорное я делю пополам', 'I split the disputed thing down the middle', 'Спірне я ділю навпіл')),
    (_m('Я жду, что партнёр сам забудет', 'I wait for my partner to forget', 'Я чекаю, що партнер сам забуде'),
     _m('Я предлагаю меняться: в этот раз выбираешь ты', 'I suggest swapping: this time you choose', 'Я пропоную мінятися: цього разу обираєш ти')),
    (_m('Я отшучиваюсь, чтобы не говорить всерьёз', 'I joke so I don’t have to talk seriously', 'Я віджартовуюся, щоб не говорити всерйоз'),
     _m('Я соглашаюсь на компромисс, лишь бы двигаться дальше', 'I accept a compromise just to move on', 'Я погоджуюся на компроміс, аби рухатися далі')),
    (_m('Мне проще промолчать, чем выяснять отношения', 'It’s easier to stay silent than to have it out', 'Мені простіше змовчати, ніж з’ясовувати стосунки'),
     _m('Я ищу золотую середину', 'I look for the happy medium', 'Я шукаю золоту середину')),
  ]),
  ('avoid', 'solve', [
    (_m('Я обхожу острые темы', 'I steer clear of touchy subjects', 'Я обходжу гострі теми'),
     _m('Я ищу, в чём мы на самом деле согласны', 'I look for what we actually agree on', 'Я шукаю, у чому ми насправді згодні')),
    (_m('Я замолкаю на весь вечер', 'I go silent for the whole evening', 'Я замовкаю на весь вечір'),
     _m('Я трачу на разговор столько времени, сколько нужно', 'I give the talk as much time as it takes', 'Я витрачаю на розмову стільки часу, скільки треба')),
    (_m('Я ухожу спать, не договорив', 'I go to bed before we finish talking', 'Я йду спати, не договоривши'),
     _m('Я придумываю новый вариант, который устроит обоих', 'I come up with a new option that suits us both', 'Я вигадую новий варіант, який влаштує обох')),
    (_m('Я говорю «давай не сейчас»', 'I say “let’s not do this now”', 'Я кажу «давай не зараз»'),
     _m('Я переспрашиваю, правильно ли понимаю партнёра', 'I check that I understand my partner right', 'Я перепитую, чи правильно розумію партнера')),
  ]),
  ('trade', 'solve', [
    (_m('Я предлагаю что-то среднее между нашими идеями', 'I suggest something between our two ideas', 'Я пропоную щось середнє між нашими ідеями'),
     _m('Я говорю «давай решим это вместе»', 'I say “let’s solve this together”', 'Я кажу «давай розв’яжемо це разом»')),
    (_m('Честно, когда уступают оба', 'It’s fair when both give in', 'Чесно, коли поступаються обоє'),
     _m('Я смотрю на спор как на общую задачу', 'I see an argument as a shared problem to solve', 'Я дивлюся на суперечку як на спільне завдання')),
    (_m('Я помню, кто уступал в прошлый раз', 'I keep track of who gave in last time', 'Я пам’ятаю, хто поступався минулого разу'),
     _m('Я ищу причину, а не виноватого', 'I look for the cause, not someone to blame', 'Я шукаю причину, а не винного')),
    (_m('Я отказываюсь от части желаний ради общего решения', 'I drop some of my wishes for a shared decision', 'Я відмовляюся від частини бажань заради спільного рішення'),
     _m('Я прошу партнёра рассказать свою сторону целиком', 'I ask my partner to tell their whole side', 'Я прошу партнера розповісти свій бік повністю')),
  ]),
  ('push', 'yield', [
    (_m('Спор чаще начинаю я', 'I’m usually the one who starts the argument', 'Суперечку частіше починаю я'),
     _m('На уступки обычно иду я', 'I’m usually the one who gives in', 'На поступки зазвичай іду я')),
    (_m('Я не меняю решение под давлением', 'I don’t change my mind under pressure', 'Я не змінюю рішення під тиском'),
     _m('Я прошу прощения, чтобы вернуть мир', 'I say sorry to bring back the peace', 'Я прошу вибачення, щоб повернути мир')),
    (_m('Я отвечаю резко, если меня задели', 'I snap back if I’m hurt', 'Я відповідаю різко, якщо мене зачепили'),
     _m('Я соглашаюсь, даже если потом жалею', 'I agree even if I regret it later', 'Я погоджуюся, навіть якщо потім шкодую')),
    (_m('Я веду спор, как соревнование', 'I treat an argument like a competition', 'Я веду суперечку, як змагання'),
     _m('Мне важнее, чтобы партнёру было спокойно', 'My partner’s peace of mind matters more to me', 'Мені важливіше, щоб партнерові було спокійно')),
  ]),
  ('yield', 'avoid', [
    (_m('Я легко меняю мнение вслед за партнёром', 'I easily change my mind to match my partner', 'Я легко змінюю думку слідом за партнером'),
     _m('Я держу недовольство в себе', 'I keep my discontent to myself', 'Я тримаю невдоволення в собі')),
    (_m('Последнее слово я оставляю партнёру', 'I leave the last word to my partner', 'Останнє слово я залишаю партнерові'),
     _m('Я ухожу от прямого вопроса', 'I dodge a direct question', 'Я ухиляюся від прямого питання')),
    (_m('Я терплю, лишь бы не было ссоры', 'I put up with it as long as there’s no fight', 'Я терплю, аби не було сварки'),
     _m('Я отдаляюсь на пару дней, пока всё не уляжется', 'I pull away for a couple of days until it settles', 'Я віддаляюся на пару днів, поки все не вляжеться')),
    (_m('В мелочах я уступаю, чтобы не тратить нервы', 'I give in on small things to save my nerves', 'У дрібницях я поступаюся, щоб не витрачати нерви'),
     _m('Больную тему я обхожу стороной', 'I steer around the sore subject', 'Болючу тему я оминаю')),
  ]),
  ('avoid', 'trade', [
    (_m('Я надеюсь, что всё решится без разговора', 'I hope it’ll sort itself out without a talk', 'Я сподіваюся, що все розв’яжеться без розмови'),
     _m('Я предлагаю попробовать и так, и так', 'I suggest we try it both ways', 'Я пропоную спробувати і так, і так')),
    (_m('Я ухожу с головой в дела, лишь бы не ссориться', 'I bury myself in work to avoid fighting', 'Я поринаю в справи, аби не сваритися'),
     _m('Я ищу вариант, на который оба согласятся без восторга', 'I look for an option we can both live with', 'Я шукаю варіант, на який обоє погодяться без захвату')),
    (_m('Я говорю «всё нормально», хотя это не так', 'I say “it’s fine” when it isn’t', 'Я кажу «все нормально», хоча це не так'),
     _m('Я договариваюсь: ты мне это, я тебе то', 'I make a deal: you do this, I do that', 'Я домовляюся: ти мені це, я тобі те')),
    (_m('Я обрываю спор на полуслове', 'I cut the argument off mid-sentence', 'Я обриваю суперечку на півслові'),
     _m('Я ищу вариант, который никого не обидит', 'I look for an option that won’t hurt anyone', 'Я шукаю варіант, який нікого не образить')),
  ]),
  ('trade', 'solve', [
    (_m('Я уступаю ровно столько, сколько уступает партнёр', 'I give in exactly as much as my partner does', 'Я поступаюся рівно стільки, скільки поступається партнер'),
     _m('Я ищу решение, после которого не останется обиды', 'I look for a solution that leaves no hard feelings', 'Я шукаю рішення, після якого не залишиться образи')),
    (_m('Если спор зашёл в тупик, я предлагаю ничью', 'If we’re stuck, I suggest calling it a draw', 'Якщо суперечка зайшла в глухий кут, я пропоную нічию'),
     _m('Я прямо говорю, чего хочу, и спрашиваю, чего хочет партнёр', 'I say plainly what I want and ask what my partner wants', 'Я прямо кажу, чого хочу, і питаю, чого хоче партнер')),
    (_m('Я быстро соглашаюсь на середину, чтобы не тратить время', 'I quickly settle on the middle to save time', 'Я швидко погоджуюся на середину, щоб не гаяти час'),
     _m('Я предлагаю передохнуть и вернуться с идеями', 'I suggest a break and coming back with ideas', 'Я пропоную перепочити й повернутися з ідеями')),
    (_m('Я считаю, что лучше половина, чем ничего', 'I think half is better than nothing', 'Я вважаю, що краще половина, ніж нічого'),
     _m('Я ищу выход, о котором мы раньше не думали', 'I look for a way out we hadn’t thought of', 'Я шукаю вихід, про який ми раніше не думали')),
  ]),
  ('solve', 'push', [
    (_m('Я хочу, чтобы после спора мы стали ближе', 'I want us to be closer after an argument', 'Я хочу, щоб після суперечки ми стали ближчими'),
     _m('Я вспоминаю прошлые ошибки партнёра, чтобы доказать своё', 'I bring up my partner’s past mistakes to make my point', 'Я згадую минулі помилки партнера, щоб довести своє')),
    (_m('Я помогаю нам обоим услышать друг друга', 'I help us both hear each other', 'Я допомагаю нам обом почути одне одного'),
     _m('Я хочу, чтобы всё было по-моему', 'I want things my way', 'Я хочу, щоб усе було по-моєму')),
    (_m('Я разбираю ссору, чтобы она не повторилась', 'I unpack a fight so it doesn’t happen again', 'Я розбираю сварку, щоб вона не повторилася'),
     _m('Я дожимаю разговор до конца', 'I push the talk through to the end', 'Я дотискаю розмову до кінця')),
    (_m('Я обсуждаю, как нам лучше спорить в следующий раз', 'I talk about how we can argue better next time', 'Я обговорюю, як нам краще сперечатися наступного разу'),
     _m('Я твёрдо говорю «нет», когда мне что-то не подходит', 'I firmly say “no” when something doesn’t suit me', 'Я твердо кажу «ні», коли мені щось не підходить')),
  ]),
];

// Насколько вы похожи: пятнадцать тем, у каждой четыре «или-или».
final Map<String, String> _alikeQ = _m('Что вам ближе?', 'Which is more you?', 'Що вам ближче?');

final List<List<(Map<String, String>, Map<String, String>)>> _alikeSlots = [
  [ // отдых
    (_m('Море', 'The sea', 'Море'), _m('Горы', 'The mountains', 'Гори')),
    (_m('Палатка', 'A tent', 'Намет'), _m('Отель', 'A hotel', 'Готель')),
    (_m('Пляж', 'The beach', 'Пляж'), _m('Экскурсии', 'Sightseeing', 'Екскурсії')),
    (_m('Отпуск летом', 'A summer vacation', 'Відпустка влітку'), _m('Отпуск зимой', 'A winter vacation', 'Відпустка взимку')),
  ],
  [ // режим
    (_m('Сова', 'A night owl', 'Сова'), _m('Жаворонок', 'An early bird', 'Жайворонок')),
    (_m('Ранний подъём', 'Getting up early', 'Ранній підйом'), _m('Поспать подольше', 'Sleeping in', 'Поспати довше')),
    (_m('Поздний ужин', 'A late dinner', 'Пізня вечеря'), _m('Ранний ужин', 'An early dinner', 'Рання вечеря')),
    (_m('Поспать днём', 'A daytime nap', 'Поспати вдень'), _m('Днём не спать', 'No naps', 'Вдень не спати')),
  ],
  [ // еда
    (_m('Сладкое', 'Sweet', 'Солодке'), _m('Солёное', 'Salty', 'Солоне')),
    (_m('Пицца', 'Pizza', 'Піца'), _m('Суши', 'Sushi', 'Суші')),
    (_m('Готовить дома', 'Cooking at home', 'Готувати вдома'), _m('Заказывать еду', 'Ordering in', 'Замовляти їжу')),
    (_m('Острое', 'Spicy', 'Гостре'), _m('Неострое', 'Mild', 'Негостре')),
  ],
  [ // напитки
    (_m('Кофе', 'Coffee', 'Кава'), _m('Чай', 'Tea', 'Чай')),
    (_m('Сок', 'Juice', 'Сік'), _m('Газировка', 'Soda', 'Газована вода')),
    (_m('Холодные напитки', 'Cold drinks', 'Холодні напої'), _m('Горячие напитки', 'Hot drinks', 'Гарячі напої')),
    (_m('Молочный коктейль', 'A milkshake', 'Молочний коктейль'), _m('Смузи', 'A smoothie', 'Смузі')),
  ],
  [ // погода
    (_m('Лето', 'Summer', 'Літо'), _m('Зима', 'Winter', 'Зима')),
    (_m('Дождь', 'Rain', 'Дощ'), _m('Снег', 'Snow', 'Сніг')),
    (_m('Жара', 'Heat', 'Спека'), _m('Прохлада', 'Cool weather', 'Прохолода')),
    (_m('Осень', 'Autumn', 'Осінь'), _m('Весна', 'Spring', 'Весна')),
  ],
  [ // дом
    (_m('Город', 'The city', 'Місто'), _m('Деревня', 'The countryside', 'Село')),
    (_m('Квартира', 'An apartment', 'Квартира'), _m('Свой дом', 'A house of my own', 'Свій дім')),
    (_m('Идеальный порядок', 'Perfect order', 'Ідеальний порядок'), _m('Творческий беспорядок', 'Creative mess', 'Творчий безлад')),
    (_m('Минимализм', 'Minimalism', 'Мінімалізм'), _m('Много вещей', 'Lots of stuff', 'Багато речей')),
  ],
  [ // досуг
    (_m('Фильм', 'A movie', 'Фільм'), _m('Сериал', 'A series', 'Серіал')),
    (_m('Книга', 'A book', 'Книжка'), _m('Подкаст', 'A podcast', 'Подкаст')),
    (_m('Комедия', 'Comedy', 'Комедія'), _m('Ужасы', 'Horror', 'Жахи')),
    (_m('Настолки', 'Board games', 'Настолки'), _m('Видеоигры', 'Video games', 'Відеоігри')),
  ],
  [ // питомцы
    (_m('Кошки', 'Cats', 'Коти'), _m('Собаки', 'Dogs', 'Собаки')),
    (_m('Рыбки', 'Fish', 'Рибки'), _m('Попугай', 'A parrot', 'Папуга')),
    (_m('Хомяк', 'A hamster', 'Хом’як'), _m('Черепаха', 'A turtle', 'Черепаха')),
    (_m('Без питомцев', 'No pets', 'Без улюбленців'), _m('Целый зоопарк', 'A whole zoo', 'Цілий зоопарк')),
  ],
  [ // общение
    (_m('Позвонить', 'Calling', 'Подзвонити'), _m('Написать', 'Texting', 'Написати')),
    (_m('Голосовое', 'A voice message', 'Голосове'), _m('Текстом', 'In writing', 'Текстом')),
    (_m('Большая компания', 'A big crowd', 'Велика компанія'), _m('Пара близких друзей', 'A couple of close friends', 'Пара близьких друзів')),
    (_m('Вечеринка', 'A party', 'Вечірка'), _m('Вечер дома', 'A night in', 'Вечір удома')),
  ],
  [ // характер
    (_m('Планировать всё', 'Planning everything', 'Планувати все'), _m('Решать на ходу', 'Winging it', 'Вирішувати на ходу')),
    (_m('Приходить заранее', 'Arriving early', 'Приходити заздалегідь'), _m('Приходить впритык', 'Arriving just in time', 'Приходити впритул')),
    (_m('Сначала думать', 'Think first', 'Спершу думати'), _m('Сначала делать', 'Act first', 'Спершу робити')),
    (_m('Список дел', 'A to-do list', 'Список справ'), _m('Всё в голове', 'All in my head', 'Усе в голові')),
  ],
  [ // деньги
    (_m('Копить', 'Saving', 'Заощаджувати'), _m('Тратить', 'Spending', 'Витрачати')),
    (_m('Наличные', 'Cash', 'Готівка'), _m('Карта', 'Card', 'Картка')),
    (_m('Покупать сразу', 'Buying right away', 'Купувати одразу'), _m('Долго выбирать', 'Choosing for ages', 'Довго обирати')),
    (_m('Подарок своими руками', 'A handmade gift', 'Подарунок власноруч'), _m('Подарок из магазина', 'A store-bought gift', 'Подарунок із крамниці')),
  ],
  [ // музыка
    (_m('Громкая музыка', 'Loud music', 'Гучна музика'), _m('Тишина', 'Silence', 'Тиша')),
    (_m('Наушники', 'Headphones', 'Навушники'), _m('Колонка', 'A speaker', 'Колонка')),
    (_m('Петь в душе', 'Singing in the shower', 'Співати в душі'), _m('Не петь вовсе', 'Never singing', 'Не співати взагалі')),
    (_m('Живой концерт', 'A live concert', 'Живий концерт'), _m('Любимый плейлист', 'A favorite playlist', 'Улюблений плейлист')),
  ],
  [ // спорт
    (_m('Бег', 'Running', 'Біг'), _m('Йога', 'Yoga', 'Йога')),
    (_m('Утренняя зарядка', 'Morning exercise', 'Ранкова зарядка'), _m('Вечерняя тренировка', 'An evening workout', 'Вечірнє тренування')),
    (_m('Велосипед', 'A bike', 'Велосипед'), _m('Самокат', 'A scooter', 'Самокат')),
    (_m('Спортзал', 'The gym', 'Спортзал'), _m('Прогулка', 'A walk', 'Прогулянка')),
  ],
  [ // поездки
    (_m('Самолёт', 'A plane', 'Літак'), _m('Поезд', 'A train', 'Потяг')),
    (_m('Знакомые места', 'Familiar places', 'Знайомі місця'), _m('Новые страны', 'New countries', 'Нові країни')),
    (_m('Чемодан', 'A suitcase', 'Валіза'), _m('Рюкзак', 'A backpack', 'Рюкзак')),
    (_m('С маршрутом', 'With a route', 'З маршрутом'), _m('Без плана', 'No plan', 'Без плану')),
  ],
  [ // вечер
    (_m('Свечи', 'Candles', 'Свічки'), _m('Яркий свет', 'Bright light', 'Яскраве світло')),
    (_m('Ванна', 'A bath', 'Ванна'), _m('Душ', 'A shower', 'Душ')),
    (_m('Спать в пижаме', 'Sleeping in pajamas', 'Спати в піжамі'), _m('Спать в футболке', 'Sleeping in a T-shirt', 'Спати у футболці')),
    (_m('Окно открыто', 'Window open', 'Вікно відчинене'), _m('Окно закрыто', 'Window closed', 'Вікно зачинене')),
  ],
];

/// Сколько вопросов в одном прохождении (слотов).
int quizSlotCount(QuizKind kind) => switch (kind) {
      QuizKind.lang => _langPairs.length,
      QuizKind.attach => _attachItems.length,
      QuizKind.animal => _animalQs.length,
      QuizKind.fight => _fightSlots.length,
      QuizKind.alike => _alikeSlots.length,
    };

/// Сколько вариантов у слота [slot], основной вариант тоже считается.
int quizVariantCount(QuizKind kind, int slot) => switch (kind) {
      QuizKind.lang => 1 + _langExtra[slot].length,
      QuizKind.attach => 1 + _attachExtra[slot].length,
      QuizKind.animal => 1 + _animalExtra[slot].length,
      QuizKind.fight => _fightSlots[slot].$3.length,
      QuizKind.alike => _alikeSlots[slot].length,
    };

/// Набор по ключам вопросов (`alike_3_2`), например из ответов партнёра:
/// у «Насколько вы похожи» оба отвечают на одни и те же вопросы. Ключей не на
/// каждый слот или вариант вне банка — null.
List<int>? quizRoundFromKeys(QuizKind kind, Iterable<String> keys) {
  final round = List<int?>.filled(quizSlotCount(kind), null);
  for (final key in keys) {
    final parts = key.split('_');
    if (parts.length != 3 || parts[0] != kind.name) return null;
    final slot = int.tryParse(parts[1]), variant = int.tryParse(parts[2]);
    if (slot == null || variant == null || slot < 0 || slot >= round.length) return null;
    if (variant < 0 || variant >= quizVariantCount(kind, slot)) return null;
    round[slot] = variant;
  }
  if (round.contains(null)) return null;
  return [for (final v in round) v!];
}

/// Ключи вопросов набора — их запоминаем, чтобы в следующий раз дать другие.
List<String> quizRoundKeys(QuizKind kind, List<int> round) =>
    [for (var s = 0; s < round.length; s++) '${kind.name}_${s}_${round[s]}'];

/// Набор прохождения: по варианту на слот, по возможности не из [exclude].
List<int> pickQuizRound(QuizKind kind, Random random, {Set<String> exclude = const {}}) => [
      for (var s = 0; s < quizSlotCount(kind); s++)
        () {
          final all = List.generate(quizVariantCount(kind, s), (v) => v);
          final fresh = [for (final v in all) if (!exclude.contains('${kind.name}_${s}_$v')) v];
          final pool = fresh.isEmpty ? all : fresh;
          return pool[random.nextInt(pool.length)];
        }(),
    ];

/// Вопросы набора [round] (вариант на слот; по умолчанию основные).
List<QuizQuestion> quizQuestions(QuizKind kind, String lang, {List<int>? round}) {
  int v(int s) => round != null && s < round.length ? round[s] : 0;
  return switch (kind) {
    QuizKind.lang => [
        for (var i = 0; i < _langPairs.length; i++)
          QuizQuestion('lang_${i}_${v(i)}', _t(_langQ, lang), [
            QuizOption(_t(v(i) == 0 ? _langPairs[i].$2 : _langExtra[i][v(i) - 1].$1, lang), {_langPairs[i].$1: 1}),
            QuizOption(_t(v(i) == 0 ? _langPairs[i].$4 : _langExtra[i][v(i) - 1].$2, lang), {_langPairs[i].$3: 1}),
          ]),
      ],
    QuizKind.attach => [
        for (var i = 0; i < _attachItems.length; i++)
          QuizQuestion('attach_${i}_${v(i)}', _t(v(i) == 0 ? _attachItems[i].$3 : _attachExtra[i][v(i) - 1], lang), [
            for (var o = 0; o < 5; o++)
              QuizOption(_t(_likert[o], lang), {
                _attachItems[i].$1: _attachItems[i].$2 ? 5 - o : o + 1,
              }),
          ]),
      ],
    QuizKind.animal => [
        for (var i = 0; i < _animalQs.length; i++)
          QuizQuestion('animal_${i}_${v(i)}', _t(v(i) == 0 ? _animalQs[i].$1 : _animalExtra[i][v(i) - 1].$1, lang), [
            for (var o = 0; o < _animalQs[i].$2.length; o++)
              QuizOption(
                _t(v(i) == 0 ? _animalQs[i].$2[o].$2 : _animalExtra[i][v(i) - 1].$2[o], lang),
                {_animalQs[i].$2[o].$1: 1},
              ),
          ]),
      ],
    QuizKind.fight => [
        for (var i = 0; i < _fightSlots.length; i++)
          QuizQuestion('fight_${i}_${v(i)}', _t(_fightQ, lang), [
            QuizOption(_t(_fightSlots[i].$3[v(i)].$1, lang), {_fightSlots[i].$1: 1}),
            QuizOption(_t(_fightSlots[i].$3[v(i)].$2, lang), {_fightSlots[i].$2: 1}),
          ]),
      ],
    QuizKind.alike => [
        for (var i = 0; i < _alikeSlots.length; i++)
          QuizQuestion('alike_${i}_${v(i)}', _t(_alikeQ, lang), [
            QuizOption(_t(_alikeSlots[i][v(i)].$1, lang), const {'a': 1}),
            QuizOption(_t(_alikeSlots[i][v(i)].$2, lang), const {'b': 1}),
          ]),
      ],
  };
}

/// Ось утверждения привязанности (`anx` или `avo`) — для тестов и подсказок.
String attachItemAxis(QuizQuestion q) => q.options.first.score.keys.single;

/// Обратное утверждение: согласие с ним снижает шкалу.
bool attachItemReversed(QuizQuestion q) => q.options.first.score.values.single == 5;

/// Подсчёт. [answers] — индекс выбранного варианта на каждый вопрос по
/// порядку; лишние, недостающие и кривые ответы пропускаются. [round] нужен
/// «Насколько вы похожи»: ответ ложится под ключом своего варианта вопроса.
QuizResult scoreQuiz(QuizKind kind, List<int> answers, {List<int>? round}) {
  final qs = quizQuestions(kind, 'en', round: round);
  if (kind == QuizKind.alike) {
    return QuizResult(kind: kind, type: 'done', scores: {
      for (var i = 0; i < qs.length && i < answers.length; i++)
        if (answers[i] == 0 || answers[i] == 1) qs[i].key: answers[i].toDouble(),
    });
  }
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
  // Побеждает доля: у зверя из семи вопросов шесть ответов весят больше,
  // чем шесть у зверя из восьми.
  final scores = {for (final t in types) t: (sums[t] ?? 0) / (possible[t] ?? 1)};
  var best = types.first;
  for (final t in types) {
    if (scores[t]! > scores[best]!) best = t;
  }
  return QuizResult(kind: kind, type: best, scores: scores);
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

final Map<String, (Map<String, String>, Map<String, String>)> _fightTypes = {
  'push': (_m('Стою на своём', 'I stand my ground', 'Стою на своєму'), _m(
    'В споре вы держитесь за свою правду и редко сдаёте позиции. Это честно, но партнёру бывает трудно вставить слово.',
    'In an argument you hold on to your truth and rarely give ground. It’s honest, but your partner can struggle to get a word in.',
    'У суперечці ви тримаєтеся своєї правди й рідко здаєте позиції. Це чесно, але партнерові буває важко вставити слово.')),
  'yield': (_m('Уступаю', 'I give in', 'Поступаюся'), _m(
    'Мир вам дороже правоты, и вы легко уступаете. Только обида от каждой уступки никуда не девается, а копится.',
    'Peace matters more to you than being right, so you give in easily. But the hurt from each concession doesn’t vanish, it piles up.',
    'Мир вам дорожчий за правоту, і ви легко поступаєтеся. Тільки образа від кожної поступки нікуди не дівається, а накопичується.')),
  'avoid': (_m('Ухожу от спора', 'I step away', 'Уникаю суперечки'), _m(
    'Вы уходите от ссоры: молчите, переводите тему, ждёте, пока само пройдёт. Буря стихает, а вопрос остаётся нерешённым.',
    'You step away from fights: go quiet, change the subject, wait for it to pass. The storm calms down, but the issue stays unsolved.',
    'Ви уникаєте сварки: мовчите, переводите тему, чекаєте, поки мине саме. Буря вщухає, а питання лишається нерозв’язаним.')),
  'trade': (_m('Ищу середину', 'I meet halfway', 'Шукаю середину'), _m(
    'Вы ищете середину: немного уступить и немного выиграть. Выходит быстро, но порой каждый остаётся доволен только наполовину.',
    'You look for the middle: give a little, win a little. It’s quick, but sometimes each of you is only half happy.',
    'Ви шукаєте середину: трохи поступитися й трохи виграти. Виходить швидко, але часом кожен задоволений лише наполовину.')),
  'solve': (_m('Решаем вместе', 'We solve it together', 'Розв’язуємо разом'), _m(
    'Вы ищете решение, которое устроит обоих, даже если на разговор уйдёт весь вечер. Это самый трудный путь и самый надёжный.',
    'You look for a solution that works for both, even if the talk takes all evening. It’s the hardest way and the most reliable one.',
    'Ви шукаєте рішення, яке влаштує обох, навіть якщо на розмову піде весь вечір. Це найважчий шлях і найнадійніший.')),
};

/// Что поможет человеку с этим стилем в следующей ссоре — для общего итога.
final Map<String, Map<String, String>> _fightRule = {
  'push': _m('сначала дослушать другого, а уже потом спорить', 'hearing the other out before arguing', 'спершу дослухати іншого, а вже потім сперечатися'),
  'yield': _m('прямо говорить, чего хочется, а не соглашаться ради тишины', 'saying plainly what you want instead of agreeing for the sake of quiet',
      'прямо казати, чого хочеться, а не погоджуватися заради тиші'),
  'avoid': _m('договориться о паузе и вернуться к разговору в тот же день', 'agreeing on a pause and coming back to the talk the same day',
      'домовитися про паузу й повернутися до розмови того ж дня'),
  'trade': _m('сначала понять, что каждому по-настоящему важно, а потом уже делить пополам', 'first finding out what truly matters to each of you, then splitting',
      'спершу зрозуміти, що кожному по-справжньому важливо, а потім уже ділити навпіл'),
  'solve': _m('не тянуть разговор до ночи, если оба устали', 'not dragging the talk into the night when you’re both tired',
      'не тягнути розмову до ночі, якщо обоє втомилися'),
};

final Map<String, (Map<String, String>, Map<String, String>)> _alikeTypes = {
  'done': (_m('Ответы готовы', 'Your answers are in', 'Відповіді готові'), _m(
    'Партнёру достанутся те же вопросы. Совпадения и различия появятся в блоке «Вместе».',
    'Your partner gets the same questions. Matches and differences show up under “Together”.',
    'Партнерові дістануться ті самі питання. Збіги й відмінності з’являться в блоці «Разом».')),
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
      QuizKind.fight => _fightTypes[type],
      QuizKind.alike => _alikeTypes[type],
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
    case QuizKind.fight:
      final a = _t(_fightRule[mine]!, lang), b = _t(_fightRule[theirs]!, lang);
      if (mine == theirs) {
        final start = switch (mine) {
          'avoid' => pick('Вы оба уходите от разговора, поэтому обиды копятся.', 'You both step away from the talk, so the hurt piles up.',
              'Ви обоє уникаєте розмови, тому образи накопичуються.'),
          'push' => pick('Вы оба стоите на своём, и спор быстро разгорается.', 'You both stand your ground, so arguments flare up fast.',
              'Ви обоє стоїте на своєму, і суперечка швидко розгоряється.'),
          _ => pick('В ссоре вы ведёте себя одинаково.', 'You argue the same way.', 'У сварці ви поводитеся однаково.'),
        };
        return '$start ${pick('Правило на следующий раз: $a.', 'Rule for next time: $a.', 'Правило на наступний раз: $a.')}';
      }
      return pick('В следующей ссоре вам поможет $a, а партнёру — $b.',
          'Next time you argue, $a will help you, and $b will help your partner.',
          'У наступній сварці вам допоможе $a, а партнерові — $b.');
    case QuizKind.alike:
      return pick('Ответили оба. Пройдите тест заново, чтобы сравнить ответы.', 'You’ve both answered. Take the test again to compare.',
          'Відповіли обоє. Пройдіть тест знову, щоб порівняти відповіді.');
  }
}

/// «Насколько вы похожи»: совпадения по вопросам, на которые ответили оба.
class QuizMatch {
  const QuizMatch(this.same, this.total, this.diffs);
  final int same;
  final int total;

  /// Где ответы разошлись: свой ответ и ответ партнёра.
  final List<(String, String)> diffs;

  int get percent => total == 0 ? 0 : (same * 100 / total).round();
}

QuizMatch quizMatch(QuizResult mine, QuizResult theirs, String lang) {
  var same = 0, total = 0;
  final diffs = <(String, String)>[];
  for (final e in mine.scores.entries) {
    final other = theirs.scores[e.key];
    if (other == null) continue;
    final parts = e.key.split('_');
    final slot = int.tryParse(parts.length == 3 ? parts[1] : '');
    final variant = int.tryParse(parts.length == 3 ? parts[2] : '');
    if (slot == null || variant == null || slot >= _alikeSlots.length || variant >= _alikeSlots[slot].length) continue;
    total++;
    if (e.value == other) {
      same++;
      continue;
    }
    final pair = _alikeSlots[slot][variant];
    String side(double v) => _t(v == 0 ? pair.$1 : pair.$2, lang);
    diffs.add((side(e.value), side(other)));
  }
  return QuizMatch(same, total, diffs);
}

/// Общий итог пары для экрана и картинки: у «Насколько вы похожи» он
/// считается по самим ответам, у остальных — по типам.
String quizPairSummary(QuizResult mine, QuizResult theirs, String lang) {
  if (mine.kind != QuizKind.alike) return quizPairText(mine.kind, mine.type, theirs.type, lang);
  String pick(String ru, String en, String uk) => _t(_m(ru, en, uk), lang);
  final m = quizMatch(mine, theirs, lang);
  if (m.total == 0) {
    return pick('Вам достались разные вопросы. Пройдите тест заново: вопросы будут те же, что у партнёра.',
        'You got different questions. Take the test again: you’ll get the same ones as your partner.',
        'Вам дісталися різні питання. Пройдіть тест знову: питання будуть ті самі, що в партнера.');
  }
  final n = '${m.same} ${pick('из', 'of', 'з')} ${m.total}';
  if (m.percent >= 80) {
    return pick('Почти одинаковые: совпало $n. Договориться вам легко о чём угодно.',
        'Nearly the same: $n match. You can agree on almost anything.',
        'Майже однакові: збіглося $n. Домовитися вам легко про що завгодно.');
  }
  if (m.percent >= 50) {
    return pick('Похожи, но не копии: совпало $n. Различий как раз хватает, чтобы не скучать.',
        'Alike, but not copies: $n match. Just enough differences to keep it interesting.',
        'Схожі, але не копії: збіглося $n. Відмінностей якраз вистачає, щоб не нудьгувати.');
  }
  return pick('Противоположности: совпало $n. Зато вам есть чему поучиться друг у друга.',
      'Opposites: $n match. Which means you have plenty to learn from each other.',
      'Протилежності: збіглося $n. Зате вам є чого навчитися одне в одного.');
}
