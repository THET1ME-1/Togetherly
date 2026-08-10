part of 'locale_service.dart';

/// Французский: то, что словарём не выражается.
///
/// Простые строки берутся из `kStrings` по коду `fr` (`lib/l10n/dict/`), здесь
/// остаются подстановки, числительные и списки дат.
///
/// Во французском единственное число берут и ноль, и единица: «0 jour»,
/// «1 jour», «2 jours». Апостроф всюду типографский (’), иначе он ломал бы
/// Dart-литерал в одинарных кавычках.
class _FrStrings extends _EnStrings {
  const _FrStrings() : super('fr');

  /// Единственное число при 0 и 1 — правило языка, а не описка.
  static String _n(int n, String one, String many) => n.abs() <= 1 ? one : many;

  // ── Списки дат ──────────────────────────────────────────────────────────

  @override
  List<String> get shortMonths => const [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  @override
  List<String> get monthAbbrev => shortMonths;

  @override
  List<String> get cycleMonthsGenitive => shortMonths;

  /// Первый элемент пустой: индексация по номеру месяца (1–12).
  @override
  List<String> get fullMonths => const [
    '',
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  @override
  List<String> get cycleMonthNames => const [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  @override
  List<String> get shortWeekdays => const [
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.',
  ];

  @override
  List<String> get cycleWeekdayShorts => const [
    'lu',
    'ma',
    'me',
    'je',
    've',
    'sa',
    'di',
  ];

  @override
  List<String> get shortWeekdaysUpper => const [
    'LUN',
    'MAR',
    'MER',
    'JEU',
    'VEN',
    'SAM',
    'DIM',
  ];

  /// Mardi и mercredi начинаются одинаково, как и jeudi с... — в узкой сетке
  /// календаря на два знака места нет, поэтому буквы повторяются.
  @override
  List<String> get shortWeekdaysSingleChar => const [
    'L',
    'M',
    'M',
    'J',
    'V',
    'S',
    'D',
  ];

  @override
  List<String> get longWeekdays => const [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  @override
  List<String> get reflectionQuestions => const [
    'Qu’a fait ton partenaire aujourd’hui qui t’a touché ?',
    'Quel moment avec ton partenaire t’a fait sourire aujourd’hui ?',
    'Qu’admires-tu chez ton partenaire en ce moment ?',
    'De quoi es-tu reconnaissant dans votre relation aujourd’hui ?',
    'Quel souvenir avec ton partenaire te revient sans cesse ?',
    'Comment ton partenaire t’a-t-il surpris récemment ?',
    'Qu’est-ce qui rend ton partenaire unique pour toi ?',
    'Comment ton partenaire t’a-t-il soutenu aujourd’hui ?',
    'Que veux-tu dire à ton partenaire aujourd’hui ?',
    'Quelle aventure aimerais-tu vivre avec ton partenaire ?',
    'Quelle chanson te rappelle ton partenaire, et pourquoi ?',
    'Quelle est la plus belle chose dans votre relation ?',
    'Quelle petite attention de ton partenaire t’a le plus touché ces temps-ci ?',
    'Qu’as-tu appris de nouveau sur ton partenaire ?',
    'Qu’est-ce qui t’inquiète quand tu penses à votre avenir ?',
    'Que voulez-vous accomplir ensemble dans les prochains mois ?',
    'Quand t’es-tu senti vraiment compris pour la dernière fois ?',
    'Que te manque-t-il, dont vous n’avez pas encore parlé ?',
    'Quelle habitude de ton partenaire aimes-tu particulièrement ?',
    'Que raconterais-tu aujourd’hui à votre premier jour ensemble ?',
  ];

  // ── Ошибки и вход ───────────────────────────────────────────────────────

  @override
  String loginError(String e) => 'Erreur de connexion : $e';

  @override
  String googleLoginError(String e) => 'Erreur de connexion Google : $e';

  @override
  String registrationError(String e) => 'Erreur d’inscription : $e';

  @override
  String passwordResetSent(String email) =>
      'Un e-mail de réinitialisation est parti à $email. '
      'Regarde aussi dans les spams.';

  @override
  String genericError(String e) => 'Erreur : $e';

  @override
  String uploadError(String e) => 'Erreur d’envoi : $e';

  @override
  String failedToSave(Object e) => 'Échec de l’enregistrement : $e';

  @override
  String exportError(String e) => 'Erreur pendant l’export : $e';

  @override
  String downloadFailed(String e) => 'Téléchargement échoué : $e';

  @override
  String failedSelectPhotos(String e) => 'Impossible de choisir les photos : $e';

  @override
  String failedSelectVideo(String e) => 'Impossible de choisir la vidéo : $e';

  @override
  String failedAddMemory(String e) => 'Impossible d’ajouter le souvenir : $e';

  @override
  String failedAddWidget(String e) => 'Impossible d’ajouter le widget : $e';

  @override
  String failedSetStatus(String e) => 'Impossible de définir le statut : $e';

  @override
  String failedClearStatus(String e) => 'Impossible d’effacer le statut : $e';

  @override
  String failedAddStatus(String e) => 'Impossible d’ajouter le statut : $e';

  @override
  String failedUpdateStatus(String e) => 'Impossible de modifier le statut : $e';

  @override
  String failedDeleteStatus(String e) => 'Impossible de supprimer le statut : $e';

  // ── Главная, таймеры, счётчики ──────────────────────────────────────────

  @override
  String daysLabel(String suffix) => 'JOURS $suffix';

  @override
  String monthsLabel(String suffix) => 'MOIS $suffix';

  @override
  String timeLabel(String suffix) => 'TEMPS $suffix';

  @override
  String daysTogetherLabel(String days) => '$days jours';

  @override
  String yearsAlready(int years) =>
      years <= 1 ? 'Déjà un an ❤️' : 'Déjà $years ans ❤️';

  @override
  String timerDaysCount(int days) => '$days ${_n(days, 'jour', 'jours')}';

  @override
  String timerDeleteConfirm(String name) => '« $name » disparaîtra pour de bon.';

  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';

  @override
  String daysTogetherNotifBody(int days) =>
      'Vous êtes ensemble depuis $days ${_n(days, 'jour', 'jours')} ❤️';

  @override
  String streakLabel(int days) =>
      'Série : $days ${_n(days, 'jour', 'jours')}';

  @override
  String recordStreakDays(int days) => 'Record : $days j.';

  @override
  String recordStreakBadge(int days) => '$days j.';

  // ── Настроение и самочувствие ───────────────────────────────────────────

  @override
  String partnerIsMood(String name, String mood) => '$name : $mood';

  @override
  String partnerMood(String name) => 'Humeur de $name';

  @override
  String moodDateLabel(String dateLabel) => 'Humeur — $dateLabel';

  @override
  String moodRecorded(String label) => '$label, c’est noté !';

  @override
  String moodPackAuthor(String name) => 'Dessins de $name';

  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name ne va pas fort : $label';

  @override
  String moodNotifTitle(String name) => '$name a changé d’humeur';

  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score sur $max';

  @override
  String statsMoodMarks(int n) => 'Entrées en 30 jours : $n';

  // ── Достижения и капсула ────────────────────────────────────────────────

  @override
  String achProgressOf(int value, int target) => '$value sur $target';

  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      '$unlocked sur $total obtenus';

  @override
  String capsuleOpensIn(int days) => days <= 0
      ? 's’ouvre aujourd’hui'
      : 'dans $days ${_n(days, 'jour', 'jours')}';

  @override
  String capsuleOpensOn(String date) => 'S’ouvre le $date';

  @override
  String capsuleFrom(String name) => 'de $name';

  @override
  String capsuleNotReady(String date) => 'Pas encore 🙈 S’ouvre le $date';

  @override
  String capsuleOpenedBodyNamed(String title) =>
      '« $title » t’attend dans le fil';

  // ── Монеты, покупки, Togetherly+ ────────────────────────────────────────

  @override
  String premiumThemeLocked(int price) =>
      'Thème payant — $price pièces, à débloquer dans la boutique';

  @override
  String buyThemeDescription(String themeName, int price) =>
      'Débloquer le thème « $themeName » pour $price pièces ?';

  @override
  String coinPackTitle(int coins) => '$coins pièces';

  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins pièces créditées';

  @override
  String coinEarned(int amount) => '+$amount pièces gagnées !';

  @override
  String coinsPlus(int n) => '+$n ${_n(n, 'pièce', 'pièces')}';

  @override
  String unlockForCoins(int price) => 'Débloquer — $price 🪙';

  @override
  String notEnoughCoinsNeed(int price) =>
      'Pas assez de pièces — il en faut $price 🪙';

  @override
  String redeemCodeDone(int coins) => '$coins pièces créditées';

  @override
  String supportCopied(String email) => 'Adresse copiée : $email';

  // ── Группа, приглашения, связь ──────────────────────────────────────────

  @override
  String groupOf(int count) => 'Groupe de $count';

  @override
  String membersCount(int count) => 'MEMBRES · $count';

  @override
  String membersCountBracket(int count) => 'MEMBRES ($count)';

  @override
  String membersOfMax(int current, int max) => '$current/$max membres';

  @override
  String shareInviteText(String code, String link) =>
      'Rejoins-moi sur Togetherly ! Code : $code\n\nOu clique ici : $link';

  @override
  String shareGroupInviteText(String code, String link) =>
      'Rejoins notre groupe sur Togetherly ! Code : $code\n\n'
      'Ou clique ici : $link';

  @override
  String joinMeLinkText(String link) => 'Rejoins-moi sur Togetherly ! $link';

  @override
  String connectedWithCouple(String name) => 'Te voilà relié à $name !';

  @override
  String marriedTo(String name) => 'Te voilà marié à $name ! 💍';

  @override
  String friendsWith(String name) => 'Vous êtes amis avec $name !';

  @override
  String buddiesWith(String name) => '$name et toi, meilleurs amis !';

  @override
  String customRelWith(String label, String name) =>
      'Te voilà $label avec $name !';

  @override
  String onboardingLeft(int left) => left <= 1
      ? 'Encore une étape'
      : 'Encore $left étapes';

  @override
  String onboardingNext(String step) => 'Encore une étape : $step';

  @override
  String quietPartnerTitle(String name, int days) => days <= 1
      ? '$name n’est pas venu depuis un jour'
      : '$name n’est pas venu depuis $days jours';

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return '$n ${_n(n, 'jour', 'jours')}';
  }

  // ── Чат ─────────────────────────────────────────────────────────────────

  @override
  String chatReplyingTo(String name) => 'Réponse à $name';

  @override
  String chatTyping(String name) => '$name écrit…';

  @override
  String chatNotifTitle(String name) => '$name t’écrit 💬';

  @override
  String chatDeleteConfirm(String text) => 'Supprimer ce message ?';

  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Aujourd’hui';
    if (diff == 1) return 'Hier';
    // Первое число месяца — «1er», остальные обычные.
    final dayLabel = day.day == 1 ? '1er' : '${day.day}';
    final base = '$dayLabel ${cycleMonthNames[day.month - 1]}';
    return day.year == now.year ? base : '$base ${day.year}';
  }

  @override
  String chatBgConfirmBody(int price) =>
      'Mettre ta photo en fond du chat pour $price 🪙 ?\n\n'
      'Chaque changement coûtera aussi $price 🪙.';

  // ── Воспоминания и медиа ────────────────────────────────────────────────

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Photo',
    'video' => 'Vidéo',
    'location' => 'Lieu',
    'music' => 'Musique',
    'text' => 'Note',
    'videoLink' => 'Lien vidéo',
    'book' => 'Livre',
    _ => 'Film',
  };

  @override
  String newMemory(String type) => 'Nouveau : $type';

  @override
  String memoriesUnit(int n) => _n(n, 'souvenir', 'souvenirs');

  @override
  String savedToPath(String path) => 'Enregistré dans $path';

  @override
  String nPhotos(int count) => '$count photos';

  @override
  String openIn(String name) => 'Ouvrir dans $name';

  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '${day == 1 ? '1er' : day} $month $year à $time';

  @override
  String memoryFileTooBig(int limitMb) =>
      'Le fichier dépasse $limitMb Mo — il ne partira pas';

  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'Le fichier dépasse $limitMb Mo. Togetherly+ double la limite';

  @override
  String selectedCount(int n) => '$n sélectionnés';

  @override
  String itemsShort(int n) => '$n éléments';

  @override
  String kpRating(String rating) => 'KP $rating';

  @override
  String yearRange(int first, int last) => 'Année de $first à $last';

  // ── Статус и профиль ────────────────────────────────────────────────────

  @override
  String statusSetTo(String status) => 'Statut défini : $status';

  @override
  String deleteStatusConfirm(String label) =>
      'Supprimer « $label » pour de bon ?';

  @override
  String widgetOfPartner(String name) => 'Widget de $name';

  @override
  String symbolSearchFound(int count) => 'Trouvés : $count';

  // ── Уведомления «скучаю» и импульсы ─────────────────────────────────────

  @override
  String missYouNotifTitle(String name) => '$name pense à toi';

  @override
  String missYouStreak(int count) => '🔥 $count';

  @override
  String thinkingOfYouNotifTitle(String name) => '$name pense à toi 💭';

  @override
  String wantHugNotifTitle(String name) => '$name veut te serrer dans ses bras 🤗';

  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карта и расстояния ──────────────────────────────────────────────────

  @override
  String kmFromYou(String km) => '$km de toi';

  @override
  String minutesAgo(int m) => 'il y a $m min';

  @override
  String hoursAgo(int h) => 'il y a $h h';

  @override
  String daysAgo(int d) => 'il y a $d j';

  @override
  String liveLocationAgo(String value) => 'il y a $value';

  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  // ── Рисование и холсты ──────────────────────────────────────────────────

  @override
  String partnerIsDrawing(String name) => '$name dessine…';

  @override
  String drawingSavedTo(String path) => 'Dessin enregistré : $path';

  @override
  String drawLayerName(int index) => 'Calque $index';

  @override
  String drawLayerStrokes(int count) =>
      count == 0 ? 'vide' : '$count ${_n(count, 'trait', 'traits')}';

  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Uni',
    'grid' => 'Quadrillage',
    'dots' => 'Points',
    'notebook' => 'Cahier',
    'millimeter' => 'Papier millimétré',
    'kraft' => 'Kraft',
    'chalkboard' => 'Tableau noir',
    'music' => 'Partition',
    'stars' => 'Étoiles',
    'hearts' => 'Cœurs',
    'watercolor' => 'Aquarelle',
    'film' => 'Pellicule',
    _ => id,
  };

  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count ${_n(count, 'dessin', 'dessins')} · dernier $lastDate';

  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells cases · $px px par pixel à l’export';

