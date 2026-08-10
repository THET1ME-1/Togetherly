part of 'locale_service.dart';

/// Португальский: то, что словарём не выражается.
///
/// Простые строки берутся из `kStrings` по коду `pt` (`lib/l10n/dict/`), здесь
/// остаются подстановки, числительные и списки дат.
///
/// Норма бразильская: обращение на «você», а не «tu». Так решено потому, что
/// говорящих в Бразилии на порядок больше, а `LocaleService.detect` отправляет
/// в `pt` и `pt-BR`, и `pt-PT` — одна колонка словаря на всех.
///
/// Порог множественного как в испанском (`== 1`): ноль идёт во множественном —
/// «0 dias», «1 dia», «2 dias». Первое число месяца пишется «1º», дата с
/// предлогом: «8 de março de 2001». Месяцы и дни недели со строчной.
class _PtStrings extends _EnStrings {
  const _PtStrings() : super('pt');

  static String _n(int n, String one, String many) => n.abs() == 1 ? one : many;

  // ── Списки дат ──────────────────────────────────────────────────────────

  @override
  List<String> get shortMonths => const [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  @override
  List<String> get monthAbbrev => shortMonths;

  @override
  List<String> get cycleMonthsGenitive => shortMonths;

  /// Первый элемент пустой: индексация по номеру месяца (1–12).
  @override
  List<String> get fullMonths => const [
    '',
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  @override
  List<String> get cycleMonthNames => const [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  @override
  List<String> get shortWeekdays => const [
    'seg',
    'ter',
    'qua',
    'qui',
    'sex',
    'sáb',
    'dom',
  ];

  @override
  List<String> get cycleWeekdayShorts => const [
    'se',
    'te',
    'qa',
    'qi',
    'sx',
    'sá',
    'do',
  ];

  @override
  List<String> get shortWeekdaysUpper => const [
    'SEG',
    'TER',
    'QUA',
    'QUI',
    'SEX',
    'SÁB',
    'DOM',
  ];

  /// Quarta и quinta начинаются одинаково, sábado с segunda — тоже: в узкой
  /// сетке календаря места на два знака нет, поэтому буквы повторяются.
  @override
  List<String> get shortWeekdaysSingleChar => const [
    'S',
    'T',
    'Q',
    'Q',
    'S',
    'S',
    'D',
  ];

  @override
  List<String> get longWeekdays => const [
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];

  @override
  List<String> get reflectionQuestions => const [
    'O que seu par fez hoje que te fez bem?',
    'Qual momento com seu par te fez sorrir hoje?',
    'O que você admira no seu par agora?',
    'Pelo que você é grato hoje na relação de vocês?',
    'Qual lembrança com seu par volta sempre à sua cabeça?',
    'Com o que seu par te surpreendeu ultimamente?',
    'O que torna seu par especial para você?',
    'Como seu par te apoiou hoje?',
    'O que você quer dizer hoje ao seu par?',
    'Que aventura você gostaria de viver com seu par?',
    'Qual música te lembra do seu par e por quê?',
    'Qual é a melhor coisa de estar com seu par?',
    'Qual gesto pequeno do seu par te tocou mais nos últimos dias?',
    'O que você descobriu de novo sobre seu par?',
    'O que te dá medo quando você pensa no futuro de vocês?',
    'O que vocês querem realizar juntos nos próximos meses?',
    'Quando você se sentiu de verdade compreendido pela última vez?',
    'O que está faltando e vocês ainda não conversaram sobre isso?',
    'Qual hábito do seu par você gosta mais?',
    'O que você contaria hoje para o primeiro dia de vocês juntos?',
  ];

  // ── Ошибки и вход ───────────────────────────────────────────────────────

  @override
  String loginError(String e) => 'Erro ao entrar: $e';

  @override
  String googleLoginError(String e) => 'Erro ao entrar com o Google: $e';

  @override
  String registrationError(String e) => 'Erro no cadastro: $e';

  @override
  String passwordResetSent(String email) =>
      'Enviamos um e-mail de redefinição para $email. '
      'Confira também a caixa de spam.';

  @override
  String genericError(String e) => 'Erro: $e';

  @override
  String uploadError(String e) => 'Erro ao enviar: $e';

  @override
  String failedToSave(Object e) => 'Não foi possível salvar: $e';

  @override
  String exportError(String e) => 'Erro durante a exportação: $e';

  @override
  String downloadFailed(String e) => 'O download falhou: $e';

  @override
  String failedSelectPhotos(String e) =>
      'Não foi possível escolher as fotos: $e';

  @override
  String failedSelectVideo(String e) => 'Não foi possível escolher o vídeo: $e';

  @override
  String failedAddMemory(String e) =>
      'Não foi possível adicionar a lembrança: $e';

  @override
  String failedAddWidget(String e) => 'Não foi possível adicionar o widget: $e';

  @override
  String failedSetStatus(String e) => 'Não foi possível definir o status: $e';

  @override
  String failedClearStatus(String e) => 'Não foi possível tirar o status: $e';

  @override
  String failedAddStatus(String e) => 'Não foi possível adicionar o status: $e';

  @override
  String failedUpdateStatus(String e) => 'Não foi possível mudar o status: $e';

  @override
  String failedDeleteStatus(String e) =>
      'Não foi possível excluir o status: $e';

  // ── Главная, таймеры, счётчики ──────────────────────────────────────────

  @override
  String daysLabel(String suffix) => 'DIAS $suffix';

  @override
  String monthsLabel(String suffix) => 'MESES $suffix';

  @override
  String timeLabel(String suffix) => 'TEMPO $suffix';

  @override
  String daysTogetherLabel(String days) => '$days dias';

  @override
  String yearsAlready(int years) =>
      years == 1 ? 'Já um ano ❤️' : 'Já $years anos ❤️';

  @override
  String timerDaysCount(int days) => '$days ${_n(days, 'dia', 'dias')}';

  @override
  String timerDeleteConfirm(String name) => '«$name» vai sumir para sempre.';

  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';

  @override
  String daysTogetherNotifBody(int days) =>
      'Vocês estão juntos há $days ${_n(days, 'dia', 'dias')} ❤️';

  @override
  String streakLabel(int days) => 'Sequência: $days ${_n(days, 'dia', 'dias')}';

  @override
  String recordStreakDays(int days) => 'Recorde: $days d.';

  @override
  String recordStreakBadge(int days) => '$days d.';

  // ── Настроение и самочувствие ───────────────────────────────────────────

  @override
  String partnerIsMood(String name, String mood) => '$name: $mood';

  @override
  String partnerMood(String name) => 'Humor de $name';

  @override
  String moodDateLabel(String dateLabel) => 'Humor — $dateLabel';

  @override
  String moodRecorded(String label) => '$label anotado!';

  @override
  String moodPackAuthor(String name) => 'Desenhos de $name';

  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name não está bem: $label';

  @override
  String moodNotifTitle(String name) => '$name mudou de humor';

  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score de $max';

  @override
  String statsMoodMarks(int n) => 'Registros em 30 dias: $n';

  // ── Достижения и капсула ────────────────────────────────────────────────

  @override
  String achProgressOf(int value, int target) => '$value de $target';

  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      '$unlocked de $total conquistados';

  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'abre hoje' : 'em $days ${_n(days, 'dia', 'dias')}';

  @override
  String capsuleOpensOn(String date) => 'Abre em $date';

  @override
  String capsuleFrom(String name) => 'de $name';

  @override
  String capsuleNotReady(String date) => 'Ainda não 🙈 Abre em $date';

  @override
  String capsuleOpenedBodyNamed(String title) =>
      '«$title» espera por você no mural';

  // ── Монеты, покупки, Togetherly+ ────────────────────────────────────────

  @override
  String premiumThemeLocked(int price) =>
      'Tema pago — $price moedas, desbloqueie na loja';

  @override
  String buyThemeDescription(String themeName, int price) =>
      'Desbloquear o tema «$themeName» por $price moedas?';

  @override
  String coinPackTitle(int coins) => '$coins moedas';

  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins moedas creditadas';

  @override
  String coinEarned(int amount) => '+$amount moedas ganhas!';

  @override
  String coinsPlus(int n) => '+$n ${_n(n, 'moeda', 'moedas')}';

  @override
  String unlockForCoins(int price) => 'Desbloquear — $price 🪙';

  @override
  String notEnoughCoinsNeed(int price) =>
      'Moedas insuficientes — faltam $price 🪙';

  @override
  String redeemCodeDone(int coins) => '$coins moedas creditadas';

  @override
  String supportCopied(String email) => 'Endereço copiado: $email';

  // ── Группа, приглашения, связь ──────────────────────────────────────────

  @override
  String groupOf(int count) => 'Grupo de $count';

  @override
  String membersCount(int count) => 'MEMBROS · $count';

  @override
  String membersCountBracket(int count) => 'MEMBROS ($count)';

  @override
  String membersOfMax(int current, int max) => '$current/$max membros';

  @override
  String shareInviteText(String code, String link) =>
      'Venha para o Togetherly comigo! Código: $code\n\nOu clique aqui: $link';

  @override
  String shareGroupInviteText(String code, String link) =>
      'Entre no nosso grupo no Togetherly! Código: $code\n\n'
      'Ou clique aqui: $link';

  @override
  String joinMeLinkText(String link) => 'Venha para o Togetherly comigo! $link';

  @override
  String connectedWithCouple(String name) => 'Agora você está com $name!';

  @override
  String marriedTo(String name) => 'Você é casado com $name! 💍';

  @override
  String friendsWith(String name) => 'Agora você é amigo de $name!';

  @override
  String buddiesWith(String name) => '$name e você, melhores amigos!';

  @override
  String customRelWith(String label, String name) =>
      'Agora você é $label com $name!';

  @override
  String onboardingLeft(int left) =>
      left == 1 ? 'Falta um passo' : 'Faltam $left passos';

  @override
  String onboardingNext(String step) => 'Falta um passo: $step';

  @override
  String quietPartnerTitle(String name, int days) => days == 1
      ? '$name não aparece há um dia'
      : '$name não aparece há $days dias';

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return '$n ${_n(n, 'dia', 'dias')}';
  }

  // ── Чат ─────────────────────────────────────────────────────────────────

  @override
  String chatReplyingTo(String name) => 'Resposta para $name';

  @override
  String chatTyping(String name) => '$name está escrevendo…';

  @override
  String chatNotifTitle(String name) => '$name te escreveu 💬';

  @override
  String chatDeleteConfirm(String text) => 'Excluir esta mensagem?';

  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    // Первое число месяца — «1º», остальные обычные.
    final dayLabel = day.day == 1 ? '1º' : '${day.day}';
    final base = '$dayLabel de ${cycleMonthNames[day.month - 1]}';
    return day.year == now.year ? base : '$base de ${day.year}';
  }

  @override
  String chatBgConfirmBody(int price) =>
      'Colocar sua foto como fundo do chat por $price 🪙?\n\n'
      'Cada troca seguinte também vai custar $price 🪙.';

  // ── Воспоминания и медиа ────────────────────────────────────────────────

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Foto',
    'video' => 'Vídeo',
    'location' => 'Lugar',
    'music' => 'Música',
    'text' => 'Nota',
    'videoLink' => 'Link de vídeo',
    'book' => 'Livro',
    _ => 'Filme',
  };

