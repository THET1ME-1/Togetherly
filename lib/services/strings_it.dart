part of 'locale_service.dart';

/// Итальянский: то, что словарём не выражается.
///
/// Простые строки берутся из `kStrings` по коду `it` (`lib/l10n/dict/`), здесь
/// остаются подстановки, числительные и списки дат.
///
/// Порог множественного как в испанском (`== 1`): ноль идёт во множественном —
/// «0 giorni», «1 giorno», «2 giorni». Апостроф типографский (’): машинный
/// ломал бы литерал в одинарных кавычках, а в итальянском он на каждом шагу
/// («l’app», «dell’anno»). Кавычки — «…», месяцы и дни недели со строчной.
class _ItStrings extends _EnStrings {
  const _ItStrings() : super('it');

  static String _n(int n, String one, String many) => n.abs() == 1 ? one : many;

  // ── Списки дат ──────────────────────────────────────────────────────────

  @override
  List<String> get shortMonths => const [
    'gen',
    'feb',
    'mar',
    'apr',
    'mag',
    'giu',
    'lug',
    'ago',
    'set',
    'ott',
    'nov',
    'dic',
  ];

  @override
  List<String> get monthAbbrev => shortMonths;

  @override
  List<String> get cycleMonthsGenitive => shortMonths;

  /// Первый элемент пустой: индексация по номеру месяца (1–12).
  @override
  List<String> get fullMonths => const [
    '',
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre',
  ];

  @override
  List<String> get cycleMonthNames => const [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre',
  ];

  @override
  List<String> get shortWeekdays => const [
    'lun',
    'mar',
    'mer',
    'gio',
    'ven',
    'sab',
    'dom',
  ];

  @override
  List<String> get cycleWeekdayShorts => const [
    'lu',
    'ma',
    'me',
    'gi',
    've',
    'sa',
    'do',
  ];

  @override
  List<String> get shortWeekdaysUpper => const [
    'LUN',
    'MAR',
    'MER',
    'GIO',
    'VEN',
    'SAB',
    'DOM',
  ];

  /// Martedì и mercoledì начинаются одинаково: в узкой сетке календаря места на
  /// два знака нет, поэтому буквы повторяются.
  @override
  List<String> get shortWeekdaysSingleChar => const [
    'L',
    'M',
    'M',
    'G',
    'V',
    'S',
    'D',
  ];

  @override
  List<String> get longWeekdays => const [
    'lunedì',
    'martedì',
    'mercoledì',
    'giovedì',
    'venerdì',
    'sabato',
    'domenica',
  ];

  @override
  List<String> get reflectionQuestions => const [
    'Che cosa ha fatto oggi il tuo partner che ti ha fatto bene?',
    'Quale momento con il tuo partner ti ha fatto sorridere oggi?',
    'Che cosa ammiri del tuo partner in questo momento?',
    'Per che cosa sei grato oggi nella vostra storia?',
    'Quale ricordo con il tuo partner ti torna sempre in mente?',
    'Come ti ha sorpreso il tuo partner di recente?',
    'Che cosa rende speciale il tuo partner per te?',
    'Come ti ha sostenuto oggi il tuo partner?',
    'Che cosa vuoi dire oggi al tuo partner?',
    'Quale avventura vorresti vivere con il tuo partner?',
    'Quale canzone ti ricorda il tuo partner e perché?',
    'Qual è la cosa più bella dello stare insieme?',
    'Quale piccolo gesto del tuo partner ti ha colpito di più ultimamente?',
    'Che cosa hai scoperto di nuovo sul tuo partner?',
    'Che cosa ti spaventa quando pensi al vostro futuro?',
    'Che cosa volete realizzare insieme nei prossimi mesi?',
    'Quando ti sei sentito davvero capito per l’ultima volta?',
    'Che cosa ti manca e di cui non avete ancora parlato?',
    'Quale abitudine del tuo partner ti piace di più?',
    'Che cosa racconteresti oggi al vostro primo giorno insieme?',
  ];

