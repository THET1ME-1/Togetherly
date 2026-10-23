part of 'locale_service.dart';

/// Три формы числа, как в русском: 1 день, 2 дні, 5 днів. 11…14 всегда
/// берут форму «много».
String _ukPlural(int n, String one, String few, String many) {
  final abs = n.abs();
  final tens = abs % 100;
  if (tens >= 11 && tens <= 14) return many;
  switch (abs % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}

/// Украинский: то, что словарём не выражается.
///
/// Простые строки берутся из `kStrings` по коду `uk` (колонка в
/// `lib/l10n/uk/`). Здесь подстановки, числа и даты. Месяц внутри даты стоит
/// в родительном («8 березня»), как в русском. Там, где русская строка
/// держит род («приболел(а)», «подарил»), фраза перестроена без рода.
class _UkStrings extends _EnStrings {
  const _UkStrings() : super('uk');

  static String _days(int n) => _ukPlural(n, 'день', 'дні', 'днів');

  /// «за 1 монету», «за 3 монети», «за 30 монет».
  static String _coinsAcc(int n) => _ukPlural(n, 'монету', 'монети', 'монет');

  static const List<String> _monthsNom = [
    'Січень',
    'Лютий',
    'Березень',
    'Квітень',
    'Травень',
    'Червень',
    'Липень',
    'Серпень',
    'Вересень',
    'Жовтень',
    'Листопад',
    'Грудень',
  ];

  static const List<String> _monthsGen = [
    'січня',
    'лютого',
    'березня',
    'квітня',
    'травня',
    'червня',
    'липня',
    'серпня',
    'вересня',
    'жовтня',
    'листопада',
    'грудня',
  ];

  static const List<String> _monthsShort = [
    'січ',
    'лют',
    'бер',
    'кві',
    'тра',
    'чер',
    'лип',
    'сер',
    'вер',
    'жов',
    'лис',
    'гру',
  ];

  static const List<String> _weekShort = [
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Нд',
  ];

  static const List<String> _weekLong = [
    'Понеділок',
    'Вівторок',
    'Середа',
    'Четвер',
    'П’ятниця',
    'Субота',
    'Неділя',
  ];

  // ── Вход и регистрация ──
  @override
  String loginError(String e) => 'Помилка входу: $e';
  @override
  String googleLoginError(String e) => 'Помилка входу через Google: $e';
  @override
  String registrationError(String e) => 'Помилка реєстрації: $e';
  @override
  String passwordResetSent(String email) =>
      'Лист для скидання пароля надіслано на $email. '
      'Перевірте пошту й папку «Спам».';

  // ── Главная ──
  @override
  String daysLabel(String suffix) => 'ДНІВ $suffix';
  @override
  String monthsLabel(String suffix) => 'МІСЯЦІВ $suffix';
  @override
  String timeLabel(String suffix) => 'ЧАС $suffix';
  @override
  String partnerIsMood(String name, String mood) => '$name — $mood';
  @override
  String moodPackAuthor(String name) => 'Малюнки — $name';
  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name нездужає: $label';
  @override
  String moodDateLabel(String dateLabel) => 'Настрій — $dateLabel';
  @override
  String achProgressOf(int value, int target) => '$value з $target';
  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      'Відкрито $unlocked з $total';
  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'відкриється сьогодні' : 'через $days дн.';
  @override
  String capsuleOpensOn(String date) => 'Відкриється $date';
  @override
  String capsuleNotReady(String date) => 'Ще зарано. Відкриється $date';
  @override
  String capsuleOpenedBodyNamed(String title) =>
      '«$title» чекає на тебе в стрічці';

  // ── Виджеты ──
  @override
  String widgetOfPartner(String name) => 'Віджет $name';

  // ── Профиль ──
  @override
  String daysTogetherLabel(String days) {
    final n = int.tryParse(days.replaceAll(RegExp(r'\D'), ''));
    return '$days ${n == null ? 'днів' : _days(n)}';
  }

  @override
  String premiumThemeLocked(int price) =>
      'Преміум-тема за $price ${_coinsAcc(price)} — відкрий у магазині';
  @override
  String buyThemeDescription(String themeName, int price) =>
      'Розблокувати тему «$themeName» за $price ${_coinsAcc(price)}?';
  @override
  String coinPackTitle(int coins) =>
      '$coins ${_ukPlural(coins, 'монета', 'монети', 'монет')}';
  @override
  String coinPurchaseSuccessAmount(int coins) =>
      '+$coins ${_coinsAcc(coins)} зараховано';
  @override
  String coinEarned(int amount) => '+$amount ${_coinsAcc(amount)} отримано!';
  @override
  String uploadError(String e) => 'Помилка завантаження: $e';

  // ── Календарь настроений ──
  @override
  String partnerMood(String name) => 'Настрої $name';

  // ── Рисование ──
  @override
  String drawingSavedTo(String path) => 'Малюнок збережено: $path';
  @override
  String partnerIsDrawing(String name) => '$name малює…';
  @override
  List<String> get reflectionQuestions => const [
    'Яка дрібниця, зроблена партнером сьогодні, дала вам відчути, що вас цінують?',
    'Який момент із партнером змусив вас усміхнутися сьогодні?',
    'Чим ви захоплюєтеся в партнері просто зараз?',
    'За що у ваших стосунках ви вдячні сьогодні?',
    'Який спогад із партнером ви згадуєте знову й знову?',
    'Чим партнер здивував вас останнім часом?',
    'Що робить вашого партнера особливим для вас?',
    'Як партнер підтримав вас сьогодні?',
    'Що ви хочете, щоб партнер дізнався сьогодні?',
    'У яку пригоду ви хотіли б вирушити разом?',
    'Яка пісня нагадує вам про партнера і чому?',
    'Що найкраще в тому, щоб бути разом?',
    'Який маленький добрий вчинок партнера важив найбільше?',
    'Що нового ви дізналися про партнера?',
    'Яка у вас спільна мета?',
    'Що вам подобається робити разом?',
    'Коли ви востаннє відчували справжній зв’язок із партнером?',
    'Що зробить завтрашній день особливим для обох?',
    'Який комплімент ви хочете зробити партнеру сьогодні?',
    'Яка звичка партнера вам потай подобається?',
  ];

  // ── Подключение ──
  @override
  String groupOf(int count) => 'Група з $count';
  @override
  String membersCount(int count) => 'УЧАСНИКИ · $count';
  @override
  String shareInviteText(String code, String link) =>
      'Приєднуйся до мене в Togetherly! Використай код: $code\n\nАбо натисни: $link';
  @override
  String onboardingLeft(int left) => left == 1
      ? 'Залишився один крок'
      : 'Залишилося $left ${_ukPlural(left, 'крок', 'кроки', 'кроків')}';
  @override
  String onboardingNext(String step) => 'Залишився крок: $step';

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Фотографія',
    'video' => 'Відео',
    'location' => 'Локація',
    'music' => 'Музика',
    'text' => 'Нотатка',
    'videoLink' => 'Відео за посиланням',
    'book' => 'Книга',
    _ => 'Кіно',
  };
  @override
  String timerDaysCount(int days) => '$days ${_days(days)}';
  @override
  String symbolSearchFound(int count) => 'Знайдено: $count';

  @override
  String quietPartnerTitle(String name, int days) =>
      '$name не заходить $days ${_days(days)}';

  @override
  String membersOfMax(int current, int max) => '$current/$max учасників';
  @override
  String shareGroupInviteText(String code, String link) =>
      'Приєднуйся до нашої групи в Togetherly! Використай код: $code\n\nАбо натисни: $link';
  @override
  String connectedWithCouple(String name) => 'Ви з $name тепер разом!';
  @override
  String marriedTo(String name) => 'Ви з $name одружені! 💍';
  @override
  String friendsWith(String name) => 'Ви з $name тепер друзі!';
  @override
  String buddiesWith(String name) => 'Ви з $name тепер найкращі друзі!';
  @override
  String customRelWith(String label, String name) =>
      'Ви з $name тепер $label!';
  @override
  String joinMeLinkText(String link) =>
      'Приєднуйся до мене в Togetherly! $link';
  @override
  String membersCountBracket(int count) => 'УЧАСНИКИ ($count)';

  // ── Даты ──
  @override
  List<String> get shortMonths => _monthsShort;
  @override
  List<String> get shortWeekdays => _weekShort;

  // ── Скучаю ──
  @override
  String missYouNotifTitle(String name) => '$name сумує за вами';
  @override
  String missYouStreak(int count) => '🔥 $count';
  @override
  String thinkingOfYouNotifTitle(String name) => '$name думає про тебе 💭';
  @override
  String wantHugNotifTitle(String name) => '$name хоче тебе обійняти 🤗';
  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карточка фото ──
  @override
  String kmFromYou(String km) => '$km від вас';
  @override
  String minutesAgo(int m) => '$m хв тому';
  @override
  String hoursAgo(int h) => '$h год тому';
  @override
  String daysAgo(int d) => '$d дн. тому';

  // ── Лента воспоминаний ──
  @override
  String newMemory(String type) => 'Нове: $type';
  @override
  String failedAddMemory(String e) => 'Не вдалося додати: $e';
  @override
  String savedToPath(String path) => 'Збережено: $path';
  @override
  String downloadFailed(String e) => 'Помилка завантаження: $e';
  @override
  String failedSelectPhotos(String e) => 'Не вдалося вибрати фото: $e';
  @override
  String failedSelectVideo(String e) => 'Не вдалося вибрати відео: $e';
  @override
  String nPhotos(int count) => '$count фото';
  @override
  String openIn(String name) => 'Відкрити в $name';
  @override
  List<String> get fullMonths => const ['', ..._monthsNom];
  @override
  String formatDateAt(String month, int day, int year, String time) {
    final i = _monthsNom.indexOf(month);
    final m = i < 0 ? month.toLowerCase() : _monthsGen[i];
    return '$day $m $year о $time';
  }

  // ── Статус отношений ──
  @override
  String statusSetTo(String status) => 'Статус: $status';
  @override
  String failedSetStatus(String e) => 'Помилка встановлення статусу: $e';
  @override
  String failedClearStatus(String e) => 'Помилка очищення статусу: $e';
  @override
  String failedAddStatus(String e) => 'Помилка додавання статусу: $e';
  @override
  String failedUpdateStatus(String e) => 'Помилка оновлення статусу: $e';
  @override
  String deleteStatusConfirm(String label) =>
      'Ви впевнені, що хочете видалити «$label»?';
  @override
  String failedDeleteStatus(String e) => 'Помилка видалення статусу: $e';

  // ── Календарь настроений ──
  @override
  String moodRecorded(String label) => '$label записано!';
  @override
  List<String> get shortWeekdaysSingleChar => const [
    'П',
    'В',
    'С',
    'Ч',
    'П',
    'С',
    'Н',
  ];
  @override
  List<String> get longWeekdays => _weekLong;

  // ── Таймеры ──
  @override
  String timerDeleteConfirm(String name) => '«$name» буде видалено назавжди.';

  // ── Виджеты (продолжение) ──
  @override
  String failedAddWidget(String e) => 'Не вдалося додати віджет: $e';
  @override
  String yearsAlready(int years) =>
      '$years ${_ukPlural(years, 'рік', 'роки', 'років')} уже ❤️';
  @override
  String monthsAlready(int months) =>
      '$months ${_ukPlural(months, 'місяць', 'місяці', 'місяців')} уже ❤️';
  @override
  String widgetSlotTitle(int index) => 'Віджет ${index + 1}';

  // ── Профиль (продолжение) ──
  @override
  String get cycleConsentBody =>
      'Дати циклу й самопочуття — це дані про здоров’я, тому питаємо окремо. '
      'Вони зберігаються на нашому сервері, партнер бачить їх, лише якщо ви '
      'самі це ввімкнете, і видаляються одним дотиком. Згоду можна відкликати '
      'в налаштуваннях, позначки зітруться разом із нею.';
  @override
  String get cycleConsentAgree => 'Погоджуюсь, вести цикл';
  @override
  String get cycleConsentLater => 'Не зараз';
  @override
  String get cycleConsentWithdraw => 'Відкликати згоду на цикл';
  @override
  String get cycleConsentWithdrawHint => 'Розділ закриється, позначки зітруться';
  @override
  String get exportMyData => 'Мої дані';
  @override
  String get exportMyDataHint => 'Завантажити архів з усім, що ми зберігаємо';
  @override
  String get exportMyDataReady => 'Архів готовий';
  @override
  String get exportMyDataFailed => 'Не вдалося зібрати архів';
  @override
  String get exportMemories => 'Експорт спогадів';
  @override
  String exportError(String e) => 'Помилка під час експорту: $e';

  // ── Мини-календарь ──
  @override
  List<String> get shortWeekdaysUpper => const [
    'ПН',
    'ВТ',
    'СР',
    'ЧТ',
    'ПТ',
    'СБ',
    'НД',
  ];

  // ── Уведомления ──
  @override
  String daysTogetherNotifBody(int days) =>
      'Ви разом уже $days ${_days(days)} ❤️';

  // ── Чат ──
  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return '$n ${_days(n)}';
  }

  @override
  String chatReplyingTo(String name) => 'У відповідь $name';
  @override
  String chatTyping(String name) => '$name друкує…';
  @override
  String chatNotifTitle(String name) => '$name пише вам 💬';
  @override
  String moodNotifTitle(String name) => 'Новий настрій у $name';
  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Сьогодні';
    if (diff == 1) return 'Учора';
    final base = '${day.day} ${_monthsGen[day.month - 1]}';
    return day.year == now.year ? base : '$base ${day.year}';
  }

  @override
  String chatDeleteConfirm(String text) => 'Видалити це повідомлення?';
  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells ${_ukPlural(cells, 'клітинка', 'клітинки', 'клітинок')} · '
      'піксель $px px у вивантаженні';
  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count ${_ukPlural(count, 'малюнок', 'малюнки', 'малюнків')} · '
      'останній $lastDate';
  @override
  String tgDaysTogetherCaption(int days) => '${_days(days)} разом';
  @override
  String tgMonthsCaption(int months) =>
      _ukPlural(months, 'місяць', 'місяці', 'місяців');
  @override
  String tgDaysMilestone(int days) => '$days ${_days(days)}';
  @override
  String tgYearsMilestone(int years) =>
      '$years ${_ukPlural(years, 'рік', 'роки', 'років')}';
  @override
  String tgInDays(int days) => 'через $days ${_days(days)}';
  @override
  String tgUntilMilestone(int target, int left) =>
      'До ${tgDaysMilestone(target)} — ${tgInDays(left)}';
  @override
  String tgMissAddressee(String name) => name;
  @override
  String tgMoodMatched(int days) => 'збіглося $days із 7';
  @override
  String tgCountdownDaysLeft(int days) => '${_days(days)} до зустрічі';
  @override
  String tgYearDaysWord(int days) => _ukPlural(days, 'День', 'Дні', 'Днів');
  @override
  String tgYearDaysUnit(int days) => _days(days);
  @override
  String tgYearDaysTogether(int days) =>
      '${_ukPlural(days, 'День', 'Дні', 'Днів')} разом';
  @override
  String tgYearDaysLeft(int days) => 'Ще $days ${_days(days)}';
  @override
  String tgYearToAnniversary(int year) =>
      'До $year ${_ukPlural(year, 'року', 'років', 'років')}';
  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'До $year ${_ukPlural(year, 'року', 'років', 'років')} — $days';
  @override
  String tgYearCurrentYearShort(int year, int days) =>
      '$year-й рік · ще $days';
  @override
  String tgYearOrdinalLabel(int year) {
    const words = [
      'ПЕРШИЙ',
      'ДРУГИЙ',
      'ТРЕТІЙ',
      'ЧЕТВЕРТИЙ',
      'П’ЯТИЙ',
      'ШОСТИЙ',
      'СЬОМИЙ',
      'ВОСЬМИЙ',
      'ДЕВ’ЯТИЙ',
      'ДЕСЯТИЙ',
    ];
    final word =
        year >= 1 && year <= words.length ? words[year - 1] : '$year-Й';
    return '$word РІК РАЗОМ';
  }

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${_ukPlural(years, 'РІК', 'РОКИ', 'РОКІВ')} '
      '$days ${_ukPlural(days, 'ДЕНЬ', 'ДНІ', 'ДНІВ')}';
  @override
  String tgYearSince(String date) => 'З $date';
  @override
  String mascotSleepRange(String from, String to) => 'Спить із $from до $to';
  @override
  String mascotNightRange(String from, String to) =>
      'Світить із $from до $to';

  @override
  String cycleOf(String name) => 'Цикл $name';
  @override
  String cycleDaysLeft(int days) => 'Через ${_days(days)}';
  @override
  String cycleDayOfCycle(int day) => '$day-й день циклу';
  @override
  String cycleOverdue(int days) => 'Затримка ${_days(days)}';
  @override
  String cycleAnalyticsHint(int cycles) =>
      'за ${_ukPlural(cycles, 'останнім циклом', 'останніми циклами', 'останніми циклами')}';
  @override
  String cycleDaysValue(int days) => '$days ${_days(days)}';
  @override
  List<String> get cycleWeekdayShorts => const [
    'пн',
    'вт',
    'ср',
    'чт',
    'пт',
    'сб',
    'нд',
  ];
  @override
  List<String> get cycleMonthNames => _monthsNom;
  @override
  List<String> get cycleMonthsGenitive => _monthsGen;
  @override
  String dayLogDate(DateTime day) => '${day.day} ${_monthsGen[day.month - 1]}';
  @override
  String dayLogWeekday(DateTime day) =>
      _weekLong[day.weekday - 1].toLowerCase();
  @override
  String cyclePeriodDayLabel(int day) => 'місячні, $day-й день';
  @override
  String drawLayerName(int index) => 'Шар $index';
  @override
  String drawLayerStrokes(int count) => count == 0
      ? 'порожньо'
      : '$count ${_ukPlural(count, 'штрих', 'штрихи', 'штрихів')}';
  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Чистий',
    'grid' => 'Клітинка',
    'dots' => 'Крапки',
    'notebook' => 'Зошит',
    'millimeter' => 'Міліметрівка',
    'kraft' => 'Крафт',
    'chalkboard' => 'Дошка',
    'music' => 'Ноти',
    'stars' => 'Зірки',
    'hearts' => 'Сердечка',
    'watercolor' => 'Акварель',
    'film' => 'Плівка',
    _ => id,
  };
  @override
  String memoryFileTooBig(int limitMb) =>
      'Файл важчий за $limitMb МБ — такий не завантажиться';
  @override
  String pcReceiptShift(int days) => 'зміна №$days';
  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Спогадів — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Малюнків — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('«Я сумую» — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Днів поспіль — ${stats.streak}');
    if (lines.isEmpty) lines.add('Усе тільки починається — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'Від кого: ${from.isEmpty ? 'мене' : from}\n'
      'Вміст: $days ${_days(days)}, усе ціле';
  @override
  String statsMoodMarks(int n) => 'Позначок за 30 днів: $n';
  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'Файл важчий за $limitMb МБ. З Togetherly+ стеля вдвічі вища';
  @override
  String selectedCount(int n) => 'Вибрано $n';
  @override
  String deleteCanvasesTitle(int n) => n == 1
      ? 'Видалити полотно?'
      : 'Видалити $n ${_ukPlural(n, 'полотно', 'полотна', 'полотен')}?';
  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'Малюнок зникне в обох. Повернути його буде неможливо.'
      : 'Малюнки зникнуть в обох. Повернути їх буде неможливо.';
  @override
  String chatBgConfirmBody(int price) =>
      'Поставити своє фото на фон чату за $price 🪙?\n\n'
      'Кожна наступна зміна фону теж коштує $price 🪙.';
  @override
  String captionDestPairWidgetSub(String partner) =>
      'Фото в «Моєму віджеті» — видно тобі й $partner';
  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Окремий віджет із фото для $partner';
  @override
  String streakLabel(int days) => 'Серія: $days ${_days(days)}';

  // ── Виджеты (фото) ──
  @override
  String unlockForCoins(int price) => 'Розблокувати — $price 🪙';
  @override
  String notEnoughCoinsNeed(int price) =>
      'Недостатньо монет — потрібно $price 🪙';
  @override
  String personalPhotosHelp(String partner) =>
      'Особисті фото — від 1 до 10 на кожен віджет. Із двох фото вмикається '
      'карусель: зміна під час розблокування або за таймером.\n\nЦі фото бачиш '
      'лише ти. Щоб поділитися з $partner, відкрий «Фото партнера» → '
      '«Обрати фото для партнера».';
  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Цей віджет показує фото, якими ділиться $partner '
      '($count ${photosUnit(count)}). Змінювати їх може лише $partner.';
  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner ще не ділиться фото. Щоб вони тут з’явилися, $partner '
      'потрібно відкрити «Фото партнера» і натиснути «Обрати фото для '
      'партнера» — звичайний «Фото-віджет» бачить лише власник.';
  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner бачить ваші фото: $count';
  @override
  String photosUnit(int n) => 'фото';
  @override
  String photoCountOnUnlock(int count) => '$count фото · під час розблокування';
  @override
  String photoCountInterval(int count, String interval) =>
      '$count фото · $interval';
  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'кожні 15 хв';
      case 30:
        return 'кожні 30 хв';
      case 60:
        return 'щогодини';
      case 180:
        return 'кожні 3 години';
      default:
        return 'кожні $minutes хв';
    }
  }

  @override
  String partnerSharedCountHelp(int count) =>
      'Від партнера $count фото — оберіть, як вони змінюватимуться на цьому '
      'віджеті.';

  // ── Галерея маскотов ──
  @override
  String mascotDeactivated(String name) => '$name вимкнено';
  @override
  String mascotActivated(String name) => '$name тепер активний';
  @override
  String deleteMascotBody(String name) => '«$name» буде видалено назавжди.';
  @override
  String recordStreakDays(int days) => 'Рекорд: $days дн.';
  @override
  String mascotsCount(int count, int max) => '$count / $max маскотів';
  @override
  String recordStreakBadge(int days) => '$days дн.';

  // ── Рисование маскота, раскраска ──
  @override
  String genericError(String e) => 'Помилка: $e';
  @override
  String coloringPartnerColoring(String name) => '$name розфарбовує';
  @override
  String coloringWaitingHint(String name) =>
      'відкриємо, щойно $name натисне «Готово»';

  // ── Карусель фото ──
  @override
  String photoCountCarousel(int count) => '$count фото · карусель';
  @override
  String photoNumber(int n) => 'Фото $n';
  @override
  String positionNumber(int n) => 'Позиція $n';

  // ── Профиль, «Смотрим», ленты ──
  @override
  String yearRange(int first, int last) => 'Рік від $first до $last';
  @override
  String kpRating(String rating) => 'КП $rating';
  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} м'
      : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} км';
  @override
  String watchWithPartner(String name) => 'Дивитися з $name';
  @override
  String watchVideoAdd(int mb) => 'Додати відео\nдо $mb МБ';
  @override
  String watchVideoTooBig(int mb) =>
      'Відео більше за $mb МБ: стисніть його або оберіть коротше';
  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName кличе дивитися разом';
  @override
  String selectUpToPhotos(int n) => 'Оберіть до $n фото';
  @override
  String addWithCount(int n) => 'Додати ($n)';
  @override
  String failedToSave(Object e) => 'Не вдалося зберегти: $e';
  @override
  String itemsShort(int n) => '$n елем.';
  @override
  String coinsPlus(int n) =>
      '+$n ${_ukPlural(n, 'монета', 'монети', 'монет')}';
  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score з $max';
  @override
  List<String> get monthAbbrev => _monthsShort;
  @override
  String memoriesUnit(int n) =>
      _ukPlural(n, 'спогад', 'спогади', 'спогадів');

  // ── Карта ──
  @override
  String liveLocationAgo(String value) => '$value тому';

  // ── Получение подарка ──
  @override
  String giftFromPartner(String name) => 'Подарунок від $name';
  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? 'Вислизнув!' : 'Знову вислизнув, лови!';
  @override
  String giftIncomingCount(int n) =>
      n == 1 ? 'чекає на тебе' : 'чекають на тебе: $n';
  @override
  String giftMutualBonus(int coins) => 'Встигли вчасно: обом по $coins';
  @override
  String giftSunriseGreeting(String name) =>
      'Доброго ранку! $name дарує тобі світанок';
  @override
  String supportCopied(String email) => 'Пошту скопійовано: $email';
  @override
  String redeemCodeDone(int coins) =>
      'Зараховано $coins ${_coinsAcc(coins)}';

  // ── Профиль партнёра ──
  @override
  String partnerGiftsChip(int count) => '$count';
  @override
  String partnerMissChip(int count) => '$count';
  @override
  String partnerDaysTogether(int days) => 'разом $days ${_days(days)}';
  @override
  String partnerMissPeak(String weekday) => 'Найчастіше — $weekday';
  @override
  String weekdayShort(int weekday) => _weekShort[weekday - 1];
  @override
  String weekdayLong(int weekday) => const [
    'по понеділках',
    'по вівторках',
    'по середах',
    'по четвергах',
    'по п’ятницях',
    'по суботах',
    'по неділях',
  ][weekday - 1];

  // ── Подарки ──
  @override
  String giftPushBody(String giftName) => 'Тобі подарунок: $giftName';
}
