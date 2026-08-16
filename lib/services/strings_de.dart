part of 'locale_service.dart';

/// Немецкий: то, что словарём не выражается.
///
/// Простые строки этот класс берёт из `kStrings` по коду `de` — они лежат в
/// `lib/l10n/dict/`. Здесь остаётся ровно то, что требует кода: подстановки,
/// числительные (1 Tag против 2 Tage) и списки месяцев с днями недели.
///
/// Родитель — английская реализация: если новый метод забудут перевести, немец
/// увидит английскую фразу, а не пустоту или падение.
class _DeStrings extends _EnStrings {
  const _DeStrings() : super('de');

  // ── Списки дат ──────────────────────────────────────────────────────────
  // Календарь и лист дня рисуются по ним, поэтому английские месяцы посреди
  // немецкого интерфейса видно сразу.

  @override
  List<String> get shortMonths => const [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  @override
  List<String> get monthAbbrev => shortMonths;

  @override
  List<String> get cycleMonthsGenitive => shortMonths;

  /// Первый элемент пустой: индексация идёт по номеру месяца (1–12).
  @override
  List<String> get fullMonths => const [
    '',
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  @override
  List<String> get cycleMonthNames => const [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  @override
  List<String> get shortWeekdays => const [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  @override
  List<String> get cycleWeekdayShorts => shortWeekdays;

  @override
  List<String> get shortWeekdaysUpper => const [
    'MO',
    'DI',
    'MI',
    'DO',
    'FR',
    'SA',
    'SO',
  ];

  /// Мittwoch и Montag начинаются одинаково, поэтому среда помечена буквой M
  /// так же, как понедельник: в узкой сетке календаря места на два знака нет.
  @override
  List<String> get shortWeekdaysSingleChar => const [
    'M',
    'D',
    'M',
    'D',
    'F',
    'S',
    'S',
  ];

  @override
  List<String> get longWeekdays => const [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  @override
  List<String> get reflectionQuestions => const [
    'Was hat dein Partner heute getan, das dir gutgetan hat?',
    'Welcher Moment mit deinem Partner hat dich heute zum Lächeln gebracht?',
    'Was bewunderst du gerade an deinem Partner?',
    'Wofür bist du in deiner Beziehung heute dankbar?',
    'An welche Erinnerung mit deinem Partner denkst du immer wieder?',
    'Womit hat dein Partner dich in letzter Zeit überrascht?',
    'Was macht deinen Partner für dich besonders?',
    'Wie hat dein Partner dich heute unterstützt?',
    'Was möchtest du deinem Partner heute sagen?',
    'Welches Abenteuer würdest du gern mit deinem Partner erleben?',
    'Welches Lied erinnert dich an deinen Partner und warum?',
    'Was ist das Schönste daran, mit deinem Partner zusammen zu sein?',
    'Welche kleine Aufmerksamkeit deines Partners hat dir zuletzt am meisten bedeutet?',
    'Was hast du neu über deinen Partner gelernt?',
    'Wovor hast du Angst, wenn du an eure Zukunft denkst?',
    'Was möchtest du in den nächsten Monaten gemeinsam schaffen?',
    'Wann hast du dich zuletzt richtig verstanden gefühlt?',
    'Was fehlt dir gerade, worüber ihr noch nicht gesprochen habt?',
    'Welche Gewohnheit deines Partners magst du besonders?',
    'Was würdest du eurem ersten gemeinsamen Tag heute erzählen?',
  ];

  // ── Ошибки и вход ───────────────────────────────────────────────────────

  @override
  String loginError(String e) => 'Anmeldefehler: $e';

  @override
  String googleLoginError(String e) => 'Fehler bei der Google-Anmeldung: $e';

  @override
  String registrationError(String e) => 'Fehler bei der Registrierung: $e';

  @override
  String passwordResetSent(String email) =>
      'Wir haben eine E-Mail zum Zurücksetzen an $email geschickt. '
      'Schau auch im Spam-Ordner nach.';

  @override
  String genericError(String e) => 'Fehler: $e';

  @override
  String uploadError(String e) => 'Fehler beim Hochladen: $e';

  @override
  String failedToSave(Object e) => 'Speichern fehlgeschlagen: $e';

  @override
  String exportError(String e) => 'Fehler beim Export: $e';

  @override
  String downloadFailed(String e) => 'Herunterladen fehlgeschlagen: $e';

  @override
  String failedSelectPhotos(String e) =>
      'Die Fotos konnten nicht gewählt werden: $e';

  @override
  String failedSelectVideo(String e) =>
      'Das Video konnte nicht gewählt werden: $e';

  @override
  String failedAddMemory(String e) =>
      'Die Erinnerung konnte nicht hinzugefügt werden: $e';

  @override
  String failedAddWidget(String e) =>
      'Das Widget konnte nicht hinzugefügt werden: $e';

  @override
  String failedSetStatus(String e) =>
      'Der Status konnte nicht gesetzt werden: $e';

  @override
  String failedClearStatus(String e) =>
      'Der Status konnte nicht entfernt werden: $e';

  @override
  String failedAddStatus(String e) =>
      'Der Status konnte nicht hinzugefügt werden: $e';

  @override
  String failedUpdateStatus(String e) =>
      'Der Status konnte nicht geändert werden: $e';

  @override
  String failedDeleteStatus(String e) =>
      'Der Status konnte nicht gelöscht werden: $e';

  // ── Главная, таймеры, счётчики ──────────────────────────────────────────

  @override
  String daysLabel(String suffix) => 'TAGE $suffix';

  @override
  String monthsLabel(String suffix) => 'MONATE $suffix';

  @override
  String timeLabel(String suffix) => 'ZEIT $suffix';

  @override
  String daysTogetherLabel(String days) => '$days Tage';

  @override
  String yearsAlready(int years) =>
      years == 1 ? 'Schon ein Jahr ❤️' : 'Schon $years Jahre ❤️';

  @override
  String monthsAlready(int months) =>
      months == 1 ? 'Schon ein Monat ❤️' : 'Schon $months Monate ❤️';

  @override
  String timerDaysCount(int days) => days == 1 ? '1 Tag' : '$days Tage';

  @override
  String timerDeleteConfirm(String name) => '„$name“ ist dann für immer weg.';

  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';

  @override
  String daysTogetherNotifBody(int days) =>
      'Ihr seid schon $days ${days == 1 ? 'Tag' : 'Tage'} zusammen ❤️';

  @override
  String streakLabel(int days) => 'Serie: $days ${days == 1 ? 'Tag' : 'Tage'}';

  @override
  String recordStreakDays(int days) => 'Rekord: $days T.';

  @override
  String recordStreakBadge(int days) => '$days T.';

  // ── Настроение и самочувствие ───────────────────────────────────────────

  @override
  String partnerIsMood(String name, String mood) => '$name ist $mood';

  @override
  String partnerMood(String name) => 'Stimmung von $name';

  @override
  String moodDateLabel(String dateLabel) => 'Stimmung — $dateLabel';

  @override
  String moodRecorded(String label) => '$label eingetragen!';

  @override
  String moodPackAuthor(String name) => 'Bilder von $name';

  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name geht es nicht gut: $label';

  @override
  String moodNotifTitle(String name) => '$name hat die Stimmung geändert';

  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score von $max';

  @override
  String statsMoodMarks(int n) => 'Einträge in 30 Tagen: $n';

  // ── Достижения и капсула ────────────────────────────────────────────────

  @override
  String achProgressOf(int value, int target) => '$value von $target';

  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      '$unlocked von $total erhalten';

  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'öffnet heute' : 'in $days ${days == 1 ? 'Tag' : 'Tagen'}';

  @override
  String capsuleOpensOn(String date) => 'Öffnet am $date';

  @override
  String capsuleFrom(String name) => 'von $name';

  @override
  String capsuleNotReady(String date) => 'Noch nicht 🙈 Öffnet am $date';

  @override
  String capsuleOpenedBodyNamed(String title) =>
      '„$title“ wartet in deinem Pfad';

  // ── Монеты, покупки, Togetherly+ ────────────────────────────────────────

  @override
  String premiumThemeLocked(int price) =>
      'Bezahltes Thema — $price Münzen, im Münzladen freischalten';

  @override
  String buyThemeDescription(String themeName, int price) =>
      'Das Thema „$themeName“ für $price Münzen freischalten?';

  @override
  String coinPackTitle(int coins) => '$coins Münzen';

  @override
  String coinPurchaseSuccessAmount(int coins) =>
      '+$coins Münzen gutgeschrieben';

  @override
  String coinEarned(int amount) => '+$amount Münzen verdient!';

  @override
  String coinsPlus(int n) => '+$n ${n == 1 ? 'Münze' : 'Münzen'}';

  @override
  String unlockForCoins(int price) => 'Freischalten — $price 🪙';

  @override
  String notEnoughCoinsNeed(int price) =>
      'Nicht genug Münzen — du brauchst $price 🪙';

  @override
  String redeemCodeDone(int coins) => '$coins Münzen gutgeschrieben';

  @override
  String supportCopied(String email) => 'Adresse kopiert: $email';

  // ── Группа, приглашения, связь ──────────────────────────────────────────

  @override
  String groupOf(int count) => 'Gruppe mit $count';

  @override
  String membersCount(int count) => 'MITGLIEDER · $count';

  @override
  String membersCountBracket(int count) => 'MITGLIEDER ($count)';

  @override
  String membersOfMax(int current, int max) => '$current/$max Mitglieder';

  @override
  String shareInviteText(String code, String link) =>
      'Komm zu mir auf Togetherly! Code: $code\n\nOder hier klicken: $link';

  @override
  String shareGroupInviteText(String code, String link) =>
      'Komm in unsere Gruppe auf Togetherly! Code: $code\n\n'
      'Oder hier klicken: $link';

  @override
  String joinMeLinkText(String link) => 'Komm zu mir auf Togetherly! $link';

  @override
  String connectedWithCouple(String name) => 'Du bist mit $name verbunden!';

  @override
  String marriedTo(String name) => 'Du bist mit $name verheiratet! 💍';

  @override
  String friendsWith(String name) => 'Du bist jetzt mit $name befreundet!';

  @override
  String buddiesWith(String name) => '$name und du seid jetzt beste Freunde!';

  @override
  String customRelWith(String label, String name) =>
      'Du bist jetzt $label mit $name!';

  @override
  String onboardingLeft(int left) =>
      left == 1 ? 'Noch ein Schritt' : 'Noch $left Schritte';

  @override
  String onboardingNext(String step) => 'Noch ein Schritt: $step';

  @override
  String quietPartnerTitle(String name, int days) => days == 1
      ? '$name war einen Tag nicht da'
      : '$name war $days Tage nicht da';

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return n == 1 ? '1 Tag' : '$n Tage';
  }

  // ── Чат ─────────────────────────────────────────────────────────────────

  @override
  String chatReplyingTo(String name) => 'Antwort an $name';

  @override
  String chatTyping(String name) => '$name tippt…';

  @override
  String chatNotifTitle(String name) => '$name schreibt dir 💬';

  @override
  String chatDeleteConfirm(String text) => 'Diese Nachricht löschen?';

  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    final base = '${day.day}. ${cycleMonthNames[day.month - 1]}';
    return day.year == now.year ? base : '$base ${day.year}';
  }

  @override
  String chatBgConfirmBody(int price) =>
      'Dein Foto als Chat-Hintergrund für $price 🪙 setzen?\n\n'
      'Jeder weitere Wechsel kostet ebenfalls $price 🪙.';

  // ── Воспоминания и медиа ────────────────────────────────────────────────

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Foto',
    'video' => 'Video',
    'location' => 'Ort',
    'music' => 'Musik',
    'text' => 'Notiz',
    'videoLink' => 'Video-Link',
    'book' => 'Buch',
    _ => 'Film',
  };

  @override
  String newMemory(String type) => 'Neu: $type';

  @override
  String memoriesUnit(int n) => n == 1 ? 'Erinnerung' : 'Erinnerungen';

  @override
  String savedToPath(String path) => 'Gespeichert in $path';

  @override
  String nPhotos(int count) => '$count Fotos';

  @override
  String openIn(String name) => 'In $name öffnen';

  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '$day. $month $year um $time';

  @override
  String memoryFileTooBig(int limitMb) =>
      'Die Datei ist größer als $limitMb MB — sie lässt sich nicht laden';

  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'Die Datei ist größer als $limitMb MB. Togetherly+ verdoppelt das Limit';

  @override
  String selectedCount(int n) => '$n ausgewählt';

  @override
  String itemsShort(int n) => '$n Stück';

  @override
  String kpRating(String rating) => 'KP $rating';

  @override
  String yearRange(int first, int last) => 'Jahr von $first bis $last';

  // ── Статус и профиль ────────────────────────────────────────────────────

  @override
  String statusSetTo(String status) => 'Status gesetzt: $status';

  @override
  String deleteStatusConfirm(String label) => '„$label“ wirklich löschen?';

  @override
  String widgetOfPartner(String name) => 'Widget von $name';

  @override
  String symbolSearchFound(int count) => 'Gefunden: $count';

  // ── Уведомления «скучаю» и импульсы ─────────────────────────────────────

  @override
  String missYouNotifTitle(String name) => '$name vermisst dich';

  @override
  String missYouStreak(int count) => '🔥 $count';

  @override
  String thinkingOfYouNotifTitle(String name) => '$name denkt an dich 💭';

  @override
  String wantHugNotifTitle(String name) => '$name will dich umarmen 🤗';

  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карта и расстояния ──────────────────────────────────────────────────

  @override
  String kmFromYou(String km) => '$km von dir';

  @override
  String minutesAgo(int m) => 'vor $m Min';

  @override
  String hoursAgo(int h) => 'vor $h Std';

  @override
  String daysAgo(int d) => 'vor $d T';

  @override
  String liveLocationAgo(String value) => 'vor $value';

  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  // ── Рисование и холсты ──────────────────────────────────────────────────

  @override
  String partnerIsDrawing(String name) => '$name zeichnet…';

  @override
  String drawingSavedTo(String path) => 'Zeichnung gespeichert: $path';

  @override
  String drawLayerName(int index) => 'Ebene $index';

  @override
  String drawLayerStrokes(int count) =>
      count == 0 ? 'leer' : '$count ${count == 1 ? 'Strich' : 'Striche'}';

  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Glatt',
    'grid' => 'Raster',
    'dots' => 'Punkte',
    'notebook' => 'Notizbuch',
    'millimeter' => 'Millimeterpapier',
    'kraft' => 'Kraftpapier',
    'chalkboard' => 'Tafel',
    'music' => 'Notenblatt',
    'stars' => 'Sterne',
    'hearts' => 'Herzen',
    'watercolor' => 'Aquarell',
    'film' => 'Film',
    _ => id,
  };

  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count ${count == 1 ? 'Zeichnung' : 'Zeichnungen'} · zuletzt $lastDate';

  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells Kästchen · $px px pro Pixel beim Export';

  @override
  String deleteCanvasesTitle(int n) =>
      n == 1 ? 'Leinwand löschen?' : '$n Leinwände löschen?';

  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'Die Zeichnung verschwindet bei euch beiden. Das lässt sich nicht '
            'rückgängig machen.'
      : 'Die Zeichnungen verschwinden bei euch beiden. Das lässt sich nicht '
            'rückgängig machen.';

  @override
  String coloringPartnerColoring(String name) => '$name malt aus';

  @override
  String coloringWaitingHint(String name) =>
      'wir öffnen es, sobald $name auf Fertig tippt';

  // ── Виджеты ─────────────────────────────────────────────────────────────

  @override
  String tgDaysTogetherCaption(int days) =>
      days == 1 ? 'Tag zusammen' : 'Tage zusammen';

  @override
  String tgMonthsCaption(int months) => months == 1 ? 'Monat' : 'Monate';

  @override
  String tgDaysMilestone(int days) => '$days ${days == 1 ? 'Tag' : 'Tage'}';

  @override
  String tgYearsMilestone(int years) =>
      '$years ${years == 1 ? 'Jahr' : 'Jahre'}';

  @override
  String tgInDays(int days) => 'in $days ${days == 1 ? 'Tag' : 'Tagen'}';

  @override
  String tgUntilMilestone(int target, int left) =>
      'Bis ${tgDaysMilestone(target)} — ${tgInDays(left)}';

  @override
  String tgMissAddressee(String name) => 'An $name';

  @override
  String tgMoodMatched(int days) => '$days von 7 gleich';

  @override
  String tgCountdownDaysLeft(int days) =>
      '${days == 1 ? 'Tag' : 'Tage'} bis zum Wiedersehen';

  @override
  String tgYearDaysWord(int days) => days == 1 ? 'Tag' : 'Tage';

  @override
  String tgYearDaysTogether(int days) =>
      '${days == 1 ? 'Tag' : 'Tage'} zusammen';

  @override
  String tgYearDaysLeft(int days) =>
      '$days ${days == 1 ? 'Tag' : 'Tage'} übrig';

  @override
  String tgYearToAnniversary(int year) => 'Bis Jahr $year';

  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'Bis Jahr $year — $days';

  @override
  String tgYearCurrentYearShort(int year, int days) =>
      'Jahr $year · $days übrig';

  @override
  String tgYearOrdinalLabel(int year) => '$year. JAHR ZUSAMMEN';

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${years == 1 ? 'JAHR' : 'JAHRE'} '
      '$days ${days == 1 ? 'TAG' : 'TAGE'}';

  @override
  String tgYearSince(String date) => 'Seit $date';

  @override
  String photosUnit(int n) => n == 1 ? 'Foto' : 'Fotos';

  @override
  String photoCountOnUnlock(int count) => '$count Fotos · beim Entsperren';

  @override
  String photoCountInterval(int count, String interval) =>
      '$count Fotos · $interval';

  @override
  String photoCountCarousel(int count) => '$count Fotos · Karussell';

  @override
  String photoNumber(int n) => 'Foto $n';

  @override
  String positionNumber(int n) => 'Position $n';

  @override
  String selectUpToPhotos(int n) => 'Bis zu $n ${photosUnit(n)} wählen';

  @override
  String addWithCount(int n) => 'Hinzufügen ($n)';

  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'alle 15 Min';
      case 30:
        return 'alle 30 Min';
      case 60:
        return 'jede Stunde';
      case 180:
        return 'alle 3 Stunden';
      default:
        return 'alle $minutes Min';
    }
  }

  @override
  String personalPhotosHelp(String partner) =>
      'Eigene Fotos — 1 bis 10 pro Widget. Ab zwei Fotos läuft ein Karussell: '
      'Wechsel beim Entsperren oder nach Zeit.\n\nDiese Fotos sieht nur du. '
      'Um sie mit $partner zu teilen, öffne „Foto des Partners“ → '
      '„Fotos für den Partner wählen“.';

  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Dieses Widget zeigt Fotos, die $partner geteilt hat '
      '($count ${photosUnit(count)}). Ändern kann sie nur $partner.';

  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner hat noch keine Fotos geteilt. Damit sie hier erscheinen, muss '
      '$partner „Foto des Partners“ öffnen und auf „Fotos für den Partner '
      'wählen“ tippen — das normale „Foto-Widget“ sieht nur der Besitzer.';

  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner sieht $count deiner ${photosUnit(count)}';

  @override
  String partnerSharedCountHelp(int count) =>
      'Dein Partner hat $count Fotos geteilt — wähle, wie sie in diesem '
      'Widget wechseln.';

  @override
  String captionDestPairWidgetSub(String partner) =>
      'Foto in „Mein Widget“ — für dich und $partner sichtbar';

  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Ein eigenes Widget mit einem Foto für $partner';

  // ── Маскоты ─────────────────────────────────────────────────────────────

  @override
  String mascotDeactivated(String name) => '$name ist deaktiviert';

  @override
  String mascotActivated(String name) => '$name ist jetzt aktiv';

  @override
  String deleteMascotBody(String name) => '„$name“ wird endgültig gelöscht.';

  @override
  String mascotsCount(int count, int max) => '$count / $max Maskottchen';

  @override
  String mascotSleepRange(String from, String to) =>
      'Schläft von $from bis $to';

  @override
  String mascotNightRange(String from, String to) =>
      'Leuchtet von $from bis $to';

  // ── Цикл ────────────────────────────────────────────────────────────────

  @override
  String cycleOf(String name) => 'Zyklus von $name';

  @override
  String cycleDaysLeft(int days) => 'In $days ${days == 1 ? 'Tag' : 'Tagen'}';

  @override
  String cycleDayOfCycle(int day) => 'Tag $day des Zyklus';

  @override
  String cycleOverdue(int days) =>
      '$days ${days == 1 ? 'Tag' : 'Tage'} überfällig';

  @override
  String cycleAnalyticsHint(int cycles) =>
      'über die letzten $cycles ${cycles == 1 ? 'Zyklus' : 'Zyklen'}';

  @override
  String cycleDaysValue(int days) => '$days ${days == 1 ? 'Tag' : 'Tage'}';

  @override
  String cyclePeriodDayLabel(int day) => 'Periode, Tag $day';

  @override
  String dayLogDate(DateTime day) =>
      '${day.day}. ${cycleMonthsGenitive[day.month - 1]}';

  @override
  String dayLogWeekday(DateTime day) => longWeekdays[day.weekday - 1];

  // ── Открытки ────────────────────────────────────────────────────────────

  @override
  String pcReceiptShift(int days) => 'Schicht Nr. $days';

  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Erinnerungen — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Zeichnungen — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('Vermisse dich — ${stats.missYou}');
    if (stats.streak > 0) {
      lines.add('Tage hintereinander — ${stats.streak}');
    }
    if (lines.isEmpty) lines.add('Es fängt gerade an — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'Von: ${from.isEmpty ? 'mir' : from}\n'
      'Inhalt: $days Tage, alles unversehrt';

  // ── Подарки ─────────────────────────────────────────────────────────────

  @override
  String giftFromPartner(String name) => 'Ein Geschenk von $name';

  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? 'Es ist entwischt!' : 'Wieder entwischt, fang es!';

  @override
  String giftIncomingCount(int n) => n == 1 ? 'wartet' : '$n warten';

  @override
  String giftMutualBonus(int coins) => 'Genau richtig: $coins für jeden';

  @override
  String giftSunriseGreeting(String name) =>
      'Guten Morgen! $name schickt dir einen Sonnenaufgang';

  @override
  String giftPushBody(String giftName) =>
      'Hat dir ein Geschenk geschickt: $giftName';

  // ── Профиль партнёра и статистика ───────────────────────────────────────

  @override
  String partnerGiftsChip(int count) => '$count';

  @override
  String partnerMissChip(int count) => '$count';

  @override
  String partnerDaysTogether(int days) =>
      days == 1 ? '1 Tag zusammen' : '$days Tage zusammen';

  @override
  String partnerMissPeak(String weekday) => 'Am häufigsten $weekday';

  @override
  String weekdayShort(int weekday) => shortWeekdays[weekday - 1];

  /// Наречие, а не название дня: строка встаёт в «Am häufigsten montags».
  @override
  String weekdayLong(int weekday) => const [
    'montags',
    'dienstags',
    'mittwochs',
    'donnerstags',
    'freitags',
    'samstags',
    'sonntags',
  ][weekday - 1];

  // ── Совместный просмотр ─────────────────────────────────────────────────

  @override
  String watchWithPartner(String name) => 'Mit $name schauen';

  @override
  String watchVideoAdd(int mb) => 'Bis zu $mb MB hochladen';

  @override
  String watchVideoTooBig(int mb) =>
      'Das Video ist größer als $mb MB: komprimiere es oder nimm ein kürzeres';

  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName lädt dich zum gemeinsamen Schauen ein';
}