  // ── Ошибки и вход ───────────────────────────────────────────────────────

  @override
  String loginError(String e) => 'Errore di accesso: $e';

  @override
  String googleLoginError(String e) => 'Errore di accesso con Google: $e';

  @override
  String registrationError(String e) => 'Errore di registrazione: $e';

  @override
  String passwordResetSent(String email) =>
      'Abbiamo inviato un’e-mail di reimpostazione a $email. '
      'Controlla anche la cartella spam.';

  @override
  String genericError(String e) => 'Errore: $e';

  @override
  String uploadError(String e) => 'Errore di caricamento: $e';

  @override
  String failedToSave(Object e) => 'Non è stato possibile salvare: $e';

  @override
  String exportError(String e) => 'Errore durante l’esportazione: $e';

  @override
  String downloadFailed(String e) => 'Download non riuscito: $e';

  @override
  String failedSelectPhotos(String e) =>
      'Non è stato possibile scegliere le foto: $e';

  @override
  String failedSelectVideo(String e) =>
      'Non è stato possibile scegliere il video: $e';

  @override
  String failedAddMemory(String e) =>
      'Non è stato possibile aggiungere il ricordo: $e';

  @override
  String failedAddWidget(String e) =>
      'Non è stato possibile aggiungere il widget: $e';

  @override
  String failedSetStatus(String e) =>
      'Non è stato possibile impostare lo stato: $e';

  @override
  String failedClearStatus(String e) =>
      'Non è stato possibile togliere lo stato: $e';

  @override
  String failedAddStatus(String e) =>
      'Non è stato possibile aggiungere lo stato: $e';

  @override
  String failedUpdateStatus(String e) =>
      'Non è stato possibile cambiare lo stato: $e';

  @override
  String failedDeleteStatus(String e) =>
      'Non è stato possibile eliminare lo stato: $e';

  // ── Главная, таймеры, счётчики ──────────────────────────────────────────

  @override
  String daysLabel(String suffix) => 'GIORNI $suffix';

  @override
  String monthsLabel(String suffix) => 'MESI $suffix';

  @override
  String timeLabel(String suffix) => 'TEMPO $suffix';

  @override
  String daysTogetherLabel(String days) => '$days giorni';

  @override
  String yearsAlready(int years) =>
      years == 1 ? 'Già un anno ❤️' : 'Già $years anni ❤️';

  @override
  String monthsAlready(int months) =>
      months == 1 ? 'Già un mese ❤️' : 'Già $months mesi ❤️';

  @override
  String timerDaysCount(int days) => '$days ${_n(days, 'giorno', 'giorni')}';

  @override
  String timerDeleteConfirm(String name) => '«$name» sparirà per sempre.';

  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';

  @override
  String daysTogetherNotifBody(int days) =>
      'Siete insieme da $days ${_n(days, 'giorno', 'giorni')} ❤️';

  @override
  String streakLabel(int days) =>
      'Serie: $days ${_n(days, 'giorno', 'giorni')}';

  @override
  String recordStreakDays(int days) => 'Record: $days g.';

  @override
  String recordStreakBadge(int days) => '$days g.';

  // ── Настроение и самочувствие ───────────────────────────────────────────

  @override
  String partnerIsMood(String name, String mood) => '$name: $mood';

  @override
  String partnerMood(String name) => 'Umore di $name';

  @override
  String moodDateLabel(String dateLabel) => 'Umore — $dateLabel';

  @override
  String moodRecorded(String label) => '$label, annotato!';

  @override
  String moodPackAuthor(String name) => 'Disegni di $name';

  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name non sta bene: $label';

  @override
  String moodNotifTitle(String name) => '$name ha cambiato umore';

  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score su $max';

  @override
  String statsMoodMarks(int n) => 'Registrazioni in 30 giorni: $n';

  // ── Достижения и капсула ────────────────────────────────────────────────

  @override
  String achProgressOf(int value, int target) => '$value su $target';

  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      '$unlocked su $total ottenuti';

  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'si apre oggi' : 'tra $days ${_n(days, 'giorno', 'giorni')}';

