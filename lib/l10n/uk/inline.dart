// Украинский для строк, которые живут прямо в экранах парой «русский /
// английский» (`ruEn` и `trEnglish` в `../../dict_strings.dart`). Ключ —
// английская строка, где каждое число заменено на `{0}`, `{1}`… по порядку,
// как в `../zh/inline.dart`. Ключи обеих таблиц совпадают: это стережёт
// `test/services/locale_uk_test.dart`.

const Map<String, String> kUkByEnglish = {
  // Поиск фильмов: вид работы
  'Series': 'Серіал',
  'Cartoon': 'Мультфільм',
  'Animated series': 'Мультсеріал',
  'Anime': 'Аніме',
  'Movie': 'Фільм',

  // Работа в фоне (Android)
  'Instant notifications & widgets': 'Миттєві сповіщення й віджети',
  'To get messages, “miss you” and widget updates instantly — even when the app is closed — allow Togetherly to run in the background without battery limits.\n\nOtherwise Android suspends the connection and everything only arrives when you open the app.':
      'Щоб повідомлення, «сумую» й оновлення віджетів приходили одразу, навіть коли застосунок закритий, дозвольте Togetherly працювати у фоні без обмежень батареї.\n\nІнакше Android присипляє з’єднання, і все приходить, лише коли ви відкриєте застосунок.',
  'Allow': 'Дозволити',
  'Later': 'Пізніше',

  // Наборы настроений
  'This pack is not for sale yet': 'Цей набір поки не продається',
  'This pack is not available yet': 'Цей набір поки недоступний',
  'Payment is processing — the pack will open by itself':
      'Платіж обробляється, набір відкриється сам',
  'Purchase failed': 'Покупка не вдалася',
  'You already own this pack': 'Цей набір у вас уже є',
  'Could not open checkout': 'Не вдалося відкрити оплату',
  'Not enough coins: {0} needed, you have {1}':
      'Недостатньо монет: потрібно {0}, у вас {1}',
  'Unlock for {0}': 'Відкрити за {0}',
  'Yours forever, and your partner gets it too':
      'Назавжди ваш, і партнер отримає його теж',

  // Плашка синхронизации
  'Offline': 'Немає мережі',
  'Compressing video…': 'Стискаємо відео…',
  "Didn't sync — retry": 'Не збереглося — повторити',

  // Хочу с тобой
  'Want with you': 'Хочу з тобою',
  'All →': 'Усі →',
  '{0} already came true — see them': 'Уже здійснилося: {0} — подивитися',
  'What to watch, where to go, where to eat — start a list for two.':
      'Що подивитися, куди піти, де поїсти — почніть список на двох.',
  "The shop didn't share a card — fill it in":
      'Магазин не віддав картку товару, заповніть самі',
  "The photo didn't upload — try later":
      'Фото не завантажилося, спробуйте пізніше',
  'From gallery': 'З галереї',
  'Take a photo': 'Сфотографувати',
  'Edit wish': 'Змінити бажання',
  'New wish': 'Нове бажання',
  'Custom': 'Своя',
  'What we want': 'Що хочемо',
  '"Dune: Part Three"': '«Дюна: Частина третя»',
  'Note': 'Примітка',
  'optional': 'необов’язково',
  'Save': 'Зберегти',
  'Add': 'Додати',
  'Cancel': 'Скасувати',
  'Own photo': 'Своє фото',
  'Replace photo': 'Замінити фото',
  'Product link': 'Посилання на товар',
  'Price': 'Ціна',
  'Open link': 'Відкрити посилання',
  'Edit category': 'Змінити категорію',
  'Your own category': 'Своя категорія',
  'Name': 'Назва',
  'Concerts': 'Концерти',
  'Pick from {0} icons': 'Оберіть із {0} значків',
  'Create': 'Створити',
  "You're gifting it — your partner won't know":
      'Ви даруєте, партнер про це не дізнається',
  'Came true': 'Здійснилося',
  'UNDO': 'СКАСУВАТИ',
  'When it happened': 'Коли здійснилося',
  'How it went': 'Як це було',
  'A few words to remember': 'Кілька слів на згадку',
  'Delete': 'Видалити',
  'Dreaming': 'Мріємо',
  'Add your first wish: a film you are waiting for, a place you want to go, or anything of your own. Your partner will see it right away.':
      'Додайте перше бажання: фільм, на який чекаєте, місце, куди хочете поїхати, або щось своє. Партнер побачить його одразу.',
  'Nothing has come true yet. Tick a wish off when it happens.':
      'Поки нічого не здійснилося. Позначте бажання, коли воно збудеться.',
  'Every wish came true. Time to think of a new one.':
      'Усі бажання здійснилися. Час вигадати нове.',
  "I'm gifting": 'Я дарую',
  'Gift it': 'Дарую',
  'Open': 'Відкрити',
  'in Togetherly+': 'у Togetherly+',

  // Кольцо настроений
  'bright': 'світлих',
  'Collapse': 'Згорнути',
  '{0} more': 'Ще {0}',

  // Типы воспоминаний
  'Photo': 'Фото',
  'Video': 'Відео',
  'Video link': 'Відео за посиланням',
  'Text': 'Текст',
  'Music': 'Музика',
  'Book': 'Книга',
  'Place': 'Місце',
  'Audio': 'Аудіо',
  'Untyped': 'Без типу',
  'Moment': 'Момент',
  'Location': 'Місце',
  'Untitled': 'Без назви',

  // Галерея маскотов
  'Pixel': 'Піксельні',
  'Our drawings': 'Наші малюнки',
  'Built-in': 'Вбудовані',
  'Catalog': 'Каталог',
  'Unlock this character forever for {0} coins?':
      'Відкрити цього персонажа назавжди за {0} монет?',
  'Buy': 'Купити',
  'Not for sale yet': 'Поки не продається',
  'Unlocks at level {0}': 'Відкриється на рівні {0}',
  'On screen now': 'Зараз на екрані',
  'Waiting': 'Чекає своєї черги',
  'Nobody with that name. Try another word.':
      'Нікого з таким ім’ям. Спробуйте інше слово.',
  // Цифра в имени художницы тоже становится меткой.
  'Mascots marked «От нас» drawn by Meller{0}':
      'Маскотів із позначкою «Від нас» намалювала Meller{0}',
  'Find a mascot': 'Знайти маскота',
  'paid': 'платний',
  'Lv {0}': 'Рів. {0}',

  // Статистика пары
  'You': 'Ви',
  'Partner': 'Партнер',
  'Couple stats': 'Статистика пари',
  'Refresh': 'Оновити',
  'Nothing to show yet — stats appear once you start together.':
      'Поки нічого показати: статистика з’явиться, коли почнете разом.',
  'Tips for today': 'Поради на сьогодні',
  'Picked from your numbers': 'Дібрано за вашими числами',
  'Days together': 'Днів разом',
  'Day streak': 'Днів поспіль',
  'Couple XP': 'Досвіду пари',
  'To anniversary': 'До річниці',
  'Memories': 'Спогадів',
  'Photos': 'Фото',
  'Videos': 'Відео',
  'Messages': 'Повідомлень',
  'Mood marks': 'Позначок настрою',
  'Miss-yous': '«Сумую»',
  'Brush strokes': 'Штрихів на полотні',
  'Comments': 'Коментарів',
  'Gifts': 'Подарунків',
  'Mascots': 'Маскотів',
  'Watch sessions': 'Спільних переглядів',
  'Canvases': 'Полотен',
  'The year together': 'Рік разом',
  'Share of each series best month': 'Частка від найкращого місяця кожного ряду',
  'Moods': 'Настрої',
  'Side by side': 'Хто скільки',
  'Each partner all-time': 'Внесок кожного за весь час',
  'Weekly rhythm': 'Ритм тижня',
  'Which days you are busiest': 'У які дні ви найактивніші',
  'Hours of the day': 'Години доби',
  'Peak at {0}:{1} · {2}% between {3} and {4}':
      'Пік о {0}:{1} · {2}% між {3} і {4}',
  'Mood': 'Настрій',
  'Mood over {0} days': 'Настрій за {0} дн.',
  'Daily average, {0} to {1}': 'Середнє за день, від {0} до {1}',
  'Favourite moods': 'Улюблені настрої',
  'What you mark most often': 'Що ви позначаєте найчастіше',
  'What memories are made of': 'З чого складаються спогади',
  'Under one': 'Менше одного',
  'Memories per week now': 'Спогадів на тиждень зараз',
  'In {0} days': 'Через {0} дн.',
  'To {0} memories': 'До {0} спогадів',
  'Projected for a year at this pace': 'За рік у такому темпі',
  'of {0}': 'з {0}',
  'Active days last month': 'Активних днів минулого місяця',
  'Mood versus last month': 'Настрій порівняно з минулим місяцем',
  'What is next': 'Що далі',
  'Projection from the last thirty days': 'Прогноз за останні тридцять днів',
  'Nothing yet': 'Поки нічого',

  // Донаты
  'Donation → coins': 'Донат → монети',
  'To get coins automatically, put your email in the donation message:':
      'Щоб монети прийшли самі, вкажіть свій email у повідомленні до донату:',
  'Email copied': 'Email скопійовано',
  'Copy the email above': 'Скопіюйте email кнопкою вище',
  'Paste it into the donation message': 'Вставте його в повідомлення до донату',
  'From {0} ₽ — coins arrive on their own in a couple of minutes':
      'Від {0} ₽, монети прийдуть самі за кілька хвилин',
  'Open DonationAlerts': 'Відкрити DonationAlerts',

  // Профиль
  'dark': 'темна',
  'light': 'світла',
  'How you love': 'Уміння любити',
  'Twenty questions, one shape for two': 'Двадцять запитань, одна фігура на двох',
  'Prefer not to say': 'Не хочу вказувати',
  'Custom gender': 'Своя стать',
  'Enter your gender': 'Укажіть свою стать',

  // Календарь настроений
  'Entries': 'Записів',
  'Days tracked': 'Днів із позначкою',
  'Most often': 'Найчастіше',

  // Уровень и задания
  'Open the app every day': 'Відкривайте застосунок щодня',
  'Add memories': 'Додавайте спогади',
  'Watch videos together': 'Дивіться відео разом',
  'Add the home screen widget': 'Додайте віджет на робочий стіл',
  'Track your mood': 'Позначайте настрій',
  'one-time': 'одноразово',
  '{0}/day': '{0}/день',
  'Level & tasks': 'Рівень і завдання',
  'Tasks — how to level up': 'Завдання: як підняти рівень',
  'Rewards — mascots': 'Нагороди: маскоти',
  'Level {0}': 'Рівень {0}',
  '{0} XP to level {1}': '{0} XP до рівня {1}',
  'Rewards are loading…': 'Нагороди завантажуються…',

  // Живое фото в виджете
  'A live photo needs a video or a GIF': 'Для живого фото потрібне відео або GIF',
  'Live photo is in the widget': 'Живе фото вже у віджеті',
  'Failed — please try again': 'Не вийшло, спробуйте ще раз',
  'Live photo removed': 'Живе фото прибрано',
  'Live photo — a video or a GIF': 'Живе фото: відео або GIF',
  'Remove the live photo': 'Прибрати живе фото',
  'This video is too large — pick a shorter one':
      'Відео завелике, оберіть коротше',
  'This GIF is too large — pick a lighter one': 'GIF завеликий, оберіть легший',

  // Наборы настроений (встроенные и из каталога)
  'Classic': 'Класичні',
  'Pink': 'Рожеві',
  'Bunny': 'Зайка',
  'Mochi': 'Моті',
  'Puppy': 'Песик',

  // Маскоты из каталога: английское имя записи → украинское
  'Pud': 'Пудя',
  'Prick': 'Колючка',
  'Cristal': 'Кристалик',
  'Wick': 'Ґнотик',
  'Brew': 'Чайок',
  'Bulb': 'Лампик',
  'Cloud': 'Хмаринка',
  'Sprout': 'Паросток',
  'Scoop': 'Пломбір',
  'Pearl': 'Перлинка',
  'Volt': 'Вольтик',
  'Moony': 'Місячик',
  'Snaily': 'Равлик',
  'Balloon': 'Кулька',
  'Shroomy': 'Боровичок',
  'Donut': 'Пампушка',
  'Beep': 'Біпка',
  'Boo': 'Пухля',
  'Tape': 'Плівка',
  'Compass': 'Стрілка',
  'Ember': 'Жаринка',
  'Boxy': 'Коробок',
  'Blink': 'Блимко',
  'Bubbly': 'Бульбашка',
  'Cuckoo': 'Ку-ку',
  'Half': 'Половинка',
  'Seasons': 'Сезонник',
  'Postie': 'Листоноша',
  'Fae': 'Фея',
  'Lantern': 'Ліхтарик',
  'Jelly': 'Желейка',
  'Spiky': 'Спайкі',
  'Lulu': 'Лулу',
  'Iskrik': 'Іскрик',
  'Zhuzha': 'Жужа',

  // Категории желаний
  'Food': 'Їжа',
  'Trip': 'Подорож',
  'Other': 'Своє',

  // Раскраски
  'Cafe': 'Кафе',
  'Castle': 'Замок',
  'Rain': 'Дощ',
  'Ferris wheel': 'Оглядове колесо',
  'Metro': 'Метро',
  'Camping': 'Намет',
  'Festival': 'Фестиваль',
  'Baking': 'Готуємо разом',
  'Beach': 'Пляж',
  'Gaming': 'Приставка',

  // Записки к подаркам
  'date lost': 'дата загубилася',
  'from you': 'від вас',
  'from your partner': 'від партнера',
  'from the chest': 'зі скрині',
  'This gift is not on the shelf yet.': 'Цього подарунка ще немає на полиці.',
  'Your reply': 'Ваша відповідь',
  'Reply': 'Відповісти',
  'No note': 'Без записки',

  // Витрина подарков
  'Everyday': 'Щодня',
  'Occasions': 'З приводу',
  'Milestones': 'Подія',
};
