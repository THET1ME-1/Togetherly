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

  @override
  bool operator ==(Object other) =>
      other is LiveLocationTuning &&
      other.distanceFilter == distanceFilter &&
      other.highAccuracy == highAccuracy &&
      other.wakeLock == wakeLock &&
      other.pauseAutomatically == pauseAutomatically &&
      other.forceIndicator == forceIndicator;

  @override
  int get hashCode => Object.hash(
        distanceFilter,
        highAccuracy,
        wakeLock,
        pauseAutomatically,
        forceIndicator,
      );
}

/// Профиль под текущее состояние приложения.
///
/// На Android профиль ОДИН на всё время: там поток живёт foreground-сервисом,
/// и каждый его перезапуск заново показывает уведомление «Геопозиция
/// включена» — ровно то, на что жалуются («пишет раз в N времени, хотя она не
/// отключалась»). Поэтому вместо переключения профилей берём средний: шаг
/// крупнее, чем на экране, точность спутниковая, процессор не держим.
LiveLocationTuning liveLocationTuning({
  required bool foreground,
  bool android = false,
}) {
  if (android) {
    return const LiveLocationTuning(
      distanceFilter: 40,
      highAccuracy: true,
      wakeLock: false,
      pauseAutomatically: false,
      forceIndicator: false,
    );
  }
  if (foreground) {
    return const LiveLocationTuning(
      distanceFilter: 15,
      highAccuracy: true,
      wakeLock: true,
      pauseAutomatically: false,
      forceIndicator: false,
    );
  }
  // В фоне метку смотрят изредка, а платит за неё батарея: шаг крупнее,
  // точность сетевая, процессор не держим.
  return const LiveLocationTuning(
    distanceFilter: 80,
    highAccuracy: false,
    wakeLock: false,
    pauseAutomatically: true,
    forceIndicator: false,
  );
}