  @override
  String deleteCanvasesTitle(int n) =>
      n <= 1 ? 'Supprimer la toile ?' : 'Supprimer $n toiles ?';

  @override
  String deleteCanvasesConfirm(int n) => n <= 1
      ? 'Le dessin disparaîtra chez vous deux. C’est définitif.'
      : 'Les dessins disparaîtront chez vous deux. C’est définitif.';

  @override
  String coloringPartnerColoring(String name) => '$name colorie';

  @override
  String coloringWaitingHint(String name) =>
      'on ouvre dès que $name appuie sur Terminé';

  // ── Виджеты ─────────────────────────────────────────────────────────────

  @override
  String tgDaysTogetherCaption(int days) =>
      _n(days, 'jour ensemble', 'jours ensemble');

  @override
  String tgMonthsCaption(int months) => _n(months, 'mois', 'mois');

  @override
  String tgDaysMilestone(int days) => '$days ${_n(days, 'jour', 'jours')}';

  @override
  String tgYearsMilestone(int years) => '$years ${_n(years, 'an', 'ans')}';

  @override
  String tgInDays(int days) => 'dans $days ${_n(days, 'jour', 'jours')}';

  @override
  String tgUntilMilestone(int target, int left) =>
      'Jusqu’à ${tgDaysMilestone(target)} — ${tgInDays(left)}';

