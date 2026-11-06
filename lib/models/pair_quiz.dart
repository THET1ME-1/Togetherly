import 'dart:convert';
import 'dart:math';

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
  'share': _m('Поделиться', 'Share', 'Поділитися'),
  'save': _m('Сохранить', 'Save', 'Зберегти'),
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

// ── банк: запасные варианты каждого вопроса ─────────────────────────────────
//
// Как в «Умении любить», набор меняется от раза к разу. Вопрос — это слот:
// у каждого слота несколько вариантов с ТЕМИ ЖЕ типами на тех же местах,
// поэтому баланс (каждый язык и каждый зверь ровно четыре раза, шесть
// утверждений на ось) держится в любом наборе. Основной вариант — списки выше.

/// Ещё по два варианта на каждую пару языков, в том же порядке типов.
final List<List<(Map<String, String>, Map<String, String>)>> _langExtra = [
  [ // words / time
    (_m('Сообщение «думаю о тебе» посреди рабочего дня', 'A “thinking of you” text in the middle of the workday', 'Повідомлення «думаю про тебе» посеред робочого дня'),
     _m('Целый выходной только вдвоём', 'A whole day off, just the two of us', 'Цілий вихідний тільки удвох')),
    (_m('Партнёр хвалит то, что у меня получилось', 'My partner praises what I pulled off', 'Партнер хвалить те, що в мене вийшло'),
     _m('Партнёр слушает меня, ни на что не отвлекаясь', 'My partner listens to me with full attention', 'Партнер слухає мене, ні на що не відволікаючись')),
  ],
  [ // words / gifts
    (_m('Голосовое с признанием', 'A voice message with a confession', 'Голосове із зізнанням'),
     _m('Любимая сладость, купленная по дороге', 'My favorite treat, picked up on the way', 'Улюблена солодість, куплена дорогою')),
    (_m('Открытка с длинным письмом от руки', 'A card with a long handwritten letter', 'Листівка з довгим листом від руки'),
     _m('Подарок по моему случайному намёку', 'A gift based on a hint I dropped once', 'Подарунок за моїм випадковим натяком')),
  ],
  [ // words / acts
    (_m('Услышать «спасибо, что ты есть»', 'Hearing “thank you for being you”', 'Почути «дякую, що ти є»'),
     _m('Партнёр чинит то, что давно сломано', 'My partner fixes what has been broken for ages', 'Партнер лагодить те, що давно зламане')),
    (_m('Партнёр говорит, что верит в меня', 'My partner says they believe in me', 'Партнер каже, що вірить у мене'),
     _m('Партнёр сам закупает продукты на неделю', 'My partner does the weekly grocery run', 'Партнер сам закуповує продукти на тиждень')),
  ],
  [ // words / touch
    (_m('Ласковое прозвище', 'A sweet nickname', 'Ласкаве прізвисько'),
     _m('Поцелуй в лоб', 'A kiss on the forehead', 'Поцілунок у лоб')),
    (_m('Комплимент моей внешности', 'A compliment on how I look', 'Комплімент моїй зовнішності'),
     _m('Рука на моём плече в толпе', 'A hand on my shoulder in a crowd', 'Рука на моєму плечі в натовпі')),
  ],
  [ // time / gifts
    (_m('Свидание, которое партнёр сам спланировал', 'A date my partner planned all by themselves', 'Побачення, яке партнер сам спланував'),
     _m('Коробка с маленькими сюрпризами', 'A box of little surprises', 'Коробка з маленькими сюрпризами')),
    (_m('Вечер настольных игр вдвоём', 'A board game night for two', 'Вечір настільних ігор удвох'),
     _m('Книга, которую партнёр выбрал специально для меня', 'A book my partner chose just for me', 'Книжка, яку партнер обрав спеціально для мене')),
  ],
  [ // time / acts
    (_m('Поездка за город вдвоём', 'A trip out of town together', 'Поїздка за місто удвох'),
     _m('Партнёр убирает квартиру, пока меня нет', 'My partner cleans the place while I’m out', 'Партнер прибирає квартиру, поки мене немає')),
    (_m('Совместный завтрак без спешки', 'A slow breakfast together', 'Спільний сніданок без поспіху'),
     _m('Партнёр заранее собирает мне обед с собой', 'My partner packs me lunch ahead of time', 'Партнер заздалегідь збирає мені обід із собою')),
  ],
  [ // time / touch
    (_m('Готовить ужин вместе', 'Cooking dinner together', 'Готувати вечерю разом'),
     _m('Засыпать в обнимку', 'Falling asleep in each other’s arms', 'Засинати в обіймах')),
    (_m('Гулять ночью по городу', 'Walking around the city at night', 'Гуляти вночі містом'),
     _m('Партнёр гладит меня по волосам', 'My partner strokes my hair', 'Партнер гладить мене по волоссю')),
  ],
  [ // gifts / acts
    (_m('Фото в рамке с нашим общим моментом', 'A framed photo of a moment we shared', 'Фото в рамці з нашою спільною миттю'),
     _m('Партнёр делает за меня скучные звонки', 'My partner makes the boring calls for me', 'Партнер робить за мене нудні дзвінки')),
    (_m('Подарок на годовщину, придуманный заранее', 'An anniversary gift planned well ahead', 'Подарунок на річницю, вигаданий заздалегідь'),
     _m('Партнёр встречает меня горячим чаем после работы', 'My partner greets me with hot tea after work', 'Партнер зустрічає мене гарячим чаєм після роботи')),
  ],
  [ // gifts / touch
    (_m('Браслет или украшение на память', 'A bracelet or a keepsake piece of jewelry', 'Браслет чи прикраса на згадку'),
     _m('Обнять, едва увидев после разлуки', 'A hug the moment we meet after time apart', 'Обійняти, щойно побачивши після розлуки')),
    (_m('Плейлист, собранный специально для меня', 'A playlist made just for me', 'Плейлист, зібраний спеціально для мене'),
     _m('Сидеть рядом, касаясь плечами', 'Sitting close, shoulders touching', 'Сидіти поруч, торкаючись плечима')),
  ],
  [ // acts / touch
    (_m('Партнёр сам моет посуду после ужина', 'My partner does the dishes after dinner', 'Партнер сам миє посуд після вечері'),
     _m('Долгие объятия без слов', 'A long hug without words', 'Довгі обійми без слів')),
    (_m('Партнёр готовит мою любимую еду', 'My partner cooks my favorite food', 'Партнер готує мою улюблену їжу'),
     _m('Партнёр держит меня за руку в кино', 'My partner holds my hand at the movies', 'Партнер тримає мене за руку в кіно')),
  ],
];