  @override
  String newMemory(String type) => 'Novo: $type';

  @override
  String memoriesUnit(int n) => _n(n, 'lembrança', 'lembranças');

  @override
  String savedToPath(String path) => 'Salvo em $path';

  @override
  String nPhotos(int count) => '$count fotos';

  @override
  String openIn(String name) => 'Abrir no $name';

  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '${day == 1 ? '1º' : day} de $month de $year às $time';

  @override
  String memoryFileTooBig(int limitMb) =>
      'O arquivo passa de $limitMb MB — não vai subir';

  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'O arquivo passa de $limitMb MB. O Togetherly+ dobra o limite';

  @override
  String selectedCount(int n) => '$n selecionados';

  @override
  String itemsShort(int n) => '$n itens';

  @override
  String kpRating(String rating) => 'KP $rating';

  @override
  String yearRange(int first, int last) => 'Ano de $first a $last';

  // ── Статус и профиль ────────────────────────────────────────────────────

  @override
  String statusSetTo(String status) => 'Status definido: $status';

  @override
  String deleteStatusConfirm(String label) => 'Excluir «$label» para sempre?';

  @override
  String widgetOfPartner(String name) => 'Widget de $name';

  @override
  String symbolSearchFound(int count) => 'Encontrados: $count';

  // ── Уведомления «скучаю» и импульсы ─────────────────────────────────────

