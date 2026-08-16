part of 'locale_service.dart';

/// Испанский: то, что словарём не выражается.
///
/// Простые строки берутся из `kStrings` по коду `es` (`lib/l10n/dict/`), здесь
/// остаются подстановки, числительные и списки дат.
///
/// Отличие от французского: ноль требует множественного числа («0 días»,
/// «1 día», «2 días»), поэтому порог здесь `== 1`, а не `<= 1`. Вопросы и
/// восклицания обрамляются с двух сторон (¿…?, ¡…!), месяцы и дни недели
/// пишутся со строчной — это норма языка, а не описка.
class _EsStrings extends _EnStrings {
  const _EsStrings() : super('es');

  /// Единственное число только при единице: «0 días», но «1 día».
  static String _n(int n, String one, String many) => n.abs() == 1 ? one : many;

  // ── Списки дат ──────────────────────────────────────────────────────────

  @override
  List<String> get shortMonths => const [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sept',
    'oct',
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
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  @override
  List<String> get cycleMonthNames => const [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  @override
  List<String> get shortWeekdays => const [
    'lun',
    'mar',
    'mié',
    'jue',
    'vie',
    'sáb',
    'dom',
  ];

  @override
  List<String> get cycleWeekdayShorts => const [
    'lu',
    'ma',
    'mi',
    'ju',
    'vi',
    'sá',
    'do',
  ];

  @override
  List<String> get shortWeekdaysUpper => const [
    'LUN',
    'MAR',
    'MIÉ',
    'JUE',
    'VIE',
    'SÁB',
    'DOM',
  ];

  /// Martes и miércoles начинаются одинаково, jueves — на J: в узкой сетке
  /// календаря места на два знака нет, поэтому буквы повторяются.
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
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  @override
  List<String> get reflectionQuestions => const [
    '¿Qué hizo hoy tu pareja que te hizo sentir bien?',
    '¿Qué momento con tu pareja te hizo sonreír hoy?',
    '¿Qué admiras de tu pareja ahora mismo?',
    '¿Por qué estás agradecido hoy en vuestra relación?',
    '¿Qué recuerdo con tu pareja vuelve una y otra vez?',
    '¿Con qué te sorprendió tu pareja hace poco?',
    '¿Qué hace única a tu pareja para ti?',
    '¿Cómo te apoyó tu pareja hoy?',
    '¿Qué quieres decirle hoy a tu pareja?',
    '¿Qué aventura te gustaría vivir con tu pareja?',
    '¿Qué canción te recuerda a tu pareja y por qué?',
    '¿Qué es lo mejor de estar con tu pareja?',
    '¿Qué pequeño detalle de tu pareja te llegó más últimamente?',
    '¿Qué has aprendido nuevo sobre tu pareja?',
    '¿Qué te da miedo cuando piensas en vuestro futuro?',
    '¿Qué queréis conseguir juntos en los próximos meses?',
    '¿Cuándo te sentiste de verdad comprendido por última vez?',
    '¿Qué te falta y aún no habéis hablado de ello?',
    '¿Qué costumbre de tu pareja te gusta especialmente?',
    '¿Qué le contarías hoy a vuestro primer día juntos?',
  ];

  // ── Ошибки и вход ───────────────────────────────────────────────────────

  @override
  String loginError(String e) => 'Error al iniciar sesión: $e';

  @override
  String googleLoginError(String e) => 'Error de acceso con Google: $e';

  @override
  String registrationError(String e) => 'Error al registrarse: $e';

  @override
  String passwordResetSent(String email) =>
      'Hemos enviado un correo de restablecimiento a $email. '
      'Mira también en la carpeta de spam.';

  @override
  String genericError(String e) => 'Error: $e';

  @override
  String uploadError(String e) => 'Error al subir: $e';

  @override
  String failedToSave(Object e) => 'No se pudo guardar: $e';

  @override
  String exportError(String e) => 'Error durante la exportación: $e';

  @override
  String downloadFailed(String e) => 'La descarga falló: $e';

  @override
  String failedSelectPhotos(String e) => 'No se pudieron elegir las fotos: $e';

  @override
  String failedSelectVideo(String e) => 'No se pudo elegir el vídeo: $e';

  @override
  String failedAddMemory(String e) => 'No se pudo añadir el recuerdo: $e';

  @override
  String failedAddWidget(String e) => 'No se pudo añadir el widget: $e';

  @override
  String failedSetStatus(String e) => 'No se pudo poner el estado: $e';

  @override
  String failedClearStatus(String e) => 'No se pudo quitar el estado: $e';

  @override
  String failedAddStatus(String e) => 'No se pudo añadir el estado: $e';

  @override
  String failedUpdateStatus(String e) => 'No se pudo cambiar el estado: $e';

  @override
  String failedDeleteStatus(String e) => 'No se pudo borrar el estado: $e';

  // ── Главная, таймеры, счётчики ──────────────────────────────────────────

  @override
  String daysLabel(String suffix) => 'DÍAS $suffix';

  @override
  String monthsLabel(String suffix) => 'MESES $suffix';

  @override
  String timeLabel(String suffix) => 'TIEMPO $suffix';

  @override
  String daysTogetherLabel(String days) => '$days días';

  @override
  String yearsAlready(int years) =>
      years == 1 ? '¡Ya un año ❤️' : '¡Ya $years años ❤️';

  @override
  String monthsAlready(int months) =>
      months == 1 ? '¡Ya un mes ❤️' : '¡Ya $months meses ❤️';

  @override
  String timerDaysCount(int days) => '$days ${_n(days, 'día', 'días')}';

  @override
  String timerDeleteConfirm(String name) =>
      '«$name» desaparecerá para siempre.';

  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';

  @override
  String daysTogetherNotifBody(int days) =>
      'Llevas $days ${_n(days, 'día', 'días')} juntos ❤️';

  @override
  String streakLabel(int days) => 'Racha: $days ${_n(days, 'día', 'días')}';

  @override
  String recordStreakDays(int days) => 'Récord: $days d.';

  @override
  String recordStreakBadge(int days) => '$days d.';

  // ── Настроение и самочувствие ───────────────────────────────────────────

  @override
  String partnerIsMood(String name, String mood) => '$name: $mood';

  @override
  String partnerMood(String name) => 'Ánimo de $name';

  @override
  String moodDateLabel(String dateLabel) => 'Ánimo — $dateLabel';

  @override
  String moodRecorded(String label) => '¡$label anotado!';

  @override
  String moodPackAuthor(String name) => 'Dibujos de $name';

  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name no está bien: $label';

  @override
  String moodNotifTitle(String name) => '$name cambió su ánimo';

  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score de $max';

  @override
  String statsMoodMarks(int n) => 'Registros en 30 días: $n';

  // ── Достижения и капсула ────────────────────────────────────────────────

  @override
  String achProgressOf(int value, int target) => '$value de $target';

  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      '$unlocked de $total conseguidos';

  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'se abre hoy' : 'en $days ${_n(days, 'día', 'días')}';

  @override
  String capsuleOpensOn(String date) => 'Se abre el $date';

  @override
  String capsuleFrom(String name) => 'de $name';

  @override
  String capsuleNotReady(String date) => 'Aún no 🙈 Se abre el $date';

  @override
  String capsuleOpenedBodyNamed(String title) =>
      '«$title» te espera en el muro';

  // ── Монеты, покупки, Togetherly+ ────────────────────────────────────────

  @override
  String premiumThemeLocked(int price) =>
      'Tema de pago — $price monedas, desbloquéalo en la tienda';

  @override
  String buyThemeDescription(String themeName, int price) =>
      '¿Desbloquear el tema «$themeName» por $price monedas?';

  @override
  String coinPackTitle(int coins) => '$coins monedas';

  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins monedas abonadas';

  @override
  String coinEarned(int amount) => '¡+$amount monedas ganadas!';

  @override
  String coinsPlus(int n) => '+$n ${_n(n, 'moneda', 'monedas')}';

  @override
  String unlockForCoins(int price) => 'Desbloquear — $price 🪙';

  @override
  String notEnoughCoinsNeed(int price) =>
      'No hay monedas suficientes — hacen falta $price 🪙';

  @override
  String redeemCodeDone(int coins) => '$coins monedas abonadas';

  @override
  String supportCopied(String email) => 'Dirección copiada: $email';

  // ── Группа, приглашения, связь ──────────────────────────────────────────

  @override
  String groupOf(int count) => 'Grupo de $count';

  @override
  String membersCount(int count) => 'MIEMBROS · $count';

  @override
  String membersCountBracket(int count) => 'MIEMBROS ($count)';

  @override
  String membersOfMax(int current, int max) => '$current/$max miembros';

  @override
  String shareInviteText(String code, String link) =>
      '¡Únete a mí en Togetherly! Código: $code\n\nO pulsa aquí: $link';

  @override
  String shareGroupInviteText(String code, String link) =>
      '¡Únete a nuestro grupo en Togetherly! Código: $code\n\n'
      'O pulsa aquí: $link';

  @override
  String joinMeLinkText(String link) => '¡Únete a mí en Togetherly! $link';

  @override
  String connectedWithCouple(String name) => '¡Ya estás unido a $name!';

  @override
  String marriedTo(String name) => '¡Estás casado con $name! 💍';

  @override
  String friendsWith(String name) => '¡Ya eres amigo de $name!';

  @override
  String buddiesWith(String name) => '¡$name y tú, mejores amigos!';

  @override
  String customRelWith(String label, String name) =>
      '¡Ya eres $label con $name!';

  @override
  String onboardingLeft(int left) =>
      left == 1 ? 'Queda un paso' : 'Quedan $left pasos';

  @override
  String onboardingNext(String step) => 'Queda un paso: $step';

  @override
  String quietPartnerTitle(String name, int days) => days == 1
      ? '$name no aparece desde ayer'
      : '$name no aparece desde hace $days días';

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return '$n ${_n(n, 'día', 'días')}';
  }

  // ── Чат ─────────────────────────────────────────────────────────────────

  @override
  String chatReplyingTo(String name) => 'Respuesta a $name';

  @override
  String chatTyping(String name) => '$name está escribiendo…';

  @override
  String chatNotifTitle(String name) => '$name te escribe 💬';

  @override
  String chatDeleteConfirm(String text) => '¿Borrar este mensaje?';

  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    final base = '${day.day} de ${cycleMonthNames[day.month - 1]}';
    return day.year == now.year ? base : '$base de ${day.year}';
  }