/// Ещё по одному утверждению на каждый слот: та же ось и то же направление.
final List<Map<String, String>> _attachExtra = [
  _m('Мне страшно, что меня бросят', 'I’m scared of being left', 'Мені страшно, що мене покинуть'),
  _m('Мне неловко, когда партнёр говорит о чувствах', 'I feel awkward when my partner talks about feelings', 'Мені ніяково, коли партнер говорить про почуття'),
  _m('Я перечитываю переписку и ищу, не обиделся ли партнёр', 'I reread our chat looking for signs my partner is upset', 'Я перечитую листування й шукаю, чи не образився партнер'),
  _m('Слишком много времени вместе меня утомляет', 'Too much time together wears me out', 'Забагато часу разом мене втомлює'),
  _m('Мне важно, чтобы партнёр часто писал первым', 'I need my partner to text first often', 'Мені важливо, щоб партнер часто писав першим'),
  _m('Я легко делюсь с партнёром тем, что меня тревожит', 'I easily share what worries me with my partner', 'Я легко ділюся з партнером тим, що мене тривожить'),
  _m('Я ревную, даже если повода нет', 'I get jealous even without a reason', 'Я ревную, навіть якщо приводу немає'),
  _m('Когда что-то не так, я скорее замолчу, чем скажу', 'When something is wrong, I’d rather go quiet than say it', 'Коли щось не так, я радше замовкну, ніж скажу'),
  _m('Если партнёр занят, я спокойно жду', 'If my partner is busy, I wait calmly', 'Якщо партнер зайнятий, я спокійно чекаю'),
  _m('Мне нравится, когда мы знаем друг о друге всё', 'I like it when we know everything about each other', 'Мені подобається, коли ми знаємо одне про одного все'),
  _m('После ссоры мне трудно уснуть', 'After a fight it is hard for me to fall asleep', 'Після сварки мені важко заснути'),
  _m('Когда партнёр просит поговорить о нас, я ищу повод отложить', 'When my partner asks to talk about us, I look for a reason to put it off', 'Коли партнер просить поговорити про нас, я шукаю привід відкласти'),
];