  @override
  String missYouNotifTitle(String name) => '$name está com saudade';

  @override
  String missYouStreak(int count) => '🔥 $count';

  @override
  String thinkingOfYouNotifTitle(String name) => '$name pensa em você 💭';

  @override
  String wantHugNotifTitle(String name) => '$name quer te abraçar 🤗';

  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карта и расстояния ──────────────────────────────────────────────────

  @override
  String kmFromYou(String km) => '$km de você';

  @override
  String minutesAgo(int m) => 'há $m min';

  @override
  String hoursAgo(int h) => 'há $h h';

  @override
  String daysAgo(int d) => 'há $d d';

  @override
  String liveLocationAgo(String value) => 'há $value';

  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  // ── Рисование и холсты ──────────────────────────────────────────────────

  @override
  String partnerIsDrawing(String name) => '$name está desenhando…';

  @override
  String drawingSavedTo(String path) => 'Desenho salvo: $path';

  @override
  String drawLayerName(int index) => 'Camada $index';

  @override
  String drawLayerStrokes(int count) =>
      count == 0 ? 'vazia' : '$count ${_n(count, 'traço', 'traços')}';

  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Liso',
    'grid' => 'Grade',
    'dots' => 'Pontos',
    'notebook' => 'Caderno',
    'millimeter' => 'Papel milimetrado',
    'kraft' => 'Kraft',
    'chalkboard' => 'Lousa',
    'music' => 'Partitura',
    'stars' => 'Estrelas',
    'hearts' => 'Corações',
    'watercolor' => 'Aquarela',
    'film' => 'Filme',
    _ => id,
  };

  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count ${_n(count, 'desenho', 'desenhos')} · último $lastDate';

  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells quadradinhos · $px px por pixel na exportação';

  @override
  String deleteCanvasesTitle(int n) =>
      n == 1 ? 'Excluir a tela?' : 'Excluir $n telas?';

  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'O desenho vai sumir para vocês dois. Não tem volta.'
      : 'Os desenhos vão sumir para vocês dois. Não tem volta.';

  @override
  String coloringPartnerColoring(String name) => '$name está colorindo';

  @override
  String coloringWaitingHint(String name) =>
      'abrimos assim que $name tocar em Pronto';

  // ── Виджеты ─────────────────────────────────────────────────────────────

  @override
  String tgDaysTogetherCaption(int days) =>
      _n(days, 'dia juntos', 'dias juntos');

  @override
  String tgMonthsCaption(int months) => _n(months, 'mês', 'meses');

  @override
  String tgDaysMilestone(int days) => '$days ${_n(days, 'dia', 'dias')}';

  @override
  String tgYearsMilestone(int years) => '$years ${_n(years, 'ano', 'anos')}';

  @override
  String tgInDays(int days) => 'em $days ${_n(days, 'dia', 'dias')}';

  @override
  String tgUntilMilestone(int target, int left) =>
      'Até ${tgDaysMilestone(target)} — ${tgInDays(left)}';

  @override
  String tgMissAddressee(String name) => 'Para $name';

  @override
  String tgMoodMatched(int days) => '$days de 7 iguais';

  @override
  String tgCountdownDaysLeft(int days) =>
      '${_n(days, 'dia', 'dias')} até o reencontro';

  @override
  String tgYearDaysWord(int days) => _n(days, 'Dia', 'Dias');

  @override
  String tgYearDaysTogether(int days) => '${_n(days, 'Dia', 'Dias')} juntos';

  @override
  String tgYearDaysLeft(int days) =>
      '$days ${_n(days, 'dia', 'dias')} restantes';

  @override
  String tgYearToAnniversary(int year) => 'Até o ano $year';

  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'Até o ano $year — $days';

  @override
  String tgYearCurrentYearShort(int year, int days) =>
      'Ano $year · $days restantes';

  @override
  String tgYearOrdinalLabel(int year) => '$yearº ANO JUNTOS';

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${_n(years, 'ANO', 'ANOS')} '
      '$days ${_n(days, 'DIA', 'DIAS')}';

  @override
  String tgYearSince(String date) => 'Desde $date';

  @override
  String photosUnit(int n) => _n(n, 'foto', 'fotos');

  @override
  String photoCountOnUnlock(int count) => '$count fotos · ao desbloquear';

  @override
  String photoCountInterval(int count, String interval) =>
      '$count fotos · $interval';

  @override
  String photoCountCarousel(int count) => '$count fotos · carrossel';

  @override
  String photoNumber(int n) => 'Foto $n';

  @override
  String positionNumber(int n) => 'Posição $n';

  @override
  String selectUpToPhotos(int n) => 'Escolha até $n ${photosUnit(n)}';

  @override
  String addWithCount(int n) => 'Adicionar ($n)';

  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'a cada 15 min';
      case 30:
        return 'a cada 30 min';
      case 60:
        return 'a cada hora';
      case 180:
        return 'a cada 3 horas';
      default:
        return 'a cada $minutes min';
    }
  }

  @override
  String personalPhotosHelp(String partner) =>
      'Fotos pessoais — de 1 a 10 por widget. Com duas ou mais começa um '
      'carrossel: troca ao desbloquear ou por tempo.\n\nSó você vê essas fotos. '
      'Para compartilhar com $partner, abra «Foto do par» → «Escolher fotos '
      'para o par».';

  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Este widget mostra as fotos que $partner compartilhou '
      '($count ${photosUnit(count)}). Só $partner pode trocá-las.';

  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner ainda não compartilhou fotos. Para aparecerem aqui, $partner '
      'precisa abrir «Foto do par» e tocar em «Escolher fotos para o par» — o '
      'widget «Foto» comum só o dono vê.';

  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner vê $count das suas ${photosUnit(count)}';

  @override
  String partnerSharedCountHelp(int count) =>
      'Seu par compartilhou $count fotos — escolha como elas se alternam neste '
      'widget.';

  @override
  String captionDestPairWidgetSub(String partner) =>
      'Foto em «Meu widget» — você e $partner veem';

  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Um widget separado com uma foto para $partner';

  // ── Маскоты ─────────────────────────────────────────────────────────────

  @override
  String mascotDeactivated(String name) => '$name está desativada';

  @override
  String mascotActivated(String name) => '$name agora está ativa';

  @override
  String deleteMascotBody(String name) => '«$name» será excluída para sempre.';

  @override
  String mascotsCount(int count, int max) => '$count / $max mascotes';

  @override
  String mascotSleepRange(String from, String to) => 'Dorme das $from às $to';

  @override
  String mascotNightRange(String from, String to) => 'Brilha das $from às $to';

  // ── Цикл ────────────────────────────────────────────────────────────────

  @override
  String cycleOf(String name) => 'Ciclo de $name';

  @override
  String cycleDaysLeft(int days) => 'Em $days ${_n(days, 'dia', 'dias')}';

  @override
  String cycleDayOfCycle(int day) => 'Dia $day do ciclo';

  @override
  String cycleOverdue(int days) => '$days ${_n(days, 'dia', 'dias')} de atraso';

  @override
  String cycleAnalyticsHint(int cycles) =>
      'nos últimos $cycles ${_n(cycles, 'ciclo', 'ciclos')}';

  @override
  String cycleDaysValue(int days) => '$days ${_n(days, 'dia', 'dias')}';

  @override
  String cyclePeriodDayLabel(int day) => 'menstruação, dia $day';

  @override
  String dayLogDate(DateTime day) =>
      '${day.day == 1 ? '1º' : day.day} ${cycleMonthsGenitive[day.month - 1]}';

  @override
  String dayLogWeekday(DateTime day) => longWeekdays[day.weekday - 1];

  // ── Открытки ────────────────────────────────────────────────────────────

  @override
  String pcReceiptShift(int days) => 'turno nº $days';

  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Lembranças — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Desenhos — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('Saudade — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Dias seguidos — ${stats.streak}');
    if (lines.isEmpty) lines.add('Está só começando — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'De: ${from.isEmpty ? 'mim' : from}\n'
      'Conteúdo: $days dias, tudo intacto';

  // ── Подарки ─────────────────────────────────────────────────────────────

  @override
  String giftFromPartner(String name) => 'Um presente de $name';

  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? 'Ele escapou!' : 'Escapou de novo, pega!';

  @override
  String giftIncomingCount(int n) => n == 1 ? 'está esperando' : '$n esperando';

  @override
  String giftMutualBonus(int coins) => 'Na hora certa: $coins para cada um';

  @override
  String giftSunriseGreeting(String name) =>
      'Bom dia! $name te mandou um nascer do sol';

  @override
  String giftPushBody(String giftName) => 'Te mandou um presente: $giftName';

  // ── Профиль партнёра и статистика ───────────────────────────────────────

  @override
  String partnerGiftsChip(int count) => '$count';

  @override
  String partnerMissChip(int count) => '$count';

  @override
  String partnerDaysTogether(int days) =>
      'juntos há $days ${_n(days, 'dia', 'dias')}';

  @override
  String partnerMissPeak(String weekday) => 'Mais na $weekday';

  @override
  String weekdayShort(int weekday) => shortWeekdays[weekday - 1];

  /// «Mais na segunda» — предлог стоит в самой фразе, поэтому здесь короткая
  /// разговорная форма без «-feira»: полное название сделало бы строку вдвое
  /// длиннее и не влезло бы в карточку.
  @override
  String weekdayLong(int weekday) => const [
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ][weekday - 1];

  // ── Совместный просмотр ─────────────────────────────────────────────────

  @override
  String watchWithPartner(String name) => 'Assistir com $name';

  @override
  String watchVideoAdd(int mb) => 'Envie até $mb MB';

  @override
  String watchVideoTooBig(int mb) =>
      'O vídeo passa de $mb MB: comprima ou escolha um mais curto';

  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName te convida para assistir junto';
}
