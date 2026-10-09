import '../l10n/zh/daily_tasks.dart';
import '../services/locale_service.dart';
import 'memory.dart';

/// Ежедневное «задание для пары» — лёгкий тёплый импульс поделиться моментом,
/// привязанный к типу воспоминания ([MemoryType]). Выполнение = создание пина
/// этого типа в Ленте воспоминаний. Награда — 1 монета (начисляется серверным
/// роутом, см. pb_hooks/coins.pb.js), поэтому задания намеренно простые: одно
/// действие «за минуту», всегда «поделись», а не «сделай задание».
///
/// Каталог статичен и типобезопасен (по образцу [ProfileIcon.all]); набор на
/// день выбирается детерминированно по (дата + pairId), поэтому у обоих
/// партнёров задания совпадают без обращения к серверу (см. [dailyTaskDayFor]).
class DailyTask {
  /// Стабильный id — по нему хранится прогресс и идёт детерминированный выбор.
  final String id;

  /// Какой пин закрывает задание.
  final MemoryType type;

  final String _ru;
  final String _en;

  const DailyTask(this.id, this.type, this._ru, this._en);

  /// Текст задания на текущем языке. Токен `{p}` заменяется именем партнёра
  /// (или локализованным «партнёр», если имя пусто).
  String title(String partnerName) {
    final p = partnerName.trim().isNotEmpty
        ? partnerName.trim()
        : LocaleService.current.partnerFallback;
    final lang = LocaleService.instance.language;
    final raw = switch (lang) {
      AppLanguage.ru => _ru,
      AppLanguage.zh => kDailyTasksZh[id] ?? _en,
      _ => _en,
    };
    return raw.replaceAll('{p}', p);
  }

  /// Значок типа пина из Material Symbols — тем же набором, что и остальной
  /// интерфейс. Эмодзи рядом оставлены для уведомлений: в системной шторке
  /// шрифта символов нет.
  String get symbol {
    switch (type) {
      case MemoryType.photo:
        return 'photo_camera';
      case MemoryType.video:
        return 'videocam';
      case MemoryType.location:
        return 'location_on';
      case MemoryType.music:
        return 'music_note';
      case MemoryType.text:
        return 'edit_note';
      case MemoryType.videoLink:
        return 'smart_display';
      case MemoryType.book:
        return 'menu_book';
      case MemoryType.movie:
        return 'theaters';
    }
  }

  /// Эмодзи типа пина (переиспользуем [Memory.typeEmoji] через фиктивный доступ
  /// к таблице эмодзи — сам маппинг живёт в модели памяти).
  String get emoji {
    switch (type) {
      case MemoryType.photo:
        return '📷';
      case MemoryType.video:
        return '🎬';
      case MemoryType.location:
        return '📍';
      case MemoryType.music:
        return '🎵';
      case MemoryType.text:
        return '📝';
      case MemoryType.videoLink:
        return '🎬';
      case MemoryType.book:
        return '📚';
      case MemoryType.movie:
        return '🎬';
    }
  }