  @override
  String chatBgConfirmBody(int price) =>
      '¿Poner tu foto como fondo del chat por $price 🪙?\n\n'
      'Cada cambio siguiente costará también $price 🪙.';

  // ── Воспоминания и медиа ────────────────────────────────────────────────

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Foto',
    'video' => 'Vídeo',
    'location' => 'Lugar',
    'music' => 'Música',
    'text' => 'Nota',
    'videoLink' => 'Enlace de vídeo',
    'book' => 'Libro',
    _ => 'Película',
  };

  @override
  String newMemory(String type) => 'Nuevo: $type';

  @override
  String memoriesUnit(int n) => _n(n, 'recuerdo', 'recuerdos');

  @override
  String savedToPath(String path) => 'Guardado en $path';

  @override
  String nPhotos(int count) => '$count fotos';

  @override
  String openIn(String name) => 'Abrir en $name';

  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '$day de $month de $year a las $time';

  @override
  String memoryFileTooBig(int limitMb) =>
      'El archivo pasa de $limitMb MB — no se subirá';

  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'El archivo pasa de $limitMb MB. Togetherly+ dobla el límite';

  @override
  String selectedCount(int n) => '$n seleccionados';

  @override
  String itemsShort(int n) => '$n elementos';

  @override
  String kpRating(String rating) => 'KP $rating';

  @override
  String yearRange(int first, int last) => 'Año de $first a $last';

  // ── Статус и профиль ────────────────────────────────────────────────────

  @override
  String statusSetTo(String status) => 'Estado puesto: $status';

  @override
  String deleteStatusConfirm(String label) => '¿Borrar «$label» para siempre?';

  @override
  String widgetOfPartner(String name) => 'Widget de $name';

  @override
  String symbolSearchFound(int count) => 'Encontrados: $count';

  // ── Уведомления «скучаю» и импульсы ─────────────────────────────────────

  @override
  String missYouNotifTitle(String name) => '$name te echa de menos';

  @override
  String missYouStreak(int count) => '🔥 $count';

  @override
  String thinkingOfYouNotifTitle(String name) => '$name piensa en ti 💭';

  @override
  String wantHugNotifTitle(String name) => '$name quiere abrazarte 🤗';

  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карта и расстояния ──────────────────────────────────────────────────

  @override
  String kmFromYou(String km) => '$km de ti';

  @override
  String minutesAgo(int m) => 'hace $m min';

  @override
  String hoursAgo(int h) => 'hace $h h';

  @override
  String daysAgo(int d) => 'hace $d d';

  @override
  String liveLocationAgo(String value) => 'hace $value';

  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  // ── Рисование и холсты ──────────────────────────────────────────────────

  @override
  String partnerIsDrawing(String name) => '$name está dibujando…';

  @override
  String drawingSavedTo(String path) => 'Dibujo guardado: $path';

  @override
  String drawLayerName(int index) => 'Capa $index';

  @override
  String drawLayerStrokes(int count) =>
      count == 0 ? 'vacía' : '$count ${_n(count, 'trazo', 'trazos')}';

  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Liso',
    'grid' => 'Cuadrícula',
    'dots' => 'Puntos',
    'notebook' => 'Cuaderno',
    'millimeter' => 'Papel milimetrado',
    'kraft' => 'Kraft',
    'chalkboard' => 'Pizarra',
    'music' => 'Partitura',
    'stars' => 'Estrellas',
    'hearts' => 'Corazones',
    'watercolor' => 'Acuarela',
    'film' => 'Película',
    _ => id,
  };

  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count ${_n(count, 'dibujo', 'dibujos')} · último $lastDate';

  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells casillas · $px px por píxel al exportar';

  @override
  String deleteCanvasesTitle(int n) =>
      n == 1 ? '¿Borrar el lienzo?' : '¿Borrar $n lienzos?';

  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'El dibujo desaparecerá para los dos. No hay vuelta atrás.'
      : 'Los dibujos desaparecerán para los dos. No hay vuelta atrás.';

  @override
  String coloringPartnerColoring(String name) => '$name está coloreando';

  @override
  String coloringWaitingHint(String name) =>
      'lo abrimos en cuanto $name pulse Listo';

  // ── Виджеты ─────────────────────────────────────────────────────────────

  @override
  String tgDaysTogetherCaption(int days) =>
      _n(days, 'día juntos', 'días juntos');

  @override
  String tgMonthsCaption(int months) => _n(months, 'mes', 'meses');

  @override
  String tgDaysMilestone(int days) => '$days ${_n(days, 'día', 'días')}';

  @override
  String tgYearsMilestone(int years) => '$years ${_n(years, 'año', 'años')}';

  @override
  String tgInDays(int days) => 'en $days ${_n(days, 'día', 'días')}';

  @override
  String tgUntilMilestone(int target, int left) =>
      'Hasta ${tgDaysMilestone(target)} — ${tgInDays(left)}';

  @override
  String tgMissAddressee(String name) => 'Para $name';

  @override
  String tgMoodMatched(int days) => '$days de 7 iguales';

  @override
  String tgCountdownDaysLeft(int days) =>
      '${_n(days, 'día', 'días')} para vernos';

  @override
  String tgYearDaysWord(int days) => _n(days, 'Día', 'Días');

  @override
  String tgYearDaysTogether(int days) => '${_n(days, 'Día', 'Días')} juntos';

  @override
  String tgYearDaysLeft(int days) =>
      '$days ${_n(days, 'día', 'días')} restantes';

  @override
  String tgYearToAnniversary(int year) => 'Hasta el año $year';

  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'Hasta el año $year — $days';

  @override
  String tgYearCurrentYearShort(int year, int days) =>
      'Año $year · $days restantes';

  @override
  String tgYearOrdinalLabel(int year) => 'AÑO $year JUNTOS';

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${_n(years, 'AÑO', 'AÑOS')} '
      '$days ${_n(days, 'DÍA', 'DÍAS')}';

  @override
  String tgYearSince(String date) => 'Desde $date';

  @override
  String photosUnit(int n) => _n(n, 'foto', 'fotos');

  @override
  String photoCountOnUnlock(int count) => '$count fotos · al desbloquear';

  @override
  String photoCountInterval(int count, String interval) =>
      '$count fotos · $interval';

  @override
  String photoCountCarousel(int count) => '$count fotos · carrusel';

  @override
  String photoNumber(int n) => 'Foto $n';

  @override
  String positionNumber(int n) => 'Posición $n';

  @override
  String selectUpToPhotos(int n) => 'Elige hasta $n ${photosUnit(n)}';

  @override
  String addWithCount(int n) => 'Añadir ($n)';

  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'cada 15 min';
      case 30:
        return 'cada 30 min';
      case 60:
        return 'cada hora';
      case 180:
        return 'cada 3 horas';
      default:
        return 'cada $minutes min';
    }
  }

  @override
  String personalPhotosHelp(String partner) =>
      'Fotos personales — de 1 a 10 por widget. Con dos o más arranca un '
      'carrusel: cambia al desbloquear o por temporizador.\n\nEstas fotos solo '
      'las ves tú. Para compartirlas con $partner, abre «Foto de la pareja» → '
      '«Elegir fotos para la pareja».';

  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Este widget muestra las fotos que compartió $partner '
      '($count ${photosUnit(count)}). Solo $partner puede cambiarlas.';

  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner aún no ha compartido fotos. Para que aparezcan aquí, $partner '
      'tiene que abrir «Foto de la pareja» y pulsar «Elegir fotos para la '
      'pareja» — el widget «Foto» normal solo lo ve su dueño.';

  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner ve $count de tus ${photosUnit(count)}';

  @override
  String partnerSharedCountHelp(int count) =>
      'Tu pareja compartió $count fotos — elige cómo van cambiando en este '
      'widget.';

  @override
  String captionDestPairWidgetSub(String partner) =>
      'Foto en «Mi widget» — la veis tú y $partner';

  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Un widget aparte con una foto para $partner';

  // ── Маскоты ─────────────────────────────────────────────────────────────

  @override
  String mascotDeactivated(String name) => '$name está desactivada';

  @override
  String mascotActivated(String name) => '$name ya está activa';

  @override
  String deleteMascotBody(String name) => '«$name» se borrará para siempre.';

  @override
  String mascotsCount(int count, int max) => '$count / $max mascotas';

  @override
  String mascotSleepRange(String from, String to) => 'Duerme de $from a $to';

  @override
  String mascotNightRange(String from, String to) => 'Brilla de $from a $to';

  // ── Цикл ────────────────────────────────────────────────────────────────

  @override
  String cycleOf(String name) => 'Ciclo de $name';

  @override
  String cycleDaysLeft(int days) => 'En $days ${_n(days, 'día', 'días')}';

  @override
  String cycleDayOfCycle(int day) => 'Día $day del ciclo';

  @override
  String cycleOverdue(int days) =>
      '$days ${_n(days, 'día', 'días')} de retraso';

  @override
  String cycleAnalyticsHint(int cycles) =>
      'en los últimos $cycles ${_n(cycles, 'ciclo', 'ciclos')}';

  @override
  String cycleDaysValue(int days) => '$days ${_n(days, 'día', 'días')}';

  @override
  String cyclePeriodDayLabel(int day) => 'regla, día $day';

  @override
  String dayLogDate(DateTime day) =>
      '${day.day} ${cycleMonthsGenitive[day.month - 1]}';

  @override
  String dayLogWeekday(DateTime day) => longWeekdays[day.weekday - 1];

  // ── Открытки ────────────────────────────────────────────────────────────

  @override
  String pcReceiptShift(int days) => 'turno n.º $days';

  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Recuerdos — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Dibujos — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('Te echo de menos — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Días seguidos — ${stats.streak}');
    if (lines.isEmpty) lines.add('Esto acaba de empezar — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'De: ${from.isEmpty ? 'mí' : from}\n'
      'Contenido: $days días, todo intacto';

  // ── Подарки ─────────────────────────────────────────────────────────────

  @override
  String giftFromPartner(String name) => 'Un regalo de $name';

  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? '¡Se escapó!' : '¡Otra vez se escapó, atrápalo!';

  @override
  String giftIncomingCount(int n) => n == 1 ? 'espera' : '$n esperan';

  @override
  String giftMutualBonus(int coins) => 'En el momento justo: $coins cada uno';

  @override
  String giftSunriseGreeting(String name) =>
      '¡Buenos días! $name te envía un amanecer';

  @override
  String giftPushBody(String giftName) => 'Te ha enviado un regalo: $giftName';

  // ── Профиль партнёра и статистика ───────────────────────────────────────

  @override
  String partnerGiftsChip(int count) => '$count';

  @override
  String partnerMissChip(int count) => '$count';

  @override
  String partnerDaysTogether(int days) =>
      'juntos $days ${_n(days, 'día', 'días')}';

  @override
  String partnerMissPeak(String weekday) => 'Sobre todo $weekday';

  @override
  String weekdayShort(int weekday) => shortWeekdays[weekday - 1];

  /// «Sobre todo los lunes» — с артиклем, иначе фраза не строится.
  @override
  String weekdayLong(int weekday) => const [
    'los lunes',
    'los martes',
    'los miércoles',
    'los jueves',
    'los viernes',
    'los sábados',
    'los domingos',
  ][weekday - 1];

  // ── Совместный просмотр ─────────────────────────────────────────────────

  @override
  String watchWithPartner(String name) => 'Ver con $name';

  @override
  String watchVideoAdd(int mb) => 'Sube hasta $mb MB';

  @override
  String watchVideoTooBig(int mb) =>
      'El vídeo pasa de $mb MB: comprímelo o elige uno más corto';

  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName te invita a ver juntos';
}
