part of 'daily_task.dart';

/// Новогодний декабрь: на каждый день с 1 по 31 декабря свои задания, одни и
/// те же у всех пар, отсчётом к Новому году. В каждом дне три основных и бонус
/// четырёх разных типов, как в обычном наборе.
///
/// В общий каталог [DailyTask.all] эти задания не входят: любой новый элемент
/// каталога меняет порядок у всех пар. Обычная очередь в декабре идёт своим
/// ходом, просто её не показывают, поэтому с 1 января пара получает тот же
/// набор, что и на прежней сборке.
///
/// Тексты не опираются на снег и холод: в Бразилии декабрь летний. Глаголы без
/// прошедшего времени и рода. Переводы — в `lib/l10n/<язык>/daily_tasks.dart`.
class NewYearTasks {
  NewYearTasks._();

  /// Задания дня на дату (UTC, как и весь расчёт заданий), если это декабрь.
  static DailyTaskDay? dayFor(DateTime date) {
    if (date.month != 12) return null;
    final day = days[date.day - 1];
    return DailyTaskDay(day.sublist(0, kDailyTaskCount), day[kDailyTaskCount]);
  }

  /// Все задания декабря подряд: по ним ищется текст для подписи в ленте.
  static Iterable<DailyTask> get all => days.expand((day) => day);