  static DailyTask? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Полный каталог. Упор на самые лёгкие типы (фото/заметка) — чтобы задание
  /// хотелось выполнить, а не откладывать.
  static const List<DailyTask> all = <DailyTask>[
    // ── 📷 Фото — сняла и готово ──────────────────────────────────────────
    DailyTask('photo_now', MemoryType.photo,
        'Сфоткай, что видишь прямо сейчас', 'Snap what you see right now'),
    DailyTask('photo_smile', MemoryType.photo,
        'Селфи с улыбкой для {p}', 'A smiling selfie for {p}'),
    DailyTask('photo_drink', MemoryType.photo,
        'Покажи, что пьёшь', "Show what you're drinking"),
    DailyTask('photo_food', MemoryType.photo,
        'Сфоткай свою еду', 'Snap your food'),
    DailyTask('photo_window', MemoryType.photo,
        'Твой вид из окна сегодня', 'Your view from the window today'),
    DailyTask('photo_sky', MemoryType.photo,
        'Сфоткай небо над тобой', 'Snap the sky above you'),
    DailyTask('photo_outfit', MemoryType.photo,
        'Покажи свой сегодняшний образ', "Show today's outfit"),
    DailyTask('photo_shoes', MemoryType.photo,
        'Сфоткай свою обувь сегодня', 'Snap your shoes today'),
    DailyTask('photo_here', MemoryType.photo,
        'Покажи, где ты сейчас', 'Show where you are right now'),
    DailyTask('photo_pet', MemoryType.photo,
        'Сфоткай питомца (или чужого котика)', 'Snap a pet (or a stray cat)'),
    DailyTask('photo_hand', MemoryType.photo,
        'Сфоткай свою руку — {p} захочет её сжать',
        "Snap your hand — {p} will want to hold it"),
    DailyTask('photo_left', MemoryType.photo,
        'Сфоткай, что слева от тебя', "Snap what's to your left"),
    DailyTask('photo_morning', MemoryType.photo,
        'Первое, что увидел утром', 'The first thing you saw this morning'),
    DailyTask('photo_beautiful', MemoryType.photo,
        'Сфоткай что-то красивое рядом', 'Snap something beautiful nearby'),
    DailyTask('photo_snack', MemoryType.photo,
        'Покажи свой перекус', 'Show your snack'),
    DailyTask('photo_mirror', MemoryType.photo,
        'Зеркальное селфи', 'A mirror selfie'),
    DailyTask('photo_cozy', MemoryType.photo,
        'Сфоткай самое уютное место рядом', 'Snap the cosiest spot near you'),
    DailyTask('photo_reminds', MemoryType.photo,
        'Сфоткай то, что напомнило о {p}',
        'Snap something that reminded you of {p}'),
    DailyTask('photo_best', MemoryType.photo,
        'Лучший момент дня — в кадр', 'Capture the best moment of your day'),
    DailyTask('photo_hobby', MemoryType.photo,
        'Покажи, чем занят прямо сейчас', "Show what you're up to right now"),
    DailyTask('photo_wink', MemoryType.photo,
        'Подмигни в камеру для {p}', 'Wink at the camera for {p}'),
    DailyTask('photo_color', MemoryType.photo,
        'Найди что-то любимого цвета {p} и сфоткай',
        "Find something in {p}'s favourite colour and snap it"),

    // ── 📝 Заметка — пара тёплых слов ─────────────────────────────────────
    DailyTask('text_grateful', MemoryType.text,
        'За что ты сегодня благодарен {p}?',
        'What are you grateful to {p} for today?'),
    DailyTask('text_three', MemoryType.text,
        'Опиши {p} тремя словами', 'Describe {p} in three words'),
    DailyTask('text_compliment', MemoryType.text,
        'Отправь {p} комплимент', 'Send {p} a compliment'),
    DailyTask('text_miss', MemoryType.text,
        'Напиши, чего тебе не хватает рядом с {p}',
        'Write what you miss about {p} right now'),
    DailyTask('text_love', MemoryType.text,
        'За что ты любишь {p}? Одно предложение',
        'Why do you love {p}? One sentence'),
    DailyTask('text_memory', MemoryType.text,
        'Вспомни любимый момент с {p}',
        'Recall your favourite moment with {p}'),
    DailyTask('text_smile', MemoryType.text,
        'Что заставило тебя улыбнуться сегодня?',
        'What made you smile today?'),
    DailyTask('text_dream', MemoryType.text,
        'О чём ты мечтаешь для вас двоих?',
        'What do you dream of for the two of you?'),
    DailyTask('text_firstthing', MemoryType.text,
        'Что первым делом скажешь {p} при встрече?',
        "First thing you'll say to {p} when you meet?"),
    DailyTask('text_nickname', MemoryType.text,
        'Придумай {p} новое милое прозвище',
        'Make up a cute new nickname for {p}'),
    DailyTask('text_ifhere', MemoryType.text,
        'Что бы вы делали, будь {p} сейчас рядом?',
        'What would you do if {p} were here now?'),
    DailyTask('text_proud', MemoryType.text,
        'Чем ты гордишься в {p}?', 'What are you proud of {p} for?'),
    DailyTask('text_good', MemoryType.text,
        'Расскажи о хорошем, что случилось сегодня',
        'Share something good that happened today'),
    DailyTask('text_wish', MemoryType.text,
        'Пожелай {p} хорошего вечера своими словами',
        'Wish {p} a good evening in your own words'),
    DailyTask('text_thanks', MemoryType.text,
        'Скажи {p} спасибо за что-то мелкое',
        'Thank {p} for something small'),
    DailyTask('text_hug', MemoryType.text,
        'Опиши, как обнимешь {p} при встрече',
        "Describe how you'll hug {p} when you meet"),

    // ── 📍 Локация — одно нажатие ─────────────────────────────────────────
    DailyTask('loc_here', MemoryType.location,
        'Отметь, где ты сейчас', 'Check in where you are now'),
    DailyTask('loc_favorite', MemoryType.location,
        'Отметь место, где вам было хорошо вдвоём',
        'Mark a place you loved together'),
    DailyTask('loc_coffee', MemoryType.location,
        'Отметь, где пьёшь кофе', "Mark where you're having coffee"),
    DailyTask('loc_dream', MemoryType.location,
        'Отметь место, куда хочешь поехать с {p}',
        'Mark a place you want to go with {p}'),
    DailyTask('loc_walk', MemoryType.location,
        'Гуляешь? Отметь, где ты', 'Out for a walk? Mark the spot'),
    DailyTask('loc_home', MemoryType.location,
        'Отметь свой любимый уголок дома',
        'Mark your favourite corner at home'),
    DailyTask('loc_food', MemoryType.location,
        'Отметь, где вкусно поел', 'Mark where you ate something tasty'),
    DailyTask('loc_first', MemoryType.location,
        'Отметь место вашего первого свидания',
        'Mark the place of your first date'),
    DailyTask('loc_view', MemoryType.location,
        'Отметь точку с лучшим видом рядом', 'Mark the best view nearby'),

    // ── 🎵 Музыка — поделись треком ───────────────────────────────────────
    DailyTask('mus_now', MemoryType.music,
        'Что играет у тебя прямо сейчас?', "What's playing for you right now?"),
    DailyTask('mus_reminds', MemoryType.music,
        'Песня, под которую вспоминаешь {p}',
        'A song that reminds you of {p}'),
    DailyTask('mus_dedicate', MemoryType.music,
        'Посвяти {p} песню', 'Dedicate a song to {p}'),
    DailyTask('mus_dance', MemoryType.music,
        'Под что бы вы потанцевали вдвоём?', 'What would you two dance to?'),
    DailyTask('mus_mood', MemoryType.music,
        'Песня под твоё настроение сейчас', 'A song for your mood right now'),
    DailyTask('mus_oursong', MemoryType.music,
        'Ваша песня — поделись', 'Your song — share it'),
    DailyTask('mus_discover', MemoryType.music,
        'Трек, который недавно зацепил', 'A track that recently caught you'),
    DailyTask('mus_morning', MemoryType.music,
        'Что бы поставил вам на утро?', 'What would you play for your morning?'),
    DailyTask('mus_road', MemoryType.music,
        'Песня для дороги к {p}', 'A song for the road to {p}'),

    // ── 🎬 Фильм ──────────────────────────────────────────────────────────
    DailyTask('mov_watch', MemoryType.movie,
        'Что хотите посмотреть вместе?', 'What do you want to watch together?'),
    DailyTask('mov_fav', MemoryType.movie,
        'Твой любимый фильм — покажи {p}', 'Your favourite film — show {p}'),
    DailyTask('mov_comedy', MemoryType.movie,
        'Комедия на вечер вдвоём', 'A comedy for an evening together'),
    DailyTask('mov_series', MemoryType.movie,
        'Сериал, который стоит начать вместе',
        'A series worth starting together'),
    DailyTask('mov_childhood', MemoryType.movie,
        'Фильм из детства, который любишь', 'A childhood film you love'),
    DailyTask('mov_cry', MemoryType.movie,
        'Фильм, над которым не стыдно поплакать', 'A film worth crying over'),

    // ── 📚 Книга ──────────────────────────────────────────────────────────
    DailyTask('book_recommend', MemoryType.book,
        'Книга, которую советуешь {p}', "A book you'd recommend to {p}"),
    DailyTask('book_reading', MemoryType.book,
        'Что читаешь сейчас?', 'What are you reading now?'),
    DailyTask('book_changed', MemoryType.book,
        'Книга, которая тебя изменила', 'A book that changed you'),
    DailyTask('book_together', MemoryType.book,
        'Книга, которую хочешь прочитать вместе',
        'A book to read together'),
    DailyTask('book_quote', MemoryType.book,
        'Любимая цитата из книги', 'A favourite book quote'),

    // ── 🎬 Видео-ссылка ───────────────────────────────────────────────────
    DailyTask('vid_laugh', MemoryType.videoLink,
        'Видео, которое тебя рассмешило', 'A video that made you laugh'),
    DailyTask('vid_show', MemoryType.videoLink,
        'Ролик, который хочешь показать {p}', 'A clip you want to show {p}'),
    DailyTask('vid_wow', MemoryType.videoLink,
        'Видео, которое удивило', 'A video that amazed you'),
    DailyTask('vid_cute', MemoryType.videoLink,
        'Милейшее видео дня', 'The cutest video of the day'),

    // ═════════ ЧАСТЬ 2 — добор до 200 ═════════

    // ── 📷 Фото ───────────────────────────────────────────────────────────
    DailyTask('photo_right', MemoryType.photo,
        'Сфоткай, что справа от тебя', "Snap what's to your right"),
    DailyTask('photo_feet', MemoryType.photo,
        'Сфоткай вид «сверху вниз» — на свои ноги',
        'Snap the view down at your feet'),
    DailyTask('photo_madeday', MemoryType.photo,
        'Сфоткай то, что сегодня тебя порадовало',
        'Snap something that made your day'),
    DailyTask('photo_coffee', MemoryType.photo,
        'Сфоткай свою кружку', 'Snap your mug'),
    DailyTask('photo_sweet', MemoryType.photo,
        'Покажи что-нибудь сладкое рядом', 'Show something sweet nearby'),
    DailyTask('photo_desk', MemoryType.photo,
        'Покажи свой рабочий беспорядок', 'Show your desk mess'),
    DailyTask('photo_infront', MemoryType.photo,
        'Что перед тобой прямо сейчас?', "What's in front of you right now?"),
    DailyTask('photo_hands_busy', MemoryType.photo,
        'Сфоткай, чем заняты твои руки',
        'Snap what your hands are busy with'),
    DailyTask('photo_light', MemoryType.photo,
        'Сфоткай красивый свет рядом', 'Snap some pretty light nearby'),
    DailyTask('photo_plant', MemoryType.photo,
        'Сфоткай растение поблизости', 'Snap a plant nearby'),
    DailyTask('photo_street', MemoryType.photo,
        'Сфоткай свою улицу', 'Snap your street'),
    DailyTask('photo_sunset', MemoryType.photo,
        'Закат или рассвет — успей поймать', 'Catch the sunset or sunrise'),
    DailyTask('photo_watching', MemoryType.photo,
        'Сфоткай, что читаешь или смотришь',
        "Snap what you're reading or watching"),
    DailyTask('photo_smalljoy', MemoryType.photo,
        'Маленькая радость дня — в кадр', 'A small joy of the day — snap it'),
    DailyTask('photo_reflection', MemoryType.photo,
        'Найди отражение и сфоткай', 'Find a reflection and snap it'),
    DailyTask('photo_texture', MemoryType.photo,
        'Сфоткай приятную текстуру рядом', 'Snap a nice texture nearby'),
    DailyTask('photo_favthing', MemoryType.photo,
        'Сфоткай любимую вещь под рукой', 'Snap a favourite thing at hand'),
    DailyTask('photo_gift', MemoryType.photo,
        'Что бы ты подарил {p}? Сфоткай', 'What would you gift {p}? Snap it'),
    DailyTask('photo_weather', MemoryType.photo,
        'Покажи погоду за окном', 'Show the weather outside'),
    DailyTask('photo_cook', MemoryType.photo,
        'Готовишь? Покажи процесс', 'Cooking? Show the process'),
    DailyTask('photo_hair', MemoryType.photo,
        'Покажи свою причёску сегодня', 'Show your hairstyle today'),
    DailyTask('photo_afterwalk', MemoryType.photo,
        'После прогулки или тренировки — селфи',
        'A selfie after a walk or workout'),
    DailyTask('photo_night', MemoryType.photo,
        'Сфоткай вечерний вид', 'Snap the evening view'),
    DailyTask('photo_name', MemoryType.photo,
        'Напиши имя {p} и сфоткай', "Write {p}'s name and snap it"),
    DailyTask('photo_round', MemoryType.photo,
        'Найди что-то круглое и сфоткай', 'Find something round and snap it'),
    DailyTask('photo_shadow', MemoryType.photo,
        'Сфоткай свою тень', 'Snap your shadow'),
    DailyTask('photo_soft', MemoryType.photo,
        'Сфоткай что-то мягкое рядом', 'Snap something soft nearby'),
    DailyTask('photo_favspot', MemoryType.photo,
        'Твоё любимое место дома — в кадр',
        'Your favourite spot at home — snap it'),
    DailyTask('photo_new', MemoryType.photo,
        'Сфоткай что-то новое у тебя', "Snap something new you've got"),
    DailyTask('photo_flower', MemoryType.photo,
        'Найди цветок и сфоткай для {p}',
        'Find a flower and snap it for {p}'),
    DailyTask('photo_sunray', MemoryType.photo,
        'Поймай солнечный лучик', 'Catch a ray of sun'),
    DailyTask('photo_detail', MemoryType.photo,
        'Сфоткай красивую деталь вокруг',
        'Snap a beautiful detail around you'),
    DailyTask('photo_evening', MemoryType.photo,
        'Как выглядит твой вечер?', 'What does your evening look like?'),
    DailyTask('photo_corner', MemoryType.photo,
        'Сфоткай самый милый угол дома',
        'Snap the cutest corner of your home'),
    DailyTask('photo_blue', MemoryType.photo,
        'Найди рядом что-то синее и сфоткай',
        'Find something blue nearby and snap it'),
    DailyTask('photo_smile2', MemoryType.photo,
        'Улыбнись как {p} и сфоткай', 'Smile like {p} and snap it'),
    DailyTask('photo_drinkfav', MemoryType.photo,
        'Твой любимый напиток в кадре', 'Your favourite drink in frame'),
    DailyTask('photo_today', MemoryType.photo,
        'Один кадр, который описывает твой день',
        'One shot that sums up your day'),

    // ── 📝 Заметка ────────────────────────────────────────────────────────
    DailyTask('text_bestthing', MemoryType.text,
        'Что лучшее в {p}?', "What's the best thing about {p}?"),
    DailyTask('text_laugh', MemoryType.text,
        'Когда {p} рассмешил тебя в последний раз?',
        'When did {p} last make you laugh?'),
    DailyTask('text_lyric', MemoryType.text,
        'Строчка из песни, которая про вас',
        "A song lyric that's about you two"),
    DailyTask('text_perfectdate', MemoryType.text,
        'Опиши ваше идеальное свидание', 'Describe your perfect date'),
    DailyTask('text_goodmorning', MemoryType.text,
        'Доброе утро для {p} своими словами',
        'A good-morning to {p} in your own words'),
    DailyTask('text_goodnight', MemoryType.text,
        'Спокойной ночи для {p}', 'A goodnight for {p}'),
    DailyTask('text_admire', MemoryType.text,
        'Чем ты восхищаешься в {p}?', 'What do you admire about {p}?'),
    DailyTask('text_taught', MemoryType.text,
        'Чему тебя научил {p}?', 'What has {p} taught you?'),
    DailyTask('text_smell', MemoryType.text,
        'Какой запах напоминает о {p}?', 'What smell reminds you of {p}?'),
    DailyTask('text_escape', MemoryType.text,
        'Куда бы вы сбежали вдвоём?', 'Where would you escape together?'),
    DailyTask('text_firstimpression', MemoryType.text,
        'Первое впечатление о {p}?', 'Your first impression of {p}?'),
    DailyTask('text_habit', MemoryType.text,
        'Какая привычка {p} тебя умиляет?',
        "Which of {p}'s habits melts you?"),
    DailyTask('text_safe', MemoryType.text,
        'Когда рядом с {p} тебе спокойнее всего?',
        'When do you feel safest with {p}?'),
    DailyTask('text_support', MemoryType.text,
        'За что хочешь поддержать {p}?', 'What would you cheer {p} on for?'),
    DailyTask('text_word', MemoryType.text,
        'Одно слово про твой день', 'One word for your day'),
    DailyTask('text_weekbest', MemoryType.text,
        'Лучший момент недели', 'The best moment of your week'),
    DailyTask('text_promise', MemoryType.text,
        'Маленькое обещание для {p}', 'A little promise for {p}'),
    DailyTask('text_weekend', MemoryType.text,
        'Идеальные выходные с {p}', 'An ideal weekend with {p}'),
    DailyTask('text_cookfor', MemoryType.text,
        'Что бы приготовил для {p}?', 'What would you cook for {p}?'),
    DailyTask('text_sweet', MemoryType.text,
        'Просто напиши что-то милое', 'Just write something sweet'),
    DailyTask('text_smallthing', MemoryType.text,
        'За какую мелочь ты благодарен сегодня?',
        'What small thing are you grateful for today?'),
    DailyTask('text_rightnow', MemoryType.text,
        'Что бы ты сделал для {p} прямо сейчас?',
        'What would you do for {p} right now?'),
    DailyTask('text_energize', MemoryType.text,
        'Что заряжает тебя рядом с {p}?', 'What energises you about {p}?'),
    DailyTask('text_firstdate', MemoryType.text,
        'Вспомни ваше первое свидание', 'Recall your first date'),
    DailyTask('text_callreason', MemoryType.text,
        'Найди повод позвонить {p}', 'Find a reason to call {p}'),
    DailyTask('text_whysmile', MemoryType.text,
        'Пусть {p} узнает, почему ты улыбаешься',
        "Let {p} know why you're smiling"),
    DailyTask('text_win', MemoryType.text,
        'Твоя маленькая победа сегодня', 'Your small win today'),
    DailyTask('text_feellike', MemoryType.text,
        'Чего тебе сейчас хочется?', 'What do you feel like right now?'),
    DailyTask('text_trait', MemoryType.text,
        'Любимая черта {p}?', 'Your favourite trait of {p}?'),
    DailyTask('text_justbeing', MemoryType.text,
        'Скажи спасибо {p} просто за то, что он есть',
        'Thank {p} just for being here'),
    DailyTask('text_triptogether', MemoryType.text,
        'Куда мечтаешь поехать вместе?',
        'Where do you dream of travelling together?'),
    DailyTask('text_noteyear', MemoryType.text,
        'Оставь послание вам через год',
        'Leave a note to you two a year from now'),
    DailyTask('text_favmemory2', MemoryType.text,
        'Момент с {p}, который хочется повторить',
        'A moment with {p} you want to relive'),
    DailyTask('text_grateful2', MemoryType.text,
        'Три вещи, за которые ты благодарен сегодня',
        'Three things you are grateful for today'),

    // ── 📍 Локация ────────────────────────────────────────────────────────
    DailyTask('loc_work', MemoryType.location,
        'Отметь, где ты работаешь или учишься',
        'Mark where you work or study'),
    DailyTask('loc_lunch', MemoryType.location,
        'Отметь, где обедал', 'Mark where you had lunch'),
    DailyTask('loc_park', MemoryType.location,
        'Отметь ближайший парк', 'Mark the nearest park'),
    DailyTask('loc_shop', MemoryType.location,
        'Отметь, где сейчас за покупками', "Mark where you're shopping"),
    DailyTask('loc_gym', MemoryType.location,
        'Отметь, где тренировался', 'Mark where you worked out'),
    DailyTask('loc_sunset', MemoryType.location,
        'Отметь точку с красивым закатом',
        'Mark a spot with a nice sunset'),
    DailyTask('loc_shared', MemoryType.location,
        'Отметь место с общим воспоминанием',
        'Mark a place with a shared memory'),
    DailyTask('loc_newplace', MemoryType.location,
        'Отметь новое место, где сегодня был',
        'Mark a new place you visited today'),
    DailyTask('loc_kiss', MemoryType.location,
        'Отметь место вашего первого поцелуя',
        'Mark the place of your first kiss'),
    DailyTask('loc_cafe', MemoryType.location,
        'Отметь ваше любимое кафе', 'Mark your favourite café'),
    DailyTask('loc_water', MemoryType.location,
        'Отметь место у воды рядом', 'Mark a spot by the water nearby'),
    DailyTask('loc_town', MemoryType.location,
        'Отметь любимое место в твоём городе',
        'Mark a favourite place in your town'),
    DailyTask('loc_night', MemoryType.location,
        'Отметь, где ты этим вечером', 'Mark where you are this evening'),
    DailyTask('loc_dreamcountry', MemoryType.location,
        'Отметь страну мечты для вас двоих',
        'Mark a dream country for you two'),
    DailyTask('loc_calm', MemoryType.location,
        'Отметь место, где тебе спокойно',
        'Mark a place where you feel calm'),
    DailyTask('loc_next', MemoryType.location,
        'Куда пойдёте в следующий раз вместе?',
        'Where will you go together next?'),
    DailyTask('loc_hidden', MemoryType.location,
        'Отметь уютное местечко, о котором мало кто знает',
        'Mark a cosy hidden spot'),
    DailyTask('loc_skyview', MemoryType.location,
        'Отметь место с видом на небо',
        'Mark a spot with a view of the sky'),
    DailyTask('loc_market', MemoryType.location,
        'Отметь рынок или магазинчик рядом',
        'Mark a market or little shop nearby'),

    // ── 🎵 Музыка ─────────────────────────────────────────────────────────
    DailyTask('mus_energy2', MemoryType.music,
        'Твой трек для энергии', 'Your track for energy'),
    DailyTask('mus_sad', MemoryType.music,
        'Песня для грустного настроения', 'A song for a blue mood'),
    DailyTask('mus_happy', MemoryType.music,
        'Песня, которая тебя радует', 'A song that makes you happy'),
    DailyTask('mus_firstdate', MemoryType.music,
        'Песня, что играла на вашем первом свидании?',
        'A song from your first date?'),
    DailyTask('mus_karaoke', MemoryType.music,
        'Что бы вы спели в караоке вдвоём?',
        'What would you two sing at karaoke?'),
    DailyTask('mus_childhood', MemoryType.music,
        'Песня из детства', 'A song from your childhood'),
    DailyTask('mus_guilty', MemoryType.music,
        'Твой «стыдный» любимый трек', 'Your guilty-pleasure track'),
    DailyTask('mus_relax', MemoryType.music,
        'Что слушаешь, чтобы расслабиться?',
        'What do you listen to to relax?'),
    DailyTask('mus_playlist', MemoryType.music,
        'Плейлист-настроение для {p}', 'A mood playlist for {p}'),
    DailyTask('mus_newfav', MemoryType.music,
        'Новый любимый трек', 'A new favourite track'),
    DailyTask('mus_slow', MemoryType.music,
        'Медленная песня для вас двоих',
        'A slow song for the two of you'),
    DailyTask('mus_wakeup', MemoryType.music,
        'Что бы поставил, чтобы разбудить {p}?',
        'What would you play to wake {p} up?'),
    DailyTask('mus_summer', MemoryType.music,
        'Песня, что звучит как лето', 'A song that sounds like summer'),
    DailyTask('mus_cover', MemoryType.music,
        'Любимый кавер', 'A favourite cover'),
    DailyTask('mus_instrumental', MemoryType.music,
        'Мелодия без слов, которая цепляет',
        'A wordless tune that grabs you'),
    DailyTask('mus_latenight', MemoryType.music,
        'Песня для позднего вечера', 'A song for late night'),
    DailyTask('mus_dance2', MemoryType.music,
        'Трек, под который хочется танцевать',
        'A track that makes you want to dance'),
    DailyTask('mus_nostalgia', MemoryType.music,
        'Песня, что возвращает в прошлое',
        'A song that takes you back'),
    DailyTask('mus_week', MemoryType.music,
        'Твой трек этой недели', 'Your track of the week'),

    // ── 🎬 Фильм ──────────────────────────────────────────────────────────
    DailyTask('mov_rewatch', MemoryType.movie,
        'Фильм, который пересматриваешь всегда',
        'A film you always rewatch'),
    DailyTask('mov_scary', MemoryType.movie,
        'Ужастик, чтобы прижаться друг к другу',
        'A scary film to cuddle through'),
    DailyTask('mov_animation', MemoryType.movie,
        'Мультик на двоих', 'An animated film for two'),
    DailyTask('mov_datenight', MemoryType.movie,
        'Идеальный фильм для свидания', 'The perfect date-night film'),
    DailyTask('mov_recommend', MemoryType.movie,
        'Фильм, который советуешь {p}', "A film you'd recommend to {p}"),
    DailyTask('mov_underrated', MemoryType.movie,
        'Недооценённый фильм, который любишь',
        'An underrated film you love'),
    DailyTask('mov_binge', MemoryType.movie,
        'Сериал, который проглотил залпом', 'A series you binged'),
    DailyTask('mov_feelgood', MemoryType.movie,
        'Фильм, поднимающий настроение', 'A feel-good film'),

    // ── 📚 Книга ──────────────────────────────────────────────────────────
    DailyTask('book_bedtime', MemoryType.book,
        'Книга, которую читаешь перед сном',
        'A book you read before bed'),
    DailyTask('book_author', MemoryType.book,
        'Любимый автор — поделись', 'Your favourite author — share'),
    DailyTask('book_childhood', MemoryType.book,
        'Книга из детства', 'A book from your childhood'),
    DailyTask('book_wishlist', MemoryType.book,
        'Книга, которую давно хочешь прочитать',
        "A book you've long wanted to read"),
    DailyTask('book_gift', MemoryType.book,
        'Книга, которую подарил бы {p}', "A book you'd gift {p}"),
    DailyTask('book_reread', MemoryType.book,
        'Книга, которую перечитывал', "A book you've reread"),
    DailyTask('book_comfort', MemoryType.book,
        'Книга, к которой возвращаешься за уютом',
        'A comfort book you return to'),

    // ── 🎬 Видео-ссылка ───────────────────────────────────────────────────
    DailyTask('vid_music', MemoryType.videoLink,
        'Клип любимой песни', 'A music video of a favourite song'),
    DailyTask('vid_inspire', MemoryType.videoLink,
        'Видео, которое вдохновляет', 'A video that inspires you'),
    DailyTask('vid_learn', MemoryType.videoLink,
        'Видео, из которого узнал что-то новое',
        'A video you learned something from'),
    DailyTask('vid_watchtogether', MemoryType.videoLink,
        'Видео, которое хочешь посмотреть с {p}',
        'A video to watch with {p}'),

    // ── Третья двухсотка (28.09.2026) ─────────────────────────────────────
    // Глаголы без прошедшего времени и без рода: «увидел», «поел» из первых
    // двухсот читаются мужской формой у всех, новые пишутся так, чтобы род
    // не понадобился вовсе.

    // ── 🎥 Своё видео — снял и отправил ────────────────────────────────────
    DailyTask('clip_around', MemoryType.video,
        'Сними пять секунд того, что вокруг',
        'Film five seconds of what’s around you'),
    DailyTask('clip_hello', MemoryType.video,
        'Скажи «привет» для {p} на видео', 'Say hi to {p} on video'),
    DailyTask('clip_sky', MemoryType.video,
        'Сними небо, пусть {p} посмотрит', 'Film the sky for {p}'),
    DailyTask('clip_walk', MemoryType.video,
        'Сними несколько шагов своей дороги',
        'Film a few steps of your way'),
    DailyTask('clip_sound', MemoryType.video,
        'Сними, как звучит место, где ты сейчас',
        'Film what your place sounds like right now'),
    DailyTask('clip_pet', MemoryType.video,
        'Сними питомца или любого зверька рядом',
        'Film a pet or any animal nearby'),
    DailyTask('clip_cook', MemoryType.video,
        'Сними, как готовишь или завариваешь чай',
        'Film yourself cooking or making tea'),
    DailyTask('clip_window', MemoryType.video,
        'Сними вид из окна', 'Film the view from your window'),
    DailyTask('clip_laugh', MemoryType.video,
        'Сними то, что тебя смешит', 'Film something that makes you laugh'),
    DailyTask('clip_dance', MemoryType.video,
        'Три секунды танца для {p}', 'Three seconds of dancing for {p}'),
    DailyTask('clip_goodnight', MemoryType.video,
        'Пожелай спокойной ночи для {p} на видео',
        'Wish {p} good night on video'),
    DailyTask('clip_morning', MemoryType.video,
        'Утреннее видео для {p}', 'A morning video for {p}'),
    DailyTask('clip_road', MemoryType.video,
        'Сними дорогу из окна автобуса или машины',
        'Film the road from a bus or car window'),
    DailyTask('clip_water', MemoryType.video,
        'Сними воду: дождь, реку, фонтан', 'Film water: rain, a river, a fountain'),
    DailyTask('clip_room', MemoryType.video,
        'Покажи свою комнату на видео', 'Show your room on video'),
    DailyTask('clip_kiss', MemoryType.video,
        'Воздушный поцелуй для {p} на видео', 'Blow {p} a kiss on video'),
    DailyTask('clip_slowmo', MemoryType.video,
        'Сними что-нибудь в замедленной съёмке',
        'Film something in slow motion'),
    DailyTask('clip_food', MemoryType.video,
        'Сними свою еду, пока она горячая',
        'Film your food while it’s still hot'),
    DailyTask('clip_music', MemoryType.video,
        'Сними, что сейчас играет рядом с тобой',
        'Film what’s playing around you'),
    DailyTask('clip_wind', MemoryType.video,
        'Сними деревья или траву на ветру', 'Film trees or grass in the wind'),
    DailyTask('clip_lights', MemoryType.video,
        'Сними вечерние огни', 'Film the evening lights'),
    DailyTask('clip_write', MemoryType.video,
        'Сними, как пишешь что-то от руки для {p}',
        'Film yourself writing something by hand for {p}'),
    DailyTask('clip_secret', MemoryType.video,
        'Шепни секрет для {p} на видео', 'Whisper a secret to {p} on video'),
    DailyTask('clip_today', MemoryType.video,
        'Твой день за десять секунд', 'Your day in ten seconds'),
    DailyTask('clip_face', MemoryType.video,
        'Смешная рожица для {p} на видео', 'A funny face for {p} on video'),

    // ── 📷 Фото ───────────────────────────────────────────────────────────
    DailyTask('photo_bag', MemoryType.photo,
        'Покажи, что у тебя в сумке или кармане',
        'Show what’s in your bag or pocket'),
    DailyTask('photo_keys', MemoryType.photo,
        'Сфоткай свои ключи и брелок', 'Snap your keys and keychain'),
    DailyTask('photo_wallpaper', MemoryType.photo,
        'Покажи обои на своём телефоне', 'Show your phone wallpaper'),
    DailyTask('photo_bed', MemoryType.photo,
        'Сфоткай, где будешь спать сегодня', 'Snap where you’ll sleep tonight'),
    DailyTask('photo_breakfast', MemoryType.photo,
        'Покажи свой завтрак', 'Show your breakfast'),
    DailyTask('photo_dinner', MemoryType.photo,
        'Покажи свой ужин', 'Show your dinner'),
    DailyTask('photo_socks', MemoryType.photo,
        'Покажи свои носки сегодня', 'Show today’s socks'),
    DailyTask('photo_heart', MemoryType.photo,
        'Найди сердечко в обычных вещах', 'Find a heart shape in everyday things'),
    DailyTask('photo_yellow', MemoryType.photo,
        'Найди что-то жёлтое и сфоткай', 'Find something yellow and snap it'),
    DailyTask('photo_green', MemoryType.photo,
        'Найди что-то зелёное и сфоткай', 'Find something green and snap it'),
    DailyTask('photo_red', MemoryType.photo,
        'Найди что-то красное и сфоткай', 'Find something red and snap it'),
    DailyTask('photo_letter', MemoryType.photo,
        'Найди вокруг первую букву имени {p}',
        'Find the first letter of {p}’s name around you'),
    DailyTask('photo_number', MemoryType.photo,
        'Найди число, которое что-то значит для вас',
        'Find a number that means something to you two'),
    DailyTask('photo_oldest', MemoryType.photo,
        'Сфоткай самую старую вещь рядом', 'Snap the oldest thing near you'),
    DailyTask('photo_tiny', MemoryType.photo,
        'Сфоткай самую маленькую вещь рядом', 'Snap the tiniest thing near you'),
    DailyTask('photo_up', MemoryType.photo,
        'Сфоткай, что над тобой', 'Snap what’s above you'),
    DailyTask('photo_behind', MemoryType.photo,
        'Сфоткай, что у тебя за спиной', 'Snap what’s behind you'),
    DailyTask('photo_door', MemoryType.photo,
        'Сфоткай свою входную дверь', 'Snap your front door'),
    DailyTask('photo_fridge', MemoryType.photo,
        'Покажи, что в холодильнике', 'Show what’s in your fridge'),
    DailyTask('photo_lamp', MemoryType.photo,
        'Сфоткай свою лампу или ночник', 'Snap your lamp or night light'),
    DailyTask('photo_cloud', MemoryType.photo,
        'Найди облако, похожее на что-то', 'Find a cloud that looks like something'),
    DailyTask('photo_leaf', MemoryType.photo,
        'Найди красивый лист и сфоткай', 'Find a pretty leaf and snap it'),
    DailyTask('photo_stone', MemoryType.photo,
        'Найди интересный камешек', 'Find an interesting pebble'),
    DailyTask('photo_street_art', MemoryType.photo,
        'Сфоткай граффити, плакат или вывеску рядом',
        'Snap graffiti, a poster or a sign nearby'),
    DailyTask('photo_funny_sign', MemoryType.photo,
        'Найди смешную надпись или вывеску', 'Find a funny sign or label'),
    DailyTask('photo_transport', MemoryType.photo,
        'Покажи, на чём сегодня едешь', 'Show how you’re getting around today'),
    DailyTask('photo_drawing', MemoryType.photo,
        'Нарисуй что-нибудь для {p} и сфоткай',
        'Draw something for {p} and snap it'),
    DailyTask('photo_handnote', MemoryType.photo,
        'Напиши записку для {p} от руки и сфоткай',
        'Write {p} a handwritten note and snap it'),
    DailyTask('photo_selfie_place', MemoryType.photo,
        'Селфи на фоне места, где ты сейчас',
        'A selfie with where you are in the background'),
    DailyTask('photo_silly', MemoryType.photo,
        'Самое смешное селфи для {p}', 'Your silliest selfie for {p}'),
    DailyTask('photo_serious', MemoryType.photo,
        'Самое серьёзное лицо для {p}', 'Your most serious face for {p}'),
    DailyTask('photo_eyes', MemoryType.photo,
        'Сфоткай свои глаза крупно', 'A close-up of your eyes'),
    DailyTask('photo_jewelry', MemoryType.photo,
        'Покажи украшение или часы, что на тебе',
        'Show the jewellery or watch you’re wearing'),
    DailyTask('photo_scent', MemoryType.photo,
        'Сфоткай свой любимый запах: духи, чай, свечу',
        'Snap your favourite scent: perfume, tea, a candle'),
    DailyTask('photo_shelf', MemoryType.photo,
        'Покажи одну из своих полок', 'Show one of your shelves'),
    DailyTask('photo_fruit', MemoryType.photo,
        'Сфоткай фрукт или овощ под рукой', 'Snap a fruit or vegetable near you'),
    DailyTask('photo_homewear', MemoryType.photo,
        'Покажи свою домашнюю одежду', 'Show your comfy home clothes'),
    DailyTask('photo_workview', MemoryType.photo,
        'Вид с места, где ты работаешь или учишься',
        'The view from where you work or study'),
    DailyTask('photo_waiting', MemoryType.photo,
        'Ждёшь чего-то? Покажи, где', 'Waiting somewhere? Show where'),
    DailyTask('photo_stars', MemoryType.photo,
        'Сфоткай ночное небо', 'Snap the night sky'),
    DailyTask('photo_moon', MemoryType.photo,
        'Найди луну и сфоткай', 'Find the moon and snap it'),
    DailyTask('photo_candle', MemoryType.photo,
        'Зажги свечу или ночник для {p} и сфоткай',
        'Light a candle or a lamp for {p} and snap it'),
    DailyTask('photo_giftfrom', MemoryType.photo,
        'Сфоткай подарок от {p}', 'Snap a gift from {p}'),
    DailyTask('photo_pattern', MemoryType.photo,
        'Найди узор: плитку, ткань, забор', 'Find a pattern: tiles, fabric, a fence'),
    DailyTask('photo_bird', MemoryType.photo,
        'Найди птицу и сфоткай', 'Find a bird and snap it'),

    // ── 📝 Заметка ────────────────────────────────────────────────────────
    DailyTask('text_todaylist', MemoryType.text,
        'Три дела, которые сделаешь сегодня', 'Three things you’ll do today'),
    DailyTask('text_tomorrow', MemoryType.text,
        'Чего ждёшь от завтра?', 'What are you looking forward to tomorrow?'),
    DailyTask('text_weird', MemoryType.text,
        'Самая странная мысль за сегодня', 'The weirdest thought you had today'),
    DailyTask('text_superpower', MemoryType.text,
        'Какая суперсила подошла бы {p}?', 'What superpower would suit {p}?'),
    DailyTask('text_animal', MemoryType.text,
        '{p} в образе зверька: кто это?', 'If {p} were an animal, which one?'),
    DailyTask('text_song_about', MemoryType.text,
        'О чём была бы песня про {p}?', 'What would a song about {p} be about?'),
    DailyTask('text_movie_title', MemoryType.text,
        'Название фильма про вашу пару', 'A movie title for your love story'),
    DailyTask('text_emoji3', MemoryType.text,
        'Опиши свой день тремя эмодзи', 'Describe your day in three emoji'),
    DailyTask('text_color_day', MemoryType.text,
        'Какого цвета твой день?', 'What colour is your day?'),
    DailyTask('text_ask', MemoryType.text,
        'Задай {p} вопрос, который давно хочешь',
        'Ask {p} a question you’ve been meaning to'),
    DailyTask('text_learned', MemoryType.text,
        'Что нового ты узнаёшь в последнее время?',
        'Something new you’ve learned lately'),
    DailyTask('text_proud_self', MemoryType.text,
        'Чем ты гордишься в себе сегодня?',
        'What are you proud of yourself for today?'),
    DailyTask('text_worry', MemoryType.text,
        'Что тебя тревожит? Пусть {p} поможет',
        'What’s worrying you? Let {p} help'),
    DailyTask('text_support_me', MemoryType.text,
        'Как {p} может поддержать тебя сегодня?',
        'How can {p} support you today?'),
    DailyTask('text_plan_week', MemoryType.text,
        'Предложи, что сделать вместе на этой неделе',
        'Suggest something to do together this week'),
    DailyTask('text_ten_years', MemoryType.text,
        'Где вы будете через десять лет?', 'Where will you two be in ten years?'),
    DailyTask('text_future_home', MemoryType.text,
        'Опиши ваш будущий дом', 'Describe your future home together'),
    DailyTask('text_pet', MemoryType.text,
        'Какого питомца вы бы завели?', 'What pet would you get together?'),
    DailyTask('text_dish', MemoryType.text,
        'Блюдо, которое хочешь приготовить вместе',
        'A dish you want to cook together'),
    DailyTask('text_tradition', MemoryType.text,
        'Придумай вашу маленькую традицию', 'Invent a little tradition for you two'),
    DailyTask('text_insidejoke', MemoryType.text,
        'Ваша общая шутка: напомни её', 'Your inside joke: bring it back'),
    DailyTask('text_quote', MemoryType.text,
        'Фраза {p}, которая запала в душу', 'Something {p} said that stuck with you'),
    DailyTask('text_letter', MemoryType.text,
        'Короткое письмо для {p}', 'A short letter for {p}'),
    DailyTask('text_poem', MemoryType.text,
        'Четыре строчки для {p}, рифма не обязательна',
        'Four lines for {p}, rhyme optional'),
    DailyTask('text_rate', MemoryType.text,
        'Оцени свой день от 1 до 10 и объясни',
        'Rate your day from 1 to 10 and say why'),
    DailyTask('text_fail', MemoryType.text,
        'Самая смешная неудача дня', 'The funniest fail of your day'),
    DailyTask('text_recommend', MemoryType.text,
        'Посоветуй {p} что-нибудь: подкаст, блюдо, место',
        'Recommend {p} something: a podcast, a dish, a place'),
    DailyTask('text_million', MemoryType.text,
        'Что бы вы сделали с миллионом на двоих?',
        'What would you two do with a million?'),
    DailyTask('text_teach', MemoryType.text,
        'Чему хочешь научить {p}?', 'What would you like to teach {p}?'),
    DailyTask('text_learn_together', MemoryType.text,
        'Чему хочешь научиться вместе?', 'What would you like to learn together?'),
    DailyTask('text_fav_photo', MemoryType.text,
        'Опиши ваше любимое совместное фото',
        'Describe your favourite photo of you two'),
    DailyTask('text_calm', MemoryType.text,
        'Что тебя сегодня успокоило?', 'What calmed you down today?'),
    DailyTask('text_energy', MemoryType.text,
        'Сколько у тебя сейчас сил, в процентах?',
        'How much energy do you have right now, in percent?'),
    DailyTask('text_inner_weather', MemoryType.text,
        'Какая погода у тебя внутри?', 'What’s the weather like inside you?'),
    DailyTask('text_secret_skill', MemoryType.text,
        'Твоё тайное умение, о котором {p} не знает',
        'A secret skill {p} doesn’t know about'),
    DailyTask('text_childhood', MemoryType.text,
        'Расскажи {p} случай из детства', 'Tell {p} a story from your childhood'),
    DailyTask('text_dream_night', MemoryType.text,
        'Что тебе снилось?', 'What did you dream about?'),
    DailyTask('text_three_wishes', MemoryType.text,
        'Три желания для вас двоих', 'Three wishes for the two of you'),
    DailyTask('text_someday', MemoryType.text,
        'Одно дело из вашего списка «когда-нибудь»',
        'One thing from your “someday” list'),
    DailyTask('text_miss_little', MemoryType.text,
        'По какой мелочи в {p} скучаешь?', 'What little thing about {p} do you miss?'),
    DailyTask('text_favword', MemoryType.text,
        'Любимое словечко {p}', 'A word {p} always says'),
    DailyTask('text_honest', MemoryType.text,
        'Честно: что сегодня пошло не так?', 'Honestly: what went wrong today?'),
    DailyTask('text_future_me', MemoryType.text,
        'Что скажешь себе через год?', 'What would you tell yourself in a year?'),
    DailyTask('text_proud_us', MemoryType.text,
        'Чем ты гордишься в вашей паре?', 'What are you proud of in your relationship?'),
    DailyTask('text_perfect_morning', MemoryType.text,
        'Опиши идеальное утро вдвоём', 'Describe a perfect morning together'),

    // ── 📍 Локация ────────────────────────────────────────────────────────
    DailyTask('loc_bench', MemoryType.location,
        'Отметь скамейку, где хорошо сидеть', 'Mark a bench that’s nice to sit on'),
    DailyTask('loc_bakery', MemoryType.location,
        'Отметь пекарню или кондитерскую рядом',
        'Mark a bakery or pastry shop nearby'),
    DailyTask('loc_library', MemoryType.location,
        'Отметь библиотеку или книжный', 'Mark a library or bookshop'),
    DailyTask('loc_cinema', MemoryType.location,
        'Отметь кинотеатр, куда сходите вместе',
        'Mark a cinema you’ll go to together'),
    DailyTask('loc_museum', MemoryType.location,
        'Отметь музей или выставку, куда хочешь',
        'Mark a museum or exhibition you want to see'),
    DailyTask('loc_picnic', MemoryType.location,
        'Отметь место для пикника', 'Mark a spot for a picnic'),
    DailyTask('loc_icecream', MemoryType.location,
        'Отметь, где продают вкусное мороженое',
        'Mark where they sell good ice cream'),
    DailyTask('loc_station', MemoryType.location,
        'Отметь остановку или вокзал, откуда едешь',
        'Mark the stop or station you leave from'),
    DailyTask('loc_high', MemoryType.location,
        'Отметь высокую точку в городе', 'Mark a high point in your city'),
    DailyTask('loc_childhood', MemoryType.location,
        'Отметь место из своего детства', 'Mark a place from your childhood'),
    DailyTask('loc_school', MemoryType.location,
        'Отметь свою школу или университет', 'Mark your school or university'),
    DailyTask('loc_alone', MemoryType.location,
        'Отметь место, где любишь побыть наедине с собой',
        'Mark a place where you like to be on your own'),
    DailyTask('loc_walkend', MemoryType.location,
        'Отметь, где заканчивается твоя прогулка', 'Mark where your walk ends'),
    DailyTask('loc_restaurant', MemoryType.location,
        'Отметь ресторан для особого вечера',
        'Mark a restaurant for a special evening'),
    DailyTask('loc_breakfast', MemoryType.location,
        'Отметь, где вкусно завтракать', 'Mark a good place for breakfast'),
    DailyTask('loc_nature', MemoryType.location,
        'Отметь место на природе рядом с городом',
        'Mark a nature spot near your city'),
    DailyTask('loc_beach', MemoryType.location,
        'Отметь пляж, куда хочешь с {p}', 'Mark a beach you want to go to with {p}'),
    DailyTask('loc_mountains', MemoryType.location,
        'Отметь горы, куда хочешь съездить', 'Mark mountains you want to visit'),
    DailyTask('loc_weekend_city', MemoryType.location,
        'Отметь город для выходных вдвоём', 'Mark a city for a weekend together'),
    DailyTask('loc_concert', MemoryType.location,
        'Отметь, где хочешь сходить на концерт',
        'Mark where you’d go to a concert'),
    DailyTask('loc_photospot', MemoryType.location,
        'Отметь место для вашего лучшего совместного фото',
        'Mark a spot for your best photo together'),
    DailyTask('loc_sport', MemoryType.location,
        'Отметь, где можно покататься или побегать вдвоём',
        'Mark a place to ride or run together'),
    DailyTask('loc_flowers', MemoryType.location,
        'Отметь, где растут красивые цветы', 'Mark where pretty flowers grow'),
    DailyTask('loc_halfway', MemoryType.location,
        'Отметь точку ровно посередине между вами',
        'Mark the spot halfway between you'),
    DailyTask('loc_goodtoday', MemoryType.location,
        'Отметь, где сегодня случилось что-то хорошее',
        'Mark where something good happened today'),

    // ── 🎵 Музыка ─────────────────────────────────────────────────────────
    DailyTask('mus_rain', MemoryType.music,
        'Песня под дождь', 'A song for a rainy day'),
    DailyTask('mus_cook', MemoryType.music,
        'Что включаешь, когда готовишь?', 'What do you play while cooking?'),
    DailyTask('mus_focus', MemoryType.music,
        'Под что тебе лучше работается?', 'What helps you focus?'),
    DailyTask('mus_shower', MemoryType.music,
        'Песня, которую поёшь в душе', 'A song you sing in the shower'),
    DailyTask('mus_loud', MemoryType.music,
        'Трек, который включаешь на полную', 'A song you play at full volume'),
    DailyTask('mus_foreign', MemoryType.music,
        'Песня на языке, которого ты не знаешь',
        'A song in a language you don’t speak'),
    DailyTask('mus_older', MemoryType.music,
        'Песня, которая старше вас обоих', 'A song older than both of you'),
    DailyTask('mus_film', MemoryType.music,
        'Любимая песня из фильма', 'A favourite song from a movie'),
    DailyTask('mus_cartoon', MemoryType.music,
        'Песня из мультика, которую знаешь наизусть',
        'A cartoon song you know by heart'),
    DailyTask('mus_roadtrip', MemoryType.music,
        'Песня для поездки на машине вдвоём', 'A song for a road trip together'),
    DailyTask('mus_winter', MemoryType.music,
        'Песня, что звучит как зима', 'A song that sounds like winter'),
    DailyTask('mus_autumn', MemoryType.music,
        'Песня, что звучит как осень', 'A song that sounds like autumn'),
    DailyTask('mus_nightwalk', MemoryType.music,
        'Песня для ночной прогулки', 'A song for a night walk'),
    DailyTask('mus_cheer', MemoryType.music,
        'Песня, чтобы подбодрить {p}', 'A song to cheer {p} up'),
    DailyTask('mus_tender', MemoryType.music,
        'Самая нежная песня, которую знаешь', 'The tenderest song you know'),
    DailyTask('mus_story', MemoryType.music,
        'Песня, в которой узнаёшь вашу историю',
        'A song that tells your story'),
    DailyTask('mus_live', MemoryType.music,
        'Любимая живая запись песни', 'Your favourite live recording'),
    DailyTask('mus_artist', MemoryType.music,
        'Исполнитель, которого стоит послушать {p}',
        'An artist {p} should listen to'),
    DailyTask('mus_first', MemoryType.music,
        'Самая первая любимая песня', 'Your very first favourite song'),
    DailyTask('mus_stuck', MemoryType.music,
        'Песня, которая весь день крутится в голове',
        'A song stuck in your head all day'),
    DailyTask('mus_sleep', MemoryType.music,
        'Песня, чтобы уснуть', 'A song to fall asleep to'),
    DailyTask('mus_weekend', MemoryType.music,
        'Саундтрек ваших выходных', 'The soundtrack to your weekend'),
    DailyTask('mus_birthday', MemoryType.music,
        'Песня для дня рождения {p}', 'A song for {p}’s birthday'),
    DailyTask('mus_school', MemoryType.music,
        'Песня из школьных времён', 'A song from your school days'),
    DailyTask('mus_credits', MemoryType.music,
        'Песня для финальных титров твоего дня',
        'A song for the end credits of your day'),

    // ── 🎬 Фильм ──────────────────────────────────────────────────────────
    DailyTask('mov_romance', MemoryType.movie,
        'Романтический фильм на вечер', 'A romantic movie for tonight'),
    DailyTask('mov_quote', MemoryType.movie,
        'Фильм с фразой, которую ты повторяешь',
        'A movie with a line you keep quoting'),
    DailyTask('mov_cozy', MemoryType.movie,
        'Фильм под плед и чай', 'A movie for a blanket and tea night'),
    DailyTask('mov_adventure', MemoryType.movie,
        'Приключение, в которое хочется попасть вдвоём',
        'An adventure you’d both jump into'),
    DailyTask('mov_space', MemoryType.movie,
        'Фильм про космос', 'A movie about space'),
    DailyTask('mov_old', MemoryType.movie,
        'Старый фильм, который стоит увидеть', 'An old movie worth seeing'),
    DailyTask('mov_short', MemoryType.movie,
        'Фильм короче полутора часов на вечер',
        'A movie under 90 minutes for tonight'),
    DailyTask('mov_new', MemoryType.movie,
        'Новинка, которую хотите посмотреть', 'A new release you both want to see'),
    DailyTask('mov_country', MemoryType.movie,
        'Фильм из страны, где вы ещё не были',
        'A movie from a country you haven’t been to'),
    DailyTask('mov_music', MemoryType.movie,
        'Фильм про музыку', 'A movie about music'),
    DailyTask('mov_couple', MemoryType.movie,
        'Фильм про пару, похожую на вас', 'A movie about a couple like you'),
    DailyTask('mov_holiday', MemoryType.movie,
        'Фильм для праздничного настроения', 'A movie for a holiday mood'),
    DailyTask('mov_talk', MemoryType.movie,
        'Фильм, который захочется обсудить', 'A movie you’ll want to talk about'),
    DailyTask('mov_miniseries', MemoryType.movie,
        'Короткий сериал на выходные', 'A short series for the weekend'),
    DailyTask('mov_anime', MemoryType.movie,
        'Аниме или мультфильм для взрослых',
        'An anime or an animated film for grown-ups'),

    // ── 📚 Книга ──────────────────────────────────────────────────────────
    DailyTask('book_evening', MemoryType.book,
        'Книга, которую можно прочитать за вечер',
        'A book you can read in one evening'),
    DailyTask('book_poetry', MemoryType.book,
        'Стихи, которые тебе нравятся', 'Poems you love'),
    DailyTask('book_world', MemoryType.book,
        'Книга, в мир которой хочешь попасть',
        'A book whose world you’d love to step into'),
    DailyTask('book_hero', MemoryType.book,
        'Книга с героем, похожим на {p}', 'A book with a character like {p}'),
    DailyTask('book_funny', MemoryType.book,
        'Книга, от которой смешно', 'A book that makes you laugh'),
    DailyTask('book_tears', MemoryType.book,
        'Книга, которая растрогала до слёз', 'A book that moved you to tears'),
    DailyTask('book_travel', MemoryType.book,
        'Книга о путешествиях', 'A book about travel'),
    DailyTask('book_audio', MemoryType.book,
        'Аудиокнига для дороги', 'An audiobook for the road'),
    DailyTask('book_classic', MemoryType.book,
        'Классика, до которой всё не доходят руки',
        'A classic you still haven’t got to'),
    DailyTask('book_love', MemoryType.book,
        'Книга о любви', 'A book about love'),

    // ── 🎬 Видео-ссылка ───────────────────────────────────────────────────
    DailyTask('vid_recipe', MemoryType.videoLink,
        'Рецепт на видео, который хотите повторить',
        'A video recipe you want to try together'),
    DailyTask('vid_place', MemoryType.videoLink,
        'Видео о месте, куда хочешь поехать',
        'A video about a place you want to visit'),
    DailyTask('vid_animals', MemoryType.videoLink,
        'Видео с животными, от которого тает сердце',
        'An animal video that melts your heart'),
    DailyTask('vid_diy', MemoryType.videoLink,
        'Что можно сделать своими руками вдвоём',
        'A DIY video you could do together'),
    DailyTask('vid_dance', MemoryType.videoLink,
        'Танец, который хотите разучить', 'A dance you want to learn together'),
    DailyTask('vid_podcast', MemoryType.videoLink,
        'Интервью или подкаст, который стоит посмотреть',
        'An interview or podcast worth watching'),
    DailyTask('vid_nostalgia', MemoryType.videoLink,
        'Видео, которое возвращает в детство',
        'A video that takes you back to childhood'),
    DailyTask('vid_calm', MemoryType.videoLink,
        'Спокойное видео для вечера', 'A calming video for the evening'),
    DailyTask('vid_space', MemoryType.videoLink,
        'Видео про космос', 'A video about space'),
    DailyTask('vid_lifehack', MemoryType.videoLink,
        'Лайфхак, который пригодится вам обоим',
        'A life hack you’ll both find useful'),
  ];
}

