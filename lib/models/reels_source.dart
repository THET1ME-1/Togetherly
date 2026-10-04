/// Откуда берутся ролики в «Лентах вдвоём».
///
/// Ленту каждой площадки держит приложение скрытым браузером, смотрят оба
/// официальным плеером площадки. Пока это умеет только YouTube Shorts;
/// остальные стоят в списке выбора с пометкой «скоро», чтобы человек видел,
/// что будет, а не решил, что выбора нет вовсе.
enum ReelsSource {
  shorts('Shorts', 'YT', available: true),
  tiktok('TikTok', 'TT'),
  rutube('Rutube', 'Rt'),
  vkClips('ВК Клипы', 'ВК'),
  dzen('Дзен', 'Дз');

  const ReelsSource(this.title, this.badge, {this.available = false});

  /// Имя площадки — собственное, не переводится.
  final String title;

  /// Две буквы на значке строки.
  final String badge;

  /// Работает уже сейчас.
  final bool available;
}
