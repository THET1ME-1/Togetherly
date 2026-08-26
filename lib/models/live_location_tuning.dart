/// Насколько часто будить GPS, пока пара делится геопозицией.
///
/// Метка партнёра на карте «Где мы» живёт в фоне — иначе она замирает в ту
/// секунду, когда человек уходит с экрана. Плата за это видна каждому: синяя
/// стрелка на iPhone, уведомление на Android и разряд батареи. Все три жалобы
/// 21.08.2026 про одно и то же, поэтому профиль зависит от того, смотрит ли
/// человек на экран.
class LiveLocationTuning {
  const LiveLocationTuning({
    required this.distanceFilter,
    required this.highAccuracy,
    required this.wakeLock,
    required this.pauseAutomatically,
    required this.forceIndicator,
    this.interval = const Duration(seconds: 30),
  });

  /// На сколько метров надо сместиться, чтобы точка ушла партнёру.
  final int distanceFilter;

  /// Спутниковая точность против сетевой.
  final bool highAccuracy;

  /// Держать процессор разбуженным (Android). В фоне это и есть «постоянно
  /// использует GPS» из жалобы.
  final bool wakeLock;

  /// Разрешить системе усыплять обновления, когда человек стоит на месте
  /// (iOS). Разбудит их она сама, по движению.
  final bool pauseAutomatically;

  /// Показывать синий индикатор принудительно (iOS). Ставили `true`, и стрелка
  /// висела в чужих приложениях постоянно; система показывает её и без нас,
  /// когда действительно берёт координаты в фоне.
  final bool forceIndicator;

  /// Как часто спрашивать координату у системы (Android). Держит расход в
  /// узде вместо снятого wake lock: процессор просыпается, но редко.
  final Duration interval;

  @override
  bool operator ==(Object other) =>
      other is LiveLocationTuning &&
      other.distanceFilter == distanceFilter &&
      other.highAccuracy == highAccuracy &&
      other.wakeLock == wakeLock &&
      other.pauseAutomatically == pauseAutomatically &&
      other.forceIndicator == forceIndicator &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(
        distanceFilter,
        highAccuracy,
        wakeLock,
        pauseAutomatically,
        forceIndicator,
        interval,
      );
}

/// Профиль под текущее состояние приложения.
///
/// На Android профиль ОДИН на всё время: там поток живёт foreground-сервисом,
/// и каждый его перезапуск заново показывает уведомление «Геопозиция
/// включена» — ровно то, на что жалуются («пишет раз в N времени, хотя она не
/// отключалась»). Поэтому вместо переключения профилей берём средний: шаг
/// крупнее, чем на экране, точность спутниковая, опрос редкий.
///
/// **Фон обязан работать.** Правка 21.08.2026 гасила расход двумя способами
/// разом — снятым wake lock на Android и `pauseLocationUpdatesAutomatically`
/// на iOS — и метка замирала, стоило свернуть приложение: «геопозиция
/// обновляется только при нахождении в приложении, даже когда в настройках
/// стоит „Всегда“, на iOS 26.6.1. В версии для Android такая же проблема»
/// (@melyron, 24.08.2026). Обе меры убивали саму фичу: без wake lock процессор
/// засыпает и координаты не доезжают, а усыплённые системой обновления iOS
/// сама не будит, пока человек не откроет приложение. Экономим иначе — редким
/// опросом и крупным шагом.
LiveLocationTuning liveLocationTuning({
  required bool foreground,
  bool android = false,
}) {
  if (android) {
    return const LiveLocationTuning(
      distanceFilter: 40,
      highAccuracy: true,
      wakeLock: true,
      pauseAutomatically: false,
      forceIndicator: false,
      interval: Duration(seconds: 60),
    );
  }
  if (foreground) {
    return const LiveLocationTuning(
      distanceFilter: 15,
      highAccuracy: true,
      wakeLock: true,
      pauseAutomatically: false,
      forceIndicator: false,
      interval: Duration(seconds: 10),
    );
  }
  // В фоне метку смотрят изредка, а платит за неё батарея: шаг крупнее и
  // точность сетевая. Усыплять обновления не даём — из этого сна их будит
  // только открытое приложение.
  //
  // **Индикатор в фоне вернули.** Гасили его 21.08.2026 из-за жалоб на синюю
  // стрелку — и вместе с ним пропало единственное видимое доказательство, что
  // приложение работает с геопозицией в фоне. App Review 26.08.2026 (заявка
  // b7ab1101, версия 1.31.0+218) отклонил сборку по 2.5.4: режим `location`
  // объявлен, а признаков персистентной геолокации ревьюер не нашёл. В
  // принятых 1.29.5–1.30.0 стрелка горела. Стрелка — цена режима, а не наша
  // прихоть: iOS показывает её всякому, кто читает координаты свёрнутым.
  return const LiveLocationTuning(
    distanceFilter: 80,
    highAccuracy: false,
    wakeLock: false,
    pauseAutomatically: false,
    forceIndicator: true,
    interval: Duration(seconds: 60),
  );
}