/// Сколько заданий в наборе на день.
const int kDailyTaskCount = 3;

/// День, с которого пара идёт по своему порядку каталога. Сдвигать нельзя:
/// у всех пар разом сменились бы задания посреди дня.
final DateTime _kTaskEpoch = DateTime.utc(2026, 9, 28);

/// Задания одного дня: три основных и бонус, который открывается, когда пара
/// закрыла все три. Бонус монеты не приносит — сервер платит за три в сутки.
class DailyTaskDay {
  const DailyTaskDay(this.main, this.bonus);

  final List<DailyTask> main;
  final DailyTask? bonus;
}

/// Хэш строки: нужен устойчивый и одинаковый на обеих платформах, поэтому
/// считаем сами, а не через hashCode — он не обещает стабильности между
/// запусками.
int _stableSeed(String key) {
  var seed = 2166136261;
  for (final unit in key.codeUnits) {
    seed = (seed ^ unit) * 16777619 & 0x7FFFFFFF;
  }
  return seed;
}

/// Каталог, перемешанный для пары на круг номер [round].
List<DailyTask> _roundOrder(String pairId, int round) {
  final order = List<DailyTask>.from(DailyTask.all);
  var cursor = _stableSeed('$pairId|$round');
  for (var i = order.length - 1; i > 0; i--) {
    cursor = (cursor * 1103515245 + 12345) & 0x7FFFFFFF;
    final j = cursor % (i + 1);
    final t = order[i];
    order[i] = order[j];
    order[j] = t;
  }
  return order;
}