  @override
  String tgMissAddressee(String name) => 'À $name';

  @override
  String tgMoodMatched(int days) => '$days sur 7 identiques';

  @override
  String tgCountdownDaysLeft(int days) =>
      '${_n(days, 'jour', 'jours')} avant de se revoir';

  @override
  String tgYearDaysWord(int days) => _n(days, 'Jour', 'Jours');

  @override
  String tgYearDaysTogether(int days) =>
      '${_n(days, 'Jour', 'Jours')} ensemble';

  @override
  String tgYearDaysLeft(int days) =>
      '$days ${_n(days, 'jour', 'jours')} restants';

  @override
  String tgYearToAnniversary(int year) => 'Vers l’an $year';

  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'Vers l’an $year — $days';

  @override
  String tgYearCurrentYearShort(int year, int days) =>
      'An $year · $days restants';

  @override
  String tgYearOrdinalLabel(int year) =>
      year == 1 ? '1RE ANNÉE ENSEMBLE' : '$year E ANNÉE ENSEMBLE';

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${_n(years, 'AN', 'ANS')} '
      '$days ${_n(days, 'JOUR', 'JOURS')}';

  @override
  String tgYearSince(String date) => 'Depuis $date';

  @override
  String photosUnit(int n) => _n(n, 'photo', 'photos');