/// Ещё по одному вопросу на каждый слот: те же звери в том же порядке.
final List<(Map<String, String>, List<Map<String, String>>)> _animalExtra = [
  (_m('Как вы отдыхаете в отпуске', 'How you spend a vacation', 'Як ви відпочиваєте у відпустці'), [
    _m('Каждый читает своё у бассейна', 'Each reading our own book by the pool', 'Кожен читає своє біля басейну'),
    _m('Везде вместе, куда бы ни пошли', 'Together everywhere, wherever we go', 'Скрізь разом, куди б не пішли'),
    _m('Каждый день новое место', 'A new place every day', 'Щодня нове місце'),
    _m('Номер, кровать и доставка еды', 'The room, the bed and food delivery', 'Номер, ліжко й доставка їжі'),
  ]),
  (_m('Партнёр замёрз', 'Your partner is cold', 'Партнер змерз'), [
    _m('Грею ладони партнёра в своих', 'I warm their hands in mine', 'Грію долоні партнера у своїх'),
    _m('Обнимаю целиком', 'I wrap them in a full hug', 'Обіймаю повністю'),
    _m('Ворчу и отдаю свою куртку', 'I grumble and hand over my jacket', 'Буркочу й віддаю свою куртку'),
    _m('Приношу горячий чай', 'I bring hot tea', 'Приношу гарячий чай'),
  ]),
  (_m('Партнёр опаздывает на свидание', 'Your partner is late for a date', 'Партнер запізнюється на побачення'), [
    _m('Не жду и занимаюсь своим', 'I don’t wait, I do my own thing', 'Не чекаю й займаюся своїм'),
    _m('Жду и радуюсь, когда наконец приходит', 'I wait and light up when they finally show', 'Чекаю й радію, коли нарешті приходить'),
    _m('Встречаю колкостью, но никуда не ухожу', 'I greet them with a jab, but I stay', 'Зустрічаю шпилькою, але нікуди не йду'),
    _m('Придумываю розыгрыш', 'I plot a little prank', 'Вигадую розіграш'),
  ]),
  (_m('Вы долго не виделись', 'You haven’t seen each other for a while', 'Ви довго не бачилися'), [
    _m('Весь день не отпускаю руку', 'I don’t let go of their hand all day', 'Увесь день не відпускаю руку'),
    _m('Делаю вид, что не так уж и скучаю', 'I act like I didn’t miss them that much', 'Вдаю, що не так уже й сумую'),
    _m('Сначала накормлю и укутаю', 'First I feed them and tuck them in', 'Спершу нагодую й закутаю'),
    _m('Обнимаемся и засыпаем', 'We cuddle and fall asleep', 'Обіймаємося й засинаємо'),
  ]),
  (_m('Новые знакомые партнёра', 'Your partner’s new friends', 'Нові знайомі партнера'), [
    _m('Быстро нахожу с ними общий язык', 'I get along with them right away', 'Швидко знаходжу з ними спільну мову'),
    _m('Присматриваюсь, пока не пойму, кто они', 'I keep my distance until I figure them out', 'Придивляюся, поки не зрозумію, хто вони'),
    _m('Сразу считаю их друзьями', 'I treat them as friends straight away', 'Одразу вважаю їх друзями'),
    _m('Мне хватает моего человека', 'My person is all I need', 'Мені вистачає моєї людини'),
  ]),
  (_m('У партнёра тяжёлый день', 'Your partner has a rough day', 'У партнера важкий день'), [
    _m('Беру всё на себя', 'I take everything on myself', 'Беру все на себе'),
    _m('Весь день пишу, что я рядом', 'I text all day that I’m here', 'Увесь день пишу, що я поруч'),
    _m('Готовлю сюрприз к вечеру', 'I plan a surprise for the evening', 'Готую сюрприз на вечір'),
    _m('Зову полежать вместе и ничего не делать', 'I invite them to lie down together and do nothing', 'Кличу полежати разом і нічого не робити'),
  ]),
  (_m('Что ранило бы вас сильнее', 'What would hurt you most', 'Що поранило б вас найбільше'), [
    _m('Измена', 'Cheating', 'Зрада'),
    _m('Холодность', 'Coldness', 'Холодність'),
    _m('Ненадёжность', 'Unreliability', 'Ненадійність'),
    _m('Скука', 'Boredom', 'Нудьга'),
  ]),
  (_m('Любимое место дома', 'Your favorite spot at home', 'Улюблене місце вдома'), [
    _m('Кровать', 'The bed', 'Ліжко'),
    _m('Свой угол, куда никто не лезет', 'My own corner nobody touches', 'Свій куток, куди ніхто не лізе'),
    _m('Диван, где мы вдвоём', 'The couch where we sit together', 'Диван, де ми вдвох'),
    _m('Подоконник с видом', 'A windowsill with a view', 'Підвіконня з краєвидом'),
  ]),
];

/// Сколько вопросов в одном прохождении (слотов).
int quizSlotCount(QuizKind kind) => switch (kind) {
      QuizKind.lang => _langPairs.length,
      QuizKind.attach => _attachItems.length,
      QuizKind.animal => _animalQs.length,
    };

/// Сколько вариантов у слота [slot], основной вариант тоже считается.
int quizVariantCount(QuizKind kind, int slot) => 1 + switch (kind) {
      QuizKind.lang => _langExtra[slot].length,
      QuizKind.attach => 1,
      QuizKind.animal => 1,
    };

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
          QuizQuestion('attach_${i}_${v(i)}', _t(v(i) == 0 ? _attachItems[i].$3 : _attachExtra[i], lang), [
            for (var o = 0; o < 5; o++)
              QuizOption(_t(_likert[o], lang), {
                _attachItems[i].$1: _attachItems[i].$2 ? 5 - o : o + 1,
              }),
          ]),
      ],
    QuizKind.animal => [
        for (var i = 0; i < _animalQs.length; i++)
          QuizQuestion('animal_${i}_${v(i)}', _t(v(i) == 0 ? _animalQs[i].$1 : _animalExtra[i].$1, lang), [
            for (var o = 0; o < _animalQs[i].$2.length; o++)
              QuizOption(
                _t(v(i) == 0 ? _animalQs[i].$2[o].$2 : _animalExtra[i].$2[o], lang),
                {_animalQs[i].$2[o].$1: 1},
              ),
          ]),
      ],
  };
}

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