final Map<String, DailyTaskDay> _dayCache = {};

/// Задания дня для пары.
///
/// Сервер в выборе не участвует: у каждой пары каталог перемешан один раз, и
/// дни идут по нему подряд, поэтому у обоих партнёров набор совпадает без
/// единого запроса, а задание возвращается, только когда пройден весь
/// каталог. До 28.09.2026 набор брался случайно на каждый день, и одно и то же
/// задание могло выпасть два дня подряд.
///
/// Типы пинов среди основных трёх разные: три задания «сделай фото» читаются
/// как одно задание трижды. Не взятое в свой день задание остаётся в очереди и
/// уходит в ближайший день, где его тип свободен.
DailyTaskDay dailyTaskDayFor({required DateTime day, required String pairId}) {
  final utc = day.toUtc();
  final date = DateTime.utc(utc.year, utc.month, utc.day);
  final index = date.difference(_kTaskEpoch).inDays.clamp(0, 1 << 20);
  final cacheKey = '$pairId|$index';
  final cached = _dayCache[cacheKey];
  if (cached != null) return cached;

  final slots = kDailyTaskCount + 1;
  final pending = <DailyTask>[];
  var round = 0;
  var picked = <DailyTask>[];
  for (var d = 0; d <= index; d++) {
    picked = <DailyTask>[];
    final types = <MemoryType>{};
    var refilled = false;
    while (true) {
      for (final task in pending) {
        if (picked.length == slots) break;
        if (types.contains(task.type)) continue;
        types.add(task.type);
        picked.add(task);
      }
      if (picked.length == slots || refilled) break;
      // Очередь кончилась или в ней остались одни и те же типы — берём
      // следующий круг. Что ещё лежит в очереди, второй раз не кладём, иначе
      // хвост прошлого круга встретился бы с собой через пару дней.
      final queued = {for (final t in pending) t.id};
      pending.addAll(
          _roundOrder(pairId, round++).where((t) => !queued.contains(t.id)));
      refilled = true;
    }
    for (final task in picked) {
      pending.remove(task);
    }
  }

  if (_dayCache.length > 64) _dayCache.clear();
  final result = DailyTaskDay(
    picked.take(kDailyTaskCount).toList(growable: false),
    picked.length > kDailyTaskCount ? picked[kDailyTaskCount] : null,
  );
  _dayCache[cacheKey] = result;
  return result;
}