  @override
  String capsuleOpensOn(String date) => 'Si apre il $date';

  @override
  String capsuleFrom(String name) => 'da $name';

  @override
  String capsuleNotReady(String date) => 'Non ancora 🙈 Si apre il $date';

  @override
  String capsuleOpenedBodyNamed(String title) =>
      '«$title» ti aspetta nel diario';

  // ── Монеты, покупки, Togetherly+ ────────────────────────────────────────

  @override
  String premiumThemeLocked(int price) =>
      'Tema a pagamento — $price monete, sbloccalo nel negozio';

  @override
  String buyThemeDescription(String themeName, int price) =>
      'Sbloccare il tema «$themeName» per $price monete?';

  @override
  String coinPackTitle(int coins) => '$coins monete';

  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins monete accreditate';

  @override
  String coinEarned(int amount) => '+$amount monete guadagnate!';

  @override
  String coinsPlus(int n) => '+$n ${_n(n, 'moneta', 'monete')}';

  @override
  String unlockForCoins(int price) => 'Sblocca — $price 🪙';

  @override
  String notEnoughCoinsNeed(int price) =>
      'Monete insufficienti — ne servono $price 🪙';

  @override
  String redeemCodeDone(int coins) => '$coins monete accreditate';

  @override
  String supportCopied(String email) => 'Indirizzo copiato: $email';

  // ── Группа, приглашения, связь ──────────────────────────────────────────

  @override
  String groupOf(int count) => 'Gruppo di $count';

  @override
  String membersCount(int count) => 'MEMBRI · $count';

  @override
  String membersCountBracket(int count) => 'MEMBRI ($count)';

  @override
  String membersOfMax(int current, int max) => '$current/$max membri';

  @override
  String shareInviteText(String code, String link) =>
      'Unisciti a me su Togetherly! Codice: $code\n\nO clicca qui: $link';

  @override
  String shareGroupInviteText(String code, String link) =>
      'Unisciti al nostro gruppo su Togetherly! Codice: $code\n\n'
      'O clicca qui: $link';

  @override
  String joinMeLinkText(String link) => 'Unisciti a me su Togetherly! $link';

  @override
  String connectedWithCouple(String name) => 'Ora sei in coppia con $name!';

  @override
  String marriedTo(String name) => 'Sei sposato con $name! 💍';

  @override
  String friendsWith(String name) => 'Ora sei amico di $name!';

  @override
  String buddiesWith(String name) => '$name e tu, migliori amici!';

  @override
  String customRelWith(String label, String name) =>
      'Ora sei $label con $name!';

  @override
  String onboardingLeft(int left) =>
      left == 1 ? 'Manca un passo' : 'Mancano $left passi';

  @override
  String onboardingNext(String step) => 'Manca un passo: $step';