  /// Дни декабря по порядку: три основных задания и бонус последним.
  static const List<List<DailyTask>> days = <List<DailyTask>>[
    // 1 декабря
    <DailyTask>[
      DailyTask('ny01_text', MemoryType.text,
          'Что хотите успеть вдвоём до Нового года',
          'What you two want to do before the New Year'),
      DailyTask('ny01_photo', MemoryType.photo,
          'Вид из окна в первый день декабря',
          'The view from your window on the first day of December'),
      DailyTask('ny01_music', MemoryType.music,
          'Песня, с которой у тебя начинается декабрь',
          'The song that starts your December'),
      DailyTask('ny01_movie', MemoryType.movie,
          'Новогодний фильм, с которого начнёте сезон',
          'The holiday movie to open the season'),
    ],
    // 2 декабря
    <DailyTask>[
      DailyTask('ny02_photo', MemoryType.photo,
          'Самая уютная вещь в комнате', 'The coziest thing in your room'),
      DailyTask('ny02_vid', MemoryType.videoLink,
          'Видео с самой красивой ёлкой',
          'A video of the most beautiful Christmas tree'),
      DailyTask('ny02_book', MemoryType.book,
          'Книга под плед на декабрь', 'A book to read under a blanket in December'),
      DailyTask('ny02_text', MemoryType.text,
          'Подарок, о котором мечталось в детстве',
          'A gift you dreamed of as a kid'),
    ],
    // 3 декабря
    <DailyTask>[
      DailyTask('ny03_loc', MemoryType.location,
          'Где хочется встретить Новый год',
          'Where you’d love to ring in the New Year'),
      DailyTask('ny03_music', MemoryType.music,
          'Новогодняя песня из детства', 'A holiday song from your childhood'),
      DailyTask('ny03_photo', MemoryType.photo,
          'Кружка, из которой сегодня чай или какао',
          'Your mug of tea or cocoa today'),
      DailyTask('ny03_clip', MemoryType.video,
          'Что за окном прямо сейчас', 'What’s outside your window right now'),
    ],
    // 4 декабря
    <DailyTask>[
      DailyTask('ny04_text', MemoryType.text,
          'Три лучших дня вашего года', 'The three best days of your year together'),
      DailyTask('ny04_movie', MemoryType.movie,
          'Фильм, который пересматриваешь каждую зиму',
          'A movie you rewatch every winter'),
      DailyTask('ny04_vid', MemoryType.videoLink,
          'Рецепт праздничного печенья, которое испечёте',
          'A holiday cookie recipe to bake together'),
      DailyTask('ny04_photo', MemoryType.photo,
          'Самые тёплые носки', 'Your warmest socks'),
    ],
    // 5 декабря
    <DailyTask>[
      DailyTask('ny05_photo', MemoryType.photo,
          'Первая гирлянда, которая попадётся сегодня',
          'The first string of lights you see today'),
      DailyTask('ny05_music', MemoryType.music,
          'Песня, под которую хочется наряжать ёлку',
          'A song for decorating the tree'),
      DailyTask('ny05_loc', MemoryType.location,
          'Каток, горка или парк, куда сходить вдвоём',
          'A rink, a hill or a park to visit together'),
      DailyTask('ny05_book', MemoryType.book,
          'Книга, которую хочется подарить {p}', 'A book you’d like to give {p}'),
    ],
    // 6 декабря
    <DailyTask>[
      DailyTask('ny06_clip', MemoryType.video,
          'Покажи, где будет стоять ёлка', 'Show where the tree will stand'),
      DailyTask('ny06_text', MemoryType.text,
          'Как Новый год встречали в твоей семье',
          'How your family celebrated New Year’s'),
      DailyTask('ny06_movie', MemoryType.movie,
          'Мультфильм, который пахнет праздником',
          'A cartoon that feels like the holidays'),
      DailyTask('ny06_vid', MemoryType.videoLink,
          'Самая трогательная праздничная реклама',
          'The most touching holiday ad'),
    ],
    // 7 декабря
    <DailyTask>[
      DailyTask('ny07_photo', MemoryType.photo,
          'Праздничная витрина по дороге', 'A festive shop window on your way'),
      DailyTask('ny07_vid', MemoryType.videoLink,
          'Зимний город, куда хочется поехать вдвоём',
          'A winter city you’d love to visit together'),
      DailyTask('ny07_music', MemoryType.music,
          'Песня для зимней дороги', 'A song for a winter road trip'),
      DailyTask('ny07_loc', MemoryType.location,
          'Кафе с лучшим горячим шоколадом рядом',
          'The café with the best hot chocolate nearby'),
    ],
    // 8 декабря
    <DailyTask>[
      DailyTask('ny08_text', MemoryType.text,
          'Чему тебя научил этот год', 'What this year taught you'),
      DailyTask('ny08_photo', MemoryType.photo,
          'Сладость, которая для тебя значит праздник',
          'A treat that means the holidays to you'),
      DailyTask('ny08_book', MemoryType.book,
          'Сказка, которую стоит перечитать к Новому году',
          'A fairy tale worth rereading before New Year’s'),
      DailyTask('ny08_movie', MemoryType.movie,
          'Фильм с самым красивым снегом', 'A movie with the most beautiful snow'),
    ],
    // 9 декабря
    <DailyTask>[
      DailyTask('ny09_music', MemoryType.music,
          'Песня, которая звучала у вас этим летом',
          'A song you two played this summer'),
      DailyTask('ny09_loc', MemoryType.location,
          'Где вам было лучше всего в этом году',
          'Where you two were happiest this year'),
      DailyTask('ny09_photo', MemoryType.photo,
          'Самая праздничная вещь в твоём шкафу',
          'The most festive thing in your closet'),
      DailyTask('ny09_vid', MemoryType.videoLink,
          'Видео, после которого хочется праздника',
          'A video that puts you in a holiday mood'),
    ],
    // 10 декабря
    <DailyTask>[
      DailyTask('ny10_photo', MemoryType.photo,
          'Ёлочная игрушка с историей', 'A tree ornament with a story'),
      DailyTask('ny10_text', MemoryType.text,
          'Чего ждёшь от декабря больше всего',
          'What you’re looking forward to most in December'),
      DailyTask('ny10_movie', MemoryType.movie,
          'Рождественская комедия на вечер', 'A Christmas comedy for tonight'),
      DailyTask('ny10_music', MemoryType.music,
          'Песня, под которую танцуешь на празднике',
          'A song you dance to at parties'),
    ],
    // 11 декабря
    <DailyTask>[
      DailyTask('ny11_clip', MemoryType.video,
          'Твой декабрьский вечер за 10 секунд',
          'Your December evening in 10 seconds'),
      DailyTask('ny11_vid', MemoryType.videoLink,
          'Как красиво упаковать подарок', 'How to wrap a gift beautifully'),
      DailyTask('ny11_book', MemoryType.book,
          'Книга, где герои встречают праздник',
          'A book where the characters celebrate the holidays'),
      DailyTask('ny11_photo', MemoryType.photo,
          'Окно, в котором горит тёплый свет', 'A window glowing with warm light'),
    ],
    // 12 декабря
    <DailyTask>[
      DailyTask('ny12_loc', MemoryType.location,
          'Ярмарка или рынок, куда хочется вдвоём',
          'A holiday market you’d like to visit together'),
      DailyTask('ny12_music', MemoryType.music,
          'Песня, которую вы поёте вместе', 'A song you sing together'),
      DailyTask('ny12_text', MemoryType.text,
          'Обещание {p} на следующий год', 'A promise to {p} for next year'),
      DailyTask('ny12_photo', MemoryType.photo,
          'Самый праздничный завтрак, какой получится',
          'The most festive breakfast you can make'),
    ],
    // 13 декабря
    <DailyTask>[
      DailyTask('ny13_photo', MemoryType.photo,
          'Что-то блестящее', 'Something sparkly'),
      DailyTask('ny13_movie', MemoryType.movie,
          'Фильм, который вы смотрели вместе в этом году',
          'A movie you watched together this year'),
      DailyTask('ny13_vid', MemoryType.videoLink,
          'Салют, который хочется увидеть вживую',
          'Fireworks you’d love to see in person'),
      DailyTask('ny13_text', MemoryType.text,
          'Самый смешной момент вашего года', 'The funniest moment of your year'),
    ],
    // 14 декабря
    <DailyTask>[
      DailyTask('ny14_clip', MemoryType.video,
          'Какая погода у тебя прямо сейчас',
          'What the weather is like where you are'),
      DailyTask('ny14_text', MemoryType.text,
          'Идеальный праздничный день вдвоём', 'Your perfect holiday together'),
      DailyTask('ny14_music', MemoryType.music,
          'Песня, которая звучит как гирлянда',
          'A song that sounds like twinkling lights'),
      DailyTask('ny14_book', MemoryType.book,
          'Лучшая книга твоего года', 'The best book of your year'),
    ],
    // 15 декабря
    <DailyTask>[
      DailyTask('ny15_photo', MemoryType.photo,
          'Ёлка или первая игрушка на ней', 'Your tree, or the first ornament on it'),
      DailyTask('ny15_loc', MemoryType.location,
          'Куда пойти гулять в праздники', 'Where to go for a walk over the holidays'),
      DailyTask('ny15_vid', MemoryType.videoLink,
          'Новогодняя традиция другой страны',
          'A New Year tradition from another country'),
      DailyTask('ny15_movie', MemoryType.movie,
          'Фильм, который {p} стоит увидеть до конца года',
          'A movie {p} should see before the year ends'),
    ],
    // 16 декабря
    <DailyTask>[
      DailyTask('ny16_text', MemoryType.text,
          'Подсказка {p}, что подарить тебе',
          'A hint for {p} about what to get you'),
      DailyTask('ny16_photo', MemoryType.photo,
          'Коробка или бумага для подарка', 'A gift box or wrapping paper'),
      DailyTask('ny16_music', MemoryType.music,
          'Песня из любимого новогоднего фильма',
          'A song from your favorite holiday movie'),
      DailyTask('ny16_vid', MemoryType.videoLink,
          'Видео с камином на весь вечер', 'A fireplace video for the whole evening'),
    ],
    // 17 декабря
    <DailyTask>[
      DailyTask('ny17_photo', MemoryType.photo,
          'Фрукт, который пахнет праздником',
          'A fruit that smells like the holidays'),
      DailyTask('ny17_movie', MemoryType.movie,
          'Фильм с праздников твоего детства',
          'A movie from your childhood holidays'),
      DailyTask('ny17_loc', MemoryType.location,
          'Место, которое хочется показать {p} в праздники',
          'A place you want to show {p} over the holidays'),
      DailyTask('ny17_clip', MemoryType.video,
          'Чем занят твой вечер', 'What your evening looks like'),
    ],
    // 18 декабря
    <DailyTask>[
      DailyTask('ny18_vid', MemoryType.videoLink,
          'Праздничный образ, который хочется повторить',
          'A holiday look you want to recreate'),
      DailyTask('ny18_text', MemoryType.text,
          'Новогоднее желание, которое можно сказать вслух',
          'A New Year wish you can say out loud'),
      DailyTask('ny18_book', MemoryType.book,
          'Книга на праздничные дни', 'A book for the holidays'),
      DailyTask('ny18_music', MemoryType.music,
          'Песня, которую хочется посвятить {p} в этом декабре',
          'A song you’d dedicate to {p} this December'),
    ],
    // 19 декабря
    <DailyTask>[
      DailyTask('ny19_photo', MemoryType.photo,
          'Самый праздничный уголок дома', 'The most festive corner of your home'),
      DailyTask('ny19_music', MemoryType.music,
          'Самая неожиданная новогодняя песня', 'The most unexpected holiday song'),
      DailyTask('ny19_movie', MemoryType.movie,
          'Фильм, где всё случается за одну ночь',
          'A movie where everything happens in one night'),
      DailyTask('ny19_loc', MemoryType.location,
          'Место с самой красивой иллюминацией',
          'The place with the most beautiful lights'),
    ],
    // 20 декабря
    <DailyTask>[
      DailyTask('ny20_clip', MemoryType.video,
          'Покажи, как украшена твоя улица', 'Show how your street is decorated'),
      DailyTask('ny20_text', MemoryType.text,
          'Подарок, который запомнился больше всех', 'The gift you remember most'),
      DailyTask('ny20_vid', MemoryType.videoLink,
          'Блюдо, которое приготовите к столу',
          'A dish you’ll make for the holiday table'),
      DailyTask('ny20_photo', MemoryType.photo,
          'Ваше лучшее общее фото этого года', 'Your best photo together this year'),
    ],
    // 21 декабря
    <DailyTask>[
      DailyTask('ny21_text', MemoryType.text,
          'Чем заняться в долгий декабрьский вечер',
          'What to do on a long December evening'),
      DailyTask('ny21_music', MemoryType.music,
          'Песня для позднего вечера', 'A song for late at night'),
      DailyTask('ny21_photo', MemoryType.photo,
          'Свеча, лампа или гирлянда в темноте',
          'A candle, a lamp or lights in the dark'),
      DailyTask('ny21_movie', MemoryType.movie,
          'Длинный фильм на свободный вечер', 'A long movie for a free evening'),
    ],
    // 22 декабря
    <DailyTask>[
      DailyTask('ny22_loc', MemoryType.location,
          'Где выбирать подарки', 'Where to shop for gifts'),
      DailyTask('ny22_photo', MemoryType.photo,
          'Список дел на праздники', 'Your holiday to-do list'),
      DailyTask('ny22_book', MemoryType.book,
          'Книга, которую хочется читать вслух вдвоём',
          'A book to read aloud together'),
      DailyTask('ny22_clip', MemoryType.video,
          'Покажи, что уже готово к празднику',
          'Show what’s already ready for the holidays'),
    ],
    // 23 декабря
    <DailyTask>[
      DailyTask('ny23_vid', MemoryType.videoLink,
          'Новогодний клип, без которого нет праздника',
          'A music video that is the holidays for you'),
      DailyTask('ny23_text', MemoryType.text,
          'Что хочешь оставить в уходящем году',
          'What you want to leave behind this year'),
      DailyTask('ny23_movie', MemoryType.movie,
          'Фильм о чуде', 'A movie about a miracle'),
      DailyTask('ny23_photo', MemoryType.photo,
          'Подарок для {p} в упаковке, без спойлеров',
          'The gift for {p}, wrapped, no spoilers'),
    ],
    // 24 декабря, сочельник
    <DailyTask>[
      DailyTask('ny24_photo', MemoryType.photo,
          'Праздничный стол или его начало', 'The holiday table, or the start of it'),
      DailyTask('ny24_music', MemoryType.music,
          'Рождественская песня', 'A Christmas song'),
      DailyTask('ny24_clip', MemoryType.video,
          'Пожелание {p} в сочельник', 'A Christmas Eve wish for {p}'),
      DailyTask('ny24_book', MemoryType.book,
          'Рождественская история', 'A Christmas story'),
    ],
    // 25 декабря, Рождество
    <DailyTask>[
      DailyTask('ny25_text', MemoryType.text,
          'Пожелание на Рождество', 'A Christmas wish'),
      DailyTask('ny25_loc', MemoryType.location,
          'Где ты сегодня', 'Where you are today'),
      DailyTask('ny25_vid', MemoryType.videoLink,
          'Рождественское видео, от которого тепло',
          'A Christmas video that warms your heart'),
      DailyTask('ny25_photo', MemoryType.photo,
          'Самое рождественское, что видно сегодня',
          'The most Christmassy thing you see today'),
    ],
    // 26 декабря
    <DailyTask>[
      DailyTask('ny26_photo', MemoryType.photo,
          'Праздничный беспорядок', 'Holiday mess'),
      DailyTask('ny26_movie', MemoryType.movie,
          'Фильм на ленивый день', 'A movie for a lazy day'),
      DailyTask('ny26_music', MemoryType.music,
          'Песня для ленивого утра', 'A song for a lazy morning'),
      DailyTask('ny26_text', MemoryType.text,
          'Самый тёплый момент недели', 'The warmest moment of the week'),
    ],
    // 27 декабря
    <DailyTask>[
      DailyTask('ny27_clip', MemoryType.video,
          'Итог года за 15 секунд', 'Your year in 15 seconds'),
      DailyTask('ny27_loc', MemoryType.location,
          'Куда вы точно поедете в следующем году',
          'Where you’ll definitely go next year'),
      DailyTask('ny27_book', MemoryType.book,
          'Книга, которую хочешь прочитать в новом году',
          'A book you want to read next year'),
      DailyTask('ny27_vid', MemoryType.videoLink,
          'Самое смешное видео уходящего года', 'The funniest video of the year'),
    ],
    // 28 декабря
    <DailyTask>[
      DailyTask('ny28_text', MemoryType.text,
          'Вопрос {p} про следующий год', 'A question for {p} about next year'),
      DailyTask('ny28_photo', MemoryType.photo,
          'Наряд для новогодней ночи', 'Your outfit for New Year’s Eve'),
      DailyTask('ny28_music', MemoryType.music,
          'Главная песня твоего года', 'The song of your year'),
      DailyTask('ny28_movie', MemoryType.movie,
          'Главный фильм вашего года', 'The movie of your year together'),
    ],
    // 29 декабря
    <DailyTask>[
      DailyTask('ny29_photo', MemoryType.photo,
          'Ёлка в огнях вечером', 'The tree lit up in the evening'),
      DailyTask('ny29_vid', MemoryType.videoLink,
          'Горячий напиток или коктейль на праздник',
          'A hot drink or a cocktail for the party'),
      DailyTask('ny29_loc', MemoryType.location,
          'Где будете смотреть салют', 'Where you’ll watch the fireworks'),
      DailyTask('ny29_book', MemoryType.book,
          'Книга, которая лучше всего описывает ваш год',
          'A book that best describes your year'),
    ],
    // 30 декабря
    <DailyTask>[
      DailyTask('ny30_music', MemoryType.music,
          'Песня в плейлист новогодней ночи',
          'A song for the New Year’s Eve playlist'),
      DailyTask('ny30_text', MemoryType.text,
          'Чем гордишься в этом году', 'What you’re proud of this year'),
      DailyTask('ny30_clip', MemoryType.video,
          'Покажи сборы к празднику', 'Show your holiday prep'),
      DailyTask('ny30_photo', MemoryType.photo,
          'Предпоследний вечер года', 'The second-to-last evening of the year'),
    ],
    // 31 декабря
    <DailyTask>[
      DailyTask('ny31_clip', MemoryType.video,
          'Поздравление {p} с Новым годом', 'A Happy New Year message for {p}'),
      DailyTask('ny31_photo', MemoryType.photo,
          'Последнее фото этого года', 'Your last photo of the year'),
      DailyTask('ny31_text', MemoryType.text,
          'Желание {p} на новый год', 'A wish for {p} for the new year'),
      DailyTask('ny31_music', MemoryType.music,
          'Песня, под которую встречаешь полночь',
          'The song you’ll greet midnight with'),
    ],
  ];
}
