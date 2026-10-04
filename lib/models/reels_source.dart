/// Откуда берутся ролики в «Лентах вдвоём».
///
/// Ленту каждой площадки держит приложение скрытым браузером (`ReelsFeed`),
/// смотрят оба официальным плеером площадки (`reels.js`). Где лежат номера
/// роликов, найдено разведкой 04.10.2026:
///
/// | площадка | лента | ответ с номерами | плеер |
/// |---|---|---|---|
/// | Shorts | m.youtube.com/shorts | `reel_watch_sequence` | YouTube API |
/// | TikTok | www.tiktok.com/foryou | `api/recommend/item_list` | `tiktok.com/player/v1` |
/// | Rutube | rutube.ru/shorts | `shorts/lenta` | `rutube.ru/play/embed` |
/// | ВК Клипы | m.vk.com/clips | `shortVideo.getRecom` | `vk.com/video_ext.php` |
/// | Дзен | dzen.ru/shorts | `video-recommend` | `dzen.ru/embed` |
///
/// Ключ площадки ([key]) должен совпадать с `SOURCES` и `FRAMES` в reels.js.
enum ReelsSource {
  shorts('shorts', 'Shorts', 'https://m.youtube.com/shorts/'),
  tiktok('tiktok', 'TikTok', 'https://www.tiktok.com/foryou', desktop: true),
  rutube('rutube', 'Rutube', 'https://rutube.ru/shorts/'),
  vkClips('vk', 'ВК Клипы', 'https://m.vk.com/clips'),
  dzen('dzen', 'Дзен', 'https://dzen.ru/shorts');

  const ReelsSource(this.key, this.title, this.home, {this.desktop = false});

  /// Метка площадки в адресе комнаты (`?feed=`) и в ключах роликов.
  final String key;

  /// Имя площадки — собственное, не переводится.
  final String title;

  /// Откуда скрытый браузер начинает ленту.
  final String home;

  /// Лента открывается как на компьютере: мобильный TikTok зовёт ставить
  /// приложение вместо ленты.
  final bool desktop;

  /// Значок площадки в листе выбора.
  String get icon => 'assets/images/reels/$key.png';

  /// Страница ролика: скрытый браузер открывает её без звука, пока ролик идёт
  /// в комнате, — площадка засчитывает просмотр и подстраивает рекомендации.
  /// Пусто — у площадки так не выходит, лента учится на своих показах.
  String watchUrl(String id) => switch (this) {
        ReelsSource.shorts => 'https://m.youtube.com/shorts/$id',
        ReelsSource.rutube => 'https://rutube.ru/shorts/$id/',
        _ => '',
      };

  static ReelsSource byKey(String key) =>
      ReelsSource.values.firstWhere((s) => s.key == key, orElse: () => ReelsSource.shorts);
}