  @override
  String photoCountOnUnlock(int count) => '$count photos · au déverrouillage';

  @override
  String photoCountInterval(int count, String interval) =>
      '$count photos · $interval';

  @override
  String photoCountCarousel(int count) => '$count photos · carrousel';

  @override
  String photoNumber(int n) => 'Photo $n';

  @override
  String positionNumber(int n) => 'Position $n';

  @override
  String selectUpToPhotos(int n) => 'Choisis jusqu’à $n ${photosUnit(n)}';

  @override
  String addWithCount(int n) => 'Ajouter ($n)';

  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'toutes les 15 min';
      case 30:
        return 'toutes les 30 min';
      case 60:
        return 'chaque heure';
      case 180:
        return 'toutes les 3 heures';
      default:
        return 'toutes les $minutes min';
    }
  }

  @override
  String personalPhotosHelp(String partner) =>
      'Photos personnelles — de 1 à 10 par widget. À partir de deux photos, un '
      'carrousel démarre : changement au déverrouillage ou par minuterie.\n\n'
      'Ces photos ne sont visibles que par toi. Pour les partager avec '
      '$partner, ouvre « Photo du partenaire » → « Choisir des photos pour le '
      'partenaire ».';

  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Ce widget montre les photos partagées par $partner '
      '($count ${photosUnit(count)}). Seul $partner peut les changer.';

  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner n’a encore rien partagé. Pour que ça apparaisse ici, $partner '
      'doit ouvrir « Photo du partenaire » et appuyer sur « Choisir des photos '
      'pour le partenaire » — le widget « Photo » ordinaire ne se voit que chez '
      'son propriétaire.';

  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner voit $count de tes ${photosUnit(count)}';

  @override
  String partnerSharedCountHelp(int count) =>
      'Ton partenaire a partagé $count photos — choisis comment elles '
      'défilent dans ce widget.';

  @override
  String captionDestPairWidgetSub(String partner) =>
      'Photo dans « Mon widget » — visible par toi et $partner';

  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Un widget à part avec une photo pour $partner';

  // ── Маскоты ─────────────────────────────────────────────────────────────

  @override
  String mascotDeactivated(String name) => '$name est désactivé';

  @override
  String mascotActivated(String name) => '$name est actif';

  @override
  String deleteMascotBody(String name) =>
      '« $name » sera supprimé pour de bon.';

  @override
  String mascotsCount(int count, int max) => '$count / $max mascottes';

  @override
  String mascotSleepRange(String from, String to) => 'Dort de $from à $to';

  @override
  String mascotNightRange(String from, String to) => 'Brille de $from à $to';

  // ── Цикл ────────────────────────────────────────────────────────────────

  @override
  String cycleOf(String name) => 'Cycle de $name';

  @override
  String cycleDaysLeft(int days) =>
      'Dans $days ${_n(days, 'jour', 'jours')}';

  @override
  String cycleDayOfCycle(int day) => 'Jour $day du cycle';

  @override
  String cycleOverdue(int days) =>
      '$days ${_n(days, 'jour', 'jours')} de retard';

  @override
  String cycleAnalyticsHint(int cycles) =>
      'sur les $cycles derniers ${_n(cycles, 'cycle', 'cycles')}';

  @override
  String cycleDaysValue(int days) => '$days ${_n(days, 'jour', 'jours')}';

  @override
  String cyclePeriodDayLabel(int day) => 'règles, jour $day';

  @override
  String dayLogDate(DateTime day) =>
      '${day.day == 1 ? '1er' : day.day} ${cycleMonthsGenitive[day.month - 1]}';

  @override
  String dayLogWeekday(DateTime day) => longWeekdays[day.weekday - 1];

  // ── Открытки ────────────────────────────────────────────────────────────

  @override
  String pcReceiptShift(int days) => 'service n° $days';

  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Souvenirs — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Dessins — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('Tu me manques — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Jours d’affilée — ${stats.streak}');
    if (lines.isEmpty) lines.add('Ça ne fait que commencer — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'De : ${from.isEmpty ? 'moi' : from}\n'
      'Contenu : $days jours, rien de cassé';

  // ── Подарки ─────────────────────────────────────────────────────────────

  @override
  String giftFromPartner(String name) => 'Un cadeau de $name';

  @override
  String giftBunnyMisses(int misses) =>
      misses <= 1 ? 'Il s’est échappé !' : 'Encore filé, attrape-le !';

  @override
  String giftIncomingCount(int n) => n <= 1 ? 'attend' : '$n attendent';

  @override
  String giftMutualBonus(int coins) => 'Pile au bon moment : $coins chacun';

  @override
  String giftSunriseGreeting(String name) =>
      'Bonjour ! $name t’envoie un lever de soleil';

  @override
  String giftPushBody(String giftName) => 'T’a offert un cadeau : $giftName';

  // ── Профиль партнёра и статистика ───────────────────────────────────────

  @override
  String partnerGiftsChip(int count) => '$count';

  @override
  String partnerMissChip(int count) => '$count';

  @override
  String partnerDaysTogether(int days) =>
      'ensemble depuis $days ${_n(days, 'jour', 'jours')}';

  @override
  String partnerMissPeak(String weekday) => 'Le plus souvent $weekday';

  @override
  String weekdayShort(int weekday) => shortWeekdays[weekday - 1];

  /// «Le plus souvent le lundi» — с артиклем, иначе фраза не строится.
  @override
  String weekdayLong(int weekday) => const [
    'le lundi',
    'le mardi',
    'le mercredi',
    'le jeudi',
    'le vendredi',
    'le samedi',
    'le dimanche',
  ][weekday - 1];

  // ── Совместный просмотр ─────────────────────────────────────────────────

  @override
  String watchWithPartner(String name) => 'Regarder avec $name';

  @override
  String watchVideoAdd(int mb) => 'Envoie jusqu’à $mb Mo';

  @override
  String watchVideoTooBig(int mb) =>
      'La vidéo dépasse $mb Mo : compresse-la ou prends-en une plus courte';

  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName t’invite à regarder ensemble';
}