  @override
  String quietPartnerTitle(String name, int days) => days == 1
      ? '$name non si fa vedere da un giorno'
      : '$name non si fa vedere da $days giorni';

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return '$n ${_n(n, 'giorno', 'giorni')}';
  }

  // ── Чат ─────────────────────────────────────────────────────────────────

  @override
  String chatReplyingTo(String name) => 'Risposta a $name';

  @override
  String chatTyping(String name) => '$name sta scrivendo…';

  @override
  String chatNotifTitle(String name) => '$name ti scrive 💬';

  @override
  String chatDeleteConfirm(String text) => 'Eliminare questo messaggio?';

  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Oggi';
    if (diff == 1) return 'Ieri';
    // Первое число месяца — «1º», остальные обычные.
    final dayLabel = day.day == 1 ? '1º' : '${day.day}';
    final base = '$dayLabel ${cycleMonthNames[day.month - 1]}';
    return day.year == now.year ? base : '$base ${day.year}';
  }

  @override
  String chatBgConfirmBody(int price) =>
      'Mettere la tua foto come sfondo della chat per $price 🪙?\n\n'
      'Ogni cambio successivo costerà anche $price 🪙.';

  // ── Воспоминания и медиа ────────────────────────────────────────────────

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Foto',
    'video' => 'Video',
    'location' => 'Luogo',
    'music' => 'Musica',
    'text' => 'Nota',
    'videoLink' => 'Link video',
    'book' => 'Libro',
    _ => 'Film',
  };

  @override
  String newMemory(String type) => 'Nuovo: $type';

  @override
  String memoriesUnit(int n) => _n(n, 'ricordo', 'ricordi');

  @override
  String savedToPath(String path) => 'Salvato in $path';

  @override
  String nPhotos(int count) => '$count foto';

  @override
  String openIn(String name) => 'Apri in $name';

  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '${day == 1 ? '1º' : day} $month $year alle $time';

  @override
  String memoryFileTooBig(int limitMb) =>
      'Il file supera $limitMb MB — non verrà caricato';

  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'Il file supera $limitMb MB. Togetherly+ raddoppia il limite';

  @override
  String selectedCount(int n) => '$n selezionati';

  @override
  String itemsShort(int n) => '$n elementi';

  @override
  String kpRating(String rating) => 'KP $rating';

  @override
  String yearRange(int first, int last) => 'Anno da $first a $last';

  // ── Статус и профиль ────────────────────────────────────────────────────

  @override
  String statusSetTo(String status) => 'Stato impostato: $status';

  @override
  String deleteStatusConfirm(String label) => 'Eliminare «$label» per sempre?';

  @override
  String widgetOfPartner(String name) => 'Widget di $name';

  @override
  String symbolSearchFound(int count) => 'Trovati: $count';

  // ── Уведомления «скучаю» и импульсы ─────────────────────────────────────

  @override
  String missYouNotifTitle(String name) => '$name ti pensa';

  @override
  String missYouStreak(int count) => '🔥 $count';

  @override
  String thinkingOfYouNotifTitle(String name) => '$name pensa a te 💭';

  @override
  String wantHugNotifTitle(String name) => '$name vuole abbracciarti 🤗';

  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карта и расстояния ──────────────────────────────────────────────────

  @override
  String kmFromYou(String km) => '$km da te';

  @override
  String minutesAgo(int m) => '$m min fa';

  @override
  String hoursAgo(int h) => '$h h fa';

  @override
  String daysAgo(int d) => '$d g fa';

  @override
  String liveLocationAgo(String value) => '$value fa';

  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  // ── Рисование и холсты ──────────────────────────────────────────────────

  @override
  String partnerIsDrawing(String name) => '$name sta disegnando…';

  @override
  String drawingSavedTo(String path) => 'Disegno salvato: $path';

  @override
  String drawLayerName(int index) => 'Livello $index';

  @override
  String drawLayerStrokes(int count) =>
      count == 0 ? 'vuoto' : '$count ${_n(count, 'tratto', 'tratti')}';

  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Liscio',
    'grid' => 'Griglia',
    'dots' => 'Punti',
    'notebook' => 'Quaderno',
    'millimeter' => 'Carta millimetrata',
    'kraft' => 'Kraft',
    'chalkboard' => 'Lavagna',
    'music' => 'Spartito',
    'stars' => 'Stelle',
    'hearts' => 'Cuori',
    'watercolor' => 'Acquerello',
    'film' => 'Pellicola',
    _ => id,
  };

  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count ${_n(count, 'disegno', 'disegni')} · ultimo $lastDate';

  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells caselle · $px px per pixel all’esportazione';

  @override
  String deleteCanvasesTitle(int n) =>
      n == 1 ? 'Eliminare la tela?' : 'Eliminare $n tele?';

  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'Il disegno sparirà per entrambi. Non si torna indietro.'
      : 'I disegni spariranno per entrambi. Non si torna indietro.';

  @override
  String coloringPartnerColoring(String name) => '$name sta colorando';

  @override
  String coloringWaitingHint(String name) => 'apriamo appena $name tocca Fatto';

  // ── Виджеты ─────────────────────────────────────────────────────────────

  @override
  String tgDaysTogetherCaption(int days) =>
      _n(days, 'giorno insieme', 'giorni insieme');

  @override
  String tgMonthsCaption(int months) => _n(months, 'mese', 'mesi');

  @override
  String tgDaysMilestone(int days) => '$days ${_n(days, 'giorno', 'giorni')}';

  @override
  String tgYearsMilestone(int years) => '$years ${_n(years, 'anno', 'anni')}';

  @override
  String tgInDays(int days) => 'tra $days ${_n(days, 'giorno', 'giorni')}';

  @override
  String tgUntilMilestone(int target, int left) =>
      'Fino a ${tgDaysMilestone(target)} — ${tgInDays(left)}';

  @override
  String tgMissAddressee(String name) => 'A $name';

  @override
  String tgMoodMatched(int days) => '$days su 7 uguali';

  @override
  String tgCountdownDaysLeft(int days) =>
      '${_n(days, 'giorno', 'giorni')} al rivederci';

  @override
  String tgYearDaysWord(int days) => _n(days, 'Giorno', 'Giorni');

  @override
  String tgYearDaysTogether(int days) =>
      '${_n(days, 'Giorno', 'Giorni')} insieme';

  @override
  String tgYearDaysLeft(int days) =>
      '$days ${_n(days, 'giorno', 'giorni')} rimasti';

  @override
  String tgYearToAnniversary(int year) => 'Fino all’anno $year';

  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'Fino all’anno $year — $days';

  @override
  String tgYearCurrentYearShort(int year, int days) =>
      'Anno $year · $days rimasti';

  @override
  String tgYearOrdinalLabel(int year) => '$year° ANNO INSIEME';

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${_n(years, 'ANNO', 'ANNI')} '
      '$days ${_n(days, 'GIORNO', 'GIORNI')}';

  @override
  String tgYearSince(String date) => 'Dal $date';

  @override
  String photosUnit(int n) => _n(n, 'foto', 'foto');

  @override
  String photoCountOnUnlock(int count) => '$count foto · allo sblocco';

  @override
  String photoCountInterval(int count, String interval) =>
      '$count foto · $interval';

  @override
  String photoCountCarousel(int count) => '$count foto · carosello';

  @override
  String photoNumber(int n) => 'Foto $n';

  @override
  String positionNumber(int n) => 'Posizione $n';

  @override
  String selectUpToPhotos(int n) => 'Scegli fino a $n ${photosUnit(n)}';

  @override
  String addWithCount(int n) => 'Aggiungi ($n)';

  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'ogni 15 min';
      case 30:
        return 'ogni 30 min';
      case 60:
        return 'ogni ora';
      case 180:
        return 'ogni 3 ore';
      default:
        return 'ogni $minutes min';
    }
  }

  @override
  String personalPhotosHelp(String partner) =>
      'Foto personali — da 1 a 10 per widget. Da due foto in su parte un '
      'carosello: cambia allo sblocco o a tempo.\n\nQueste foto le vedi solo '
      'tu. Per condividerle con $partner apri «Foto del partner» → «Scegli le '
      'foto per il partner».';

  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Questo widget mostra le foto condivise da $partner '
      '($count ${photosUnit(count)}). Solo $partner può cambiarle.';

  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner non ha ancora condiviso foto. Perché compaiano qui, $partner '
      'deve aprire «Foto del partner» e toccare «Scegli le foto per il '
      'partner» — il widget «Foto» normale lo vede solo chi lo possiede.';

  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner vede $count delle tue ${photosUnit(count)}';

  @override
  String partnerSharedCountHelp(int count) =>
      'Il tuo partner ha condiviso $count foto — scegli come si alternano in '
      'questo widget.';

  @override
  String captionDestPairWidgetSub(String partner) =>
      'Foto in «Il mio widget» — la vedete tu e $partner';

  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Un widget a parte con una foto per $partner';

  // ── Маскоты ─────────────────────────────────────────────────────────────

  @override
  String mascotDeactivated(String name) => '$name è disattivata';

  @override
  String mascotActivated(String name) => '$name ora è attiva';

  @override
  String deleteMascotBody(String name) => '«$name» verrà eliminata per sempre.';

  @override
  String mascotsCount(int count, int max) => '$count / $max mascotte';

  @override
  String mascotSleepRange(String from, String to) =>
      'Dorme dalle $from alle $to';

  @override
  String mascotNightRange(String from, String to) =>
      'Brilla dalle $from alle $to';

  // ── Цикл ────────────────────────────────────────────────────────────────

  @override
  String cycleOf(String name) => 'Ciclo di $name';

  @override
  String cycleDaysLeft(int days) => 'Tra $days ${_n(days, 'giorno', 'giorni')}';

  @override
  String cycleDayOfCycle(int day) => 'Giorno $day del ciclo';

  @override
  String cycleOverdue(int days) =>
      '$days ${_n(days, 'giorno', 'giorni')} di ritardo';

  @override
  String cycleAnalyticsHint(int cycles) =>
      'sugli ultimi $cycles ${_n(cycles, 'ciclo', 'cicli')}';

  @override
  String cycleDaysValue(int days) => '$days ${_n(days, 'giorno', 'giorni')}';

  @override
  String cyclePeriodDayLabel(int day) => 'ciclo, giorno $day';

  @override
  String dayLogDate(DateTime day) =>
      '${day.day == 1 ? '1º' : day.day} ${cycleMonthsGenitive[day.month - 1]}';

  @override
  String dayLogWeekday(DateTime day) => longWeekdays[day.weekday - 1];

  // ── Открытки ────────────────────────────────────────────────────────────

  @override
  String pcReceiptShift(int days) => 'turno n. $days';

  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Ricordi — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Disegni — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('Mi manchi — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Giorni di fila — ${stats.streak}');
    if (lines.isEmpty) lines.add('È appena cominciata — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'Da: ${from.isEmpty ? 'me' : from}\n'
      'Contenuto: $days giorni, tutto intatto';

  // ── Подарки ─────────────────────────────────────────────────────────────

  @override
  String giftFromPartner(String name) => 'Un regalo da $name';

  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? 'È scappato!' : 'Scappato di nuovo, prendilo!';

  @override
  String giftIncomingCount(int n) => n == 1 ? 'aspetta' : '$n aspettano';

  @override
  String giftMutualBonus(int coins) =>
      'Proprio al momento giusto: $coins a testa';

  @override
  String giftSunriseGreeting(String name) =>
      'Buongiorno! $name ti manda un’alba';

  @override
  String giftPushBody(String giftName) => 'Ti ha mandato un regalo: $giftName';

  // ── Профиль партнёра и статистика ───────────────────────────────────────

  @override
  String partnerGiftsChip(int count) => '$count';

  @override
  String partnerMissChip(int count) => '$count';

  @override
  String partnerDaysTogether(int days) =>
      'insieme da $days ${_n(days, 'giorno', 'giorni')}';

  @override
  String partnerMissPeak(String weekday) => 'Più spesso $weekday';

  @override
  String weekdayShort(int weekday) => shortWeekdays[weekday - 1];

  /// «Più spesso il lunedì» — с артиклем, иначе фраза не строится.
  @override
  String weekdayLong(int weekday) => const [
    'il lunedì',
    'il martedì',
    'il mercoledì',
    'il giovedì',
    'il venerdì',
    'il sabato',
    'la domenica',
  ][weekday - 1];

  // ── Совместный просмотр ─────────────────────────────────────────────────

  @override
  String watchWithPartner(String name) => 'Guarda con $name';

  @override
  String watchVideoAdd(int mb) => 'Carica fino a $mb MB';

  @override
  String watchVideoTooBig(int mb) =>
      'Il video supera $mb MB: comprimilo o scegline uno più corto';

  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName ti invita a guardare insieme';
}