/// Три основных задания на день для конкретной пары.
List<DailyTask> dailyTasksFor({required DateTime day, required String pairId}) =>
    dailyTaskDayFor(day: day, pairId: pairId).main;

/// Какое задание закрывает только что созданный пин.
///
/// Возвращает id закрытого задания или null: пин чужого типа и повторный пин
/// уже закрытого задания монету не приносят.
///
/// [fromTaskId] — задание, из которого человек пришёл в форму. Оно главнее
/// типа: форма сама решает, чем считать запись (текст плюс фотография — это
/// уже `photo`), и без этой связи ответ на «Чем ты восхищаешься в {p}?» с
/// приложенным снимком не закрывал ничего. Так у пары tepngitgvren2b9 19
/// августа 2026 текстовое задание осталось пустым при написанном ответе, а
/// жалоба звучала как «текстовые задания не отмечаются».
String? closeByMemory({
  required List<DailyTask> tasks,
  required Set<String> alreadyDone,
  required MemoryType type,
  String? fromTaskId,
}) {
  if (fromTaskId != null) {
    for (final task in tasks) {
      if (task.id != fromTaskId) continue;
      // Закрытое задание уступает обычному правилу: второй пин из той же
      // строки пусть закроет задание своего типа, если такое ещё открыто.
      if (!alreadyDone.contains(task.id)) return task.id;
      break;
    }
  }
  for (final task in tasks) {
    if (task.type == type && !alreadyDone.contains(task.id)) return task.id;
  }
  return null;
}

/// Текст задания, ответом на которое стала запись ленты.
///
/// Возвращает null, когда задания нет, id пустой или каталог его не знает:
/// каталог живёт в сборке, а запись переживает обновления, и подпись «ответ на
/// задание» без самого задания читалась бы поломкой.
String? dailyTaskTitleOf(String? taskId, String partnerName) {
  final id = (taskId ?? '').trim();
  if (id.isEmpty) return null;
  return DailyTask.byId(id)?.title(partnerName);
}

/// Что пара успела сегодня. Дата хранится строкой: прогресс живёт сутки и на
/// следующий день начинается с чистого листа.
class DailyTaskProgress {
  const DailyTaskProgress({required this.date, required this.done});

  const DailyTaskProgress.empty() : date = '', done = const {};

  final String date;
  final Set<String> done;

  static String dayKey(DateTime day) =>
      day.toUtc().toIso8601String().substring(0, 10);

  Set<String> doneOn(DateTime day) => date == dayKey(day) ? done : const {};

  DailyTaskProgress withDone(String id, DateTime day) {
    final key = dayKey(day);
    return DailyTaskProgress(
      date: key,
      done: date == key ? {...done, id} : {id},
    );
  }

  factory DailyTaskProgress.fromMap(Map<String, dynamic> map) =>
      DailyTaskProgress(
        date: (map['date'] ?? '').toString(),
        done: {
          for (final v in (map['done'] as List? ?? const [])) v.toString(),
        },
      );

  Map<String, dynamic> toMap() => {'date': date, 'done': done.toList()};
}
